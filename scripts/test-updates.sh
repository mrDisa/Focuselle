#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
sdk=$(./scripts/prepare-sparkle.sh)
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
    Focuselle/Models/AppUpdate.swift Tests/UpdateDiscoveryTests.swift \
    -F "$sdk" -framework Sparkle -Xlinker -rpath -Xlinker "$sdk" -o .build/UpdateDiscoveryTests
.build/UpdateDiscoveryTests
# CI runs real HTTP discovery; the managed local sandbox forbids loopback listeners.
if [[ "${GITHUB_ACTIONS:-}" != true && "${FOCUS_TEST_NETWORK:-0}" != 1 ]]; then
    echo 'SKIP: real Sparkle HTTP integration runs in CI (local loopback is restricted).'
    exit 0
fi
test_dir=$(mktemp -d "$PWD/.build/update-feed.XXXXXX")
python3 Tests/ServeUpdateFeed.py "$test_dir/url" "$test_dir/counts.json" > "$test_dir/server.log" 2>&1 &
feed_pid=$!
cleanup() { kill "$feed_pid" 2>/dev/null || true; rm -rf "$test_dir"; }
trap cleanup EXIT
for attempt in $(seq 1 50); do
    [[ -f "$test_dir/url" ]] && break
    sleep 0.1
done
[[ -f "$test_dir/url" ]] || { cat "$test_dir/server.log"; exit 1; }
probe="$PWD/.build/UpdateDiscoveryHost.app"
mkdir -p "$probe/Contents/MacOS"
python3 - "$probe/Contents/Info.plist" "$test_dir/url" <<'PYCODE'
import pathlib, plistlib, sys
info = {'CFBundleIdentifier':'dev.focuselle.update-discovery-probe', 'CFBundleExecutable':'Host',
        'CFBundleName':'UpdateDiscoveryProbe', 'CFBundlePackageType':'APPL',
        'CFBundleVersion':'4', 'CFBundleShortVersionString':'0.4.0', 'LSMinimumSystemVersion':'14.0',
        'SUFeedURL':pathlib.Path(sys.argv[2]).read_text(), 'SUEnableAutomaticChecks':True,
        'SUScheduledCheckInterval':86400, 'SUAutomaticallyUpdate':False, 'SUAllowsAutomaticUpdates':False,
        'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},
        'SUPublicEDKey':'qfDMhzyX3RoBmZlYzfC4Ug9A/4/OQwcddUwvoHnGOnU=', 'SUVerifyUpdateBeforeExtraction':True}
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PYCODE
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
    Focuselle/Models/AppUpdate.swift Tests/BackgroundUpdateIntegration.swift \
    -F "$sdk" -framework Sparkle -Xlinker -rpath -Xlinker "$sdk" -o .build/BackgroundUpdateIntegration
cp .build/UpdateDiscoveryTests "$probe/Contents/MacOS/Host"
.build/BackgroundUpdateIntegration "$test_dir/counts.json"
