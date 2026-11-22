#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d "$PWD/.build/signature-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
export FOCUS_SIGNING_KEY_FILE="$fixture/private-key"
public_key=$(./scripts/update-signing.sh init)
printf 'signed update fixture' > "$fixture/archive.zip"
signature=$(./scripts/update-signing.sh sign "$fixture/archive.zip")
./scripts/update-signing.sh verify "$fixture/archive.zip" "$public_key" "$signature"
printf 'tampered' >> "$fixture/archive.zip"
if ./scripts/update-signing.sh verify "$fixture/archive.zip" "$public_key" "$signature" 2>/dev/null; then
    echo 'FAIL: altered archive accepted' >&2
    exit 1
fi
printf 'Passed: Ed25519 signing, verification and tamper rejection\n'
