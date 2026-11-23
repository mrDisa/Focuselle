#!/usr/bin/env python3
"""Verify the actual app in a mounted installer before allowing deployment."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app, dmg = map(Path, sys.argv[1:])
expected = plistlib.loads(Path('Focuselle/Info.plist').read_bytes())
actual = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
for key in ('CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleIdentifier', 'SUPublicEDKey', 'SUFeedURL'):
    if expected[key] != actual[key]:
        raise SystemExit('Installer metadata mismatch: ' + key)
icon = Path('Focuselle/Resources/AppIcon.icns').read_bytes()
if (app / 'Contents/Resources/AppIcon.icns').read_bytes() != icon:
    raise SystemExit('Installer contains an outdated application icon')
if (app.parent / '.VolumeIcon.icns').read_bytes() != icon:
    raise SystemExit('Installer volume icon does not match the app')
attributes = subprocess.check_output(['GetFileInfo', '-a', str(app.parent)], text=True).strip()
if 'C' not in attributes:
    raise SystemExit('Installer volume custom icon is not enabled')
version = actual['CFBundleShortVersionString']
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Invalid release version')
architectures = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/Focuselle')], text=True).split()
if architectures != ['arm64']:
    raise SystemExit('Installer must contain the Apple Silicon build')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
sdk = Path('.build/Sparkle-2.9.1')
if not (sdk / '.verified-sdk').exists():
    raise SystemExit('Release requires the official verified Sparkle SDK')
framework_info = plistlib.loads((app / 'Contents/Frameworks/Sparkle.framework/Resources/Info.plist').read_bytes())
if framework_info['CFBundleShortVersionString'] != '2.9.1':
    raise SystemExit('Unexpected embedded Sparkle version')
index = Path('landing/dist/index.html').read_text()
links = re.findall(r'href="(downloads/[^\"]+\.dmg)"', index)
expected_link = 'downloads/' + dmg.name
if len(links) < 2 or any(link != expected_link for link in links):
    raise SystemExit('Landing download buttons do not point to the new installer')
metadata = {
    'version': version,
    'build': actual['CFBundleVersion'],
    'architecture': 'arm64',
    'downloadURL': 'https://mrdisa.github.io/Focuselle/' + expected_link,
    'sha256': hashlib.sha256(dmg.read_bytes()).hexdigest(),
    'sourceCommit': os.environ.get('GITHUB_SHA', ''),
    'sparkleVersion': framework_info['CFBundleShortVersionString'],
    'sparkleSDKVerified': True,
}
Path('landing/dist/release.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('Verified installer:', version, 'build', actual['CFBundleVersion'])
print('SHA-256:', metadata['sha256'])
