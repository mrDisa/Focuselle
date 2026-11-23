#!/bin/bash
# Prepare an update signing key on the release runner without publishing private bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'This helper runs only in GitHub Actions.' >&2; exit 1; }
key_dir="$RUNNER_TEMP/focuselle-signing-$GITHUB_RUN_ID"
mkdir -p "$key_dir"
chmod 700 "$key_dir"
key_file="$key_dir/update.seed"
export FOCUS_SIGNING_KEY_FILE="$key_file"
if [[ -n "${FOCUS_UPDATE_SIGNING_KEY_B64:-}" ]]; then
    python3 - "$key_file" <<'PY'
import base64, os, pathlib, sys
key = base64.b64decode(os.environ['FOCUS_UPDATE_SIGNING_KEY_B64'], validate=True)
if len(key) != 32: raise SystemExit('Expected a 32-byte update signing seed')
p = pathlib.Path(sys.argv[1]); p.write_bytes(key); p.chmod(0o600)
PY
else
    # One-time encrypted handoff to this exact runner. Only the ephemeral public key
    # and an RSA-OAEP encrypted response enter Git; the RSA private key stays here.
    : "${GH_TOKEN:?GitHub token is required for the signing handoff}"
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$key_dir/transport.pem" 2>/dev/null
    openssl pkey -in "$key_dir/transport.pem" -pubout -out "$key_dir/public.pem" 2>/dev/null
    trap 'rm -f "$key_dir/transport.pem" "$key_dir/response.bin"' EXIT
    python3 - "$key_dir" <<'PY'
import datetime, json, os, pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1])
info = plistlib.loads(pathlib.Path('Focuselle/Info.plist').read_bytes())
request = {'runId': os.environ['GITHUB_RUN_ID'], 'sourceCommit': os.environ['GITHUB_SHA'],
           'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
           'publicKey': (p/'public.pem').read_text(),
           'expiresAt': (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=12)).isoformat()}
(p/'request.json').write_text(json.dumps(request))
PY
    # Update a coordination file outside the workflow's source-path trigger list.
    request_path="repos/$GITHUB_REPOSITORY/contents/releases/update-signing-request.json"
    previous_sha=$(gh api "$request_path" --jq .sha 2>/dev/null || true)
    python3 - "$key_dir" "$previous_sha" <<'PY'
import base64, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
payload = {'message': 'chore: request encrypted signing for release',
           'content': base64.b64encode((p/'request.json').read_bytes()).decode(), 'branch': 'main'}
if sys.argv[2]: payload['sha'] = sys.argv[2]
(p/'request-payload.json').write_text(json.dumps(payload))
PY
    gh api --method PUT "$request_path" --input "$key_dir/request-payload.json" > /dev/null
    echo "Waiting for encrypted signing response for run $GITHUB_RUN_ID"
    received=0
    for attempt in $(seq 1 72); do
        if gh api "repos/$GITHUB_REPOSITORY/contents/releases/update-signing-envelope.json?ref=main" > "$key_dir/response.json" 2>/dev/null; then
            if python3 - "$key_dir" <<'PY'
import base64, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); request = json.loads((p/'request.json').read_text())
response = json.loads(base64.b64decode(json.loads((p/'response.json').read_text())['content']))
if any(response.get(k) != request[k] for k in ('runId', 'sourceCommit', 'version', 'build')): raise SystemExit(1)
cipher = base64.b64decode(response['ciphertext'], validate=True)
if len(cipher) != 384: raise SystemExit(1)
(p/'response.bin').write_bytes(cipher)
PY
            then
                openssl pkeyutl -decrypt -inkey "$key_dir/transport.pem" -in "$key_dir/response.bin" \
                    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -out "$key_file"
                chmod 600 "$key_file"
                received=1
                break
            fi
        fi
        sleep 10
    done
    [[ "$received" == 1 ]] || { echo 'No matching encrypted signing response received.' >&2; exit 1; }
fi
expected=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Focuselle/Info.plist)
actual=$(./scripts/update-signing.sh public-key)
[[ "$actual" == "$expected" ]] || { echo 'Release signing key does not match the installed app.' >&2; exit 1; }
printf 'FOCUS_SIGNING_KEY_FILE=%s\n' "$key_file" >> "$GITHUB_ENV"
echo 'Release signing key verified.'
