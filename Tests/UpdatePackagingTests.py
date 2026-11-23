import base64
import importlib.util
import pathlib
import re
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

spec = importlib.util.spec_from_file_location('appcast', pathlib.Path(__file__).resolve().parents[1] / 'scripts/create-appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)

class UpdatePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.app = self.root / 'Focuselle.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.feed = self.root / 'appcast.xml'
        self.signature = base64.b64encode(bytes(64)).decode()
        self.info = {'CFBundleShortVersionString': '0.3.0', 'CFBundleVersion': '3',
                     'CFBundleIdentifier': 'dev.focuselle.local', 'SUPublicEDKey': 'fixture',
                     'SUVerifyUpdateBeforeExtraction': True, 'LSMinimumSystemVersion': '14.0'}

    def tearDown(self):
        self.temp.cleanup()

    def archive(self, build='3'):
        self.info['CFBundleVersion'] = build
        data = plistlib.dumps(self.info)
        (self.app / 'Contents/Info.plist').write_bytes(data)
        archive = self.root / ('Focuselle-' + build + '.zip')
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('Focuselle.app/Contents/Info.plist', data)
        return archive

    def test_landing_downloads_match_current_release(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        info = plistlib.loads((root/'Focuselle/Info.plist').read_bytes())
        version = info['CFBundleShortVersionString']
        html = (root/'landing/dist/index.html').read_text()
        links = re.findall(r'href="(downloads/[^\"]+\.dmg)"', html)
        self.assertGreaterEqual(len(links), 2)
        self.assertEqual(set(links), {'downloads/Focuselle-' + version + '-arm64.dmg'})
        self.assertIn('V' + version + ' / EARLY ACCESS', html)

    def test_signed_feed_metadata_and_history(self):
        archive = self.archive()
        appcast.create(self.app, archive, self.signature, self.feed)
        enclosure = ET.parse(self.feed).find('channel/item/enclosure')
        self.assertEqual(enclosure.get(appcast.tag('edSignature')), self.signature)
        self.assertEqual(enclosure.get('length'), str(archive.stat().st_size))
        self.assertTrue(enclosure.get('url').startswith('https://mrdisa.github.io/Focuselle/downloads/'))
        appcast.create(self.app, self.archive('4'), self.signature, self.feed)
        builds = [i.findtext(appcast.tag('version')) for i in ET.parse(self.feed).findall('channel/item')]
        self.assertEqual(builds, ['4', '3'])

    def test_refuses_duplicate_or_downgrade(self):
        archive = self.archive('4')
        appcast.create(self.app, archive, self.signature, self.feed)
        for build in ['4', '3']:
            with self.assertRaises(ValueError):
                appcast.create(self.app, self.archive(build), self.signature, self.feed)

    def test_refuses_mismatched_archive(self):
        archive = self.archive()
        self.info['CFBundleVersion'] = '5'
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        with self.assertRaises(ValueError):
            appcast.create(self.app, archive, self.signature, self.feed)

    def test_refuses_unsigned_or_invalid_signature(self):
        archive = self.archive()
        with self.assertRaises(ValueError):
            appcast.create(self.app, archive, 'invalid', self.feed)
        self.info['SUVerifyUpdateBeforeExtraction'] = False
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        with self.assertRaises(ValueError):
            appcast.create(self.app, archive, self.signature, self.feed)

if __name__ == '__main__':
    unittest.main()
