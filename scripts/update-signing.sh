#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
if [[ ! -x .build/update-signing || scripts/update-signing.swift -nt .build/update-signing ]]; then
    xcrun swiftc -module-cache-path "$PWD/.build/module-cache" scripts/update-signing.swift -o .build/update-signing
fi
if [[ -z "${FOCUS_SIGNING_KEY_FILE:-}" && -f "$PWD/.secrets/focuselle-ed25519.key" ]]; then
    export FOCUS_SIGNING_KEY_FILE="$PWD/.secrets/focuselle-ed25519.key"
fi
exec .build/update-signing "$@"
