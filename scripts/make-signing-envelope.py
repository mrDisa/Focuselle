#!/usr/bin/env python3
"""Encrypt the existing update seed for one verified release runner; never print it."""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def create(request, destination, key_file, expected_commit, expected_run, info):
    if request.get('sourceCommit') != expected_commit or request.get('runId') != str(expected_run):
        raise ValueError('Signing request belongs to another commit or workflow run')
    if request.get('version') != info['CFBundleShortVersionString'] or request.get('build') != info['CFBundleVersion']:
        raise ValueError('Signing request belongs to another release')
    if dt.datetime.fromisoformat(request['expiresAt']) <= dt.datetime.now(dt.timezone.utc):
        raise ValueError('Signing request has expired')
    if key_file.stat().st_mode & 0o077:
        raise ValueError('Update signing seed must have private file permissions')
    env = dict(os.environ, FOCUS_SIGNING_KEY_FILE=str(key_file.resolve()))
    public = subprocess.check_output([str(ROOT/'scripts/update-signing.sh'), 'public-key'], env=env, text=True).strip()
    if public != info['SUPublicEDKey']:
        raise ValueError('Signing seed does not match the public key shipped in the app')
    with tempfile.TemporaryDirectory(prefix='focuselle-envelope-') as folder:
        public_file = Path(folder)/'runner-public.pem'
        public_file.write_text(request['publicKey'])
        # SHA-256 OAEP and a 3072-bit per-run RSA key protect the 32-byte seed.
        encrypted = subprocess.check_output(['openssl', 'pkeyutl', '-encrypt', '-pubin', '-inkey', str(public_file),
            '-pkeyopt', 'rsa_padding_mode:oaep', '-pkeyopt', 'rsa_oaep_md:sha256',
            '-pkeyopt', 'rsa_mgf1_md:sha256', '-in', str(key_file)])
    if len(encrypted) != 384:
        raise ValueError('Expected the release runner’s 3072-bit RSA public key')
    envelope = {k: request[k] for k in ('runId', 'sourceCommit', 'version', 'build')}
    envelope['publicKeySHA256'] = hashlib.sha256(request['publicKey'].encode()).hexdigest()
    envelope['ciphertext'] = base64.b64encode(encrypted).decode()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(envelope, indent=2)+'\n')
    return envelope

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('request', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--key-file', type=Path, default=ROOT/'.secrets/focuselle-ed25519.key')
    args = parser.parse_args()
    info = plistlib.loads((ROOT/'Focuselle/Info.plist').read_bytes())
    create(json.loads(args.request.read_text()), args.destination, args.key_file, args.commit, args.run, info)
    print('Encrypted signing response prepared. Private key was not printed.')
