import copy
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('envelope', ROOT/'scripts/make-signing-envelope.py')
envelope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(envelope)

class ReleaseSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.key = cls.root/'fixture.seed'
        cls.key.write_bytes(bytes(range(32)))
        cls.key.chmod(0o600)
        cls.transport = cls.root/'transport.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:3072', '-out', str(cls.transport)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(cls.transport), '-pubout'], text=True, stderr=subprocess.DEVNULL)
        ed_public = subprocess.check_output([str(ROOT/'scripts/update-signing.sh'), 'public-key'], env=dict(os.environ, FOCUS_SIGNING_KEY_FILE=str(cls.key)), text=True).strip()
        cls.info = {'CFBundleShortVersionString':'0.4.0', 'CFBundleVersion':'4', 'SUPublicEDKey':ed_public}
        cls.request = {'runId':'123', 'sourceCommit':'a'*40, 'version':'0.4.0', 'build':'4', 'publicKey':public,
                       'expiresAt':(dt.datetime.now(dt.timezone.utc)+dt.timedelta(minutes=5)).isoformat()}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_round_trip_without_plaintext_in_response(self):
        target = self.root/'envelope.json'
        response = envelope.create(self.request, target, self.key, 'a'*40, '123', self.info)
        import base64
        ciphertext = base64.b64decode(response['ciphertext'])
        encrypted = self.root/'encrypted.bin'; encrypted.write_bytes(ciphertext)
        actual = subprocess.check_output(['openssl', 'pkeyutl', '-decrypt', '-inkey', str(self.transport), '-in', str(encrypted),
            '-pkeyopt', 'rsa_padding_mode:oaep', '-pkeyopt', 'rsa_oaep_md:sha256', '-pkeyopt', 'rsa_mgf1_md:sha256'])
        self.assertEqual(actual, self.key.read_bytes())
        self.assertNotIn(base64.b64encode(actual).decode(), target.read_text())

    def test_rejects_another_run_commit_or_release(self):
        for field, value in [('runId','124'), ('sourceCommit','b'*40), ('version','0.5.0'), ('build','5')]:
            request = copy.deepcopy(self.request); request[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                envelope.create(request, self.root/'rejected.json', self.key, 'a'*40, '123', self.info)

    def test_rejects_expired_request(self):
        request = dict(self.request, expiresAt=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=1)).isoformat())
        with self.assertRaises(ValueError):
            envelope.create(request, self.root/'rejected.json', self.key, 'a'*40, '123', self.info)

    def test_rejects_wrong_ed25519_key(self):
        info = dict(self.info, SUPublicEDKey='wrong key')
        with self.assertRaises(ValueError):
            envelope.create(self.request, self.root/'rejected.json', self.key, 'a'*40, '123', info)

if __name__ == '__main__':
    unittest.main()
