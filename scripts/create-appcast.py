#!/usr/bin/env python3
"""Create a Sparkle feed entry from an already signed application archive."""
import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)

def tag(name):
    return '{' + SPARKLE + '}' + name

def create(app, archive, signature, output, base_url='https://mrdisa.github.io/Focuselle/'):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('Release requires a stable version and a positive integer build number')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Expected an Ed25519 signature')
    if not info.get('SUPublicEDKey') or not info.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('Application must require signed updates before extraction')
    with zipfile.ZipFile(archive) as bundle:
        archived_info = plistlib.loads(bundle.read('Focuselle.app/Contents/Info.plist'))
    for key in ('CFBundleVersion', 'CFBundleShortVersionString', 'CFBundleIdentifier', 'SUPublicEDKey'):
        if info[key] != archived_info[key]:
            raise ValueError('Archive does not match the built application: ' + key)
    if output.exists():
        tree = ET.parse(output)
        root = tree.getroot()
        channel = root.find('channel')
        if root.tag != 'rss' or channel is None:
            raise ValueError('Invalid existing appcast')
        for old in channel.findall('item'):
            old_build = old.findtext(tag('version'), '0')
            if int(old_build) >= int(build):
                raise ValueError('Build numbers must increase; never replace a published update')
    else:
        root = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(root, 'channel')
        ET.SubElement(channel, 'title').text = 'Focuselle'
        ET.SubElement(channel, 'link').text = base_url
        ET.SubElement(channel, 'description').text = 'Focuselle updates'
        tree = ET.ElementTree(root)
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = 'Focuselle ' + version
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, tag('version')).text = build
    ET.SubElement(item, tag('shortVersionString')).text = version
    ET.SubElement(item, tag('minimumSystemVersion')).text = info.get('LSMinimumSystemVersion', '14.0')
    ET.SubElement(item, 'enclosure', {
        'url': base_url.rstrip('/') + '/downloads/' + archive.name,
        'length': str(archive.stat().st_size),
        'type': 'application/octet-stream',
        tag('edSignature'): signature,
    })
    channel.insert(3, item)
    ET.indent(tree, space='  ')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.xml.tmp')
    tree.write(temporary, encoding='utf-8', xml_declaration=True)
    temporary.replace(output)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, type=pathlib.Path)
    parser.add_argument('--archive', required=True, type=pathlib.Path)
    parser.add_argument('--signature', required=True)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    parser.add_argument('--base-url', default='https://mrdisa.github.io/Focuselle/')
    args = parser.parse_args()
    create(args.app, args.archive, args.signature, args.output, args.base_url)
