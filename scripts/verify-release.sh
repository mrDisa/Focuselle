#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Focuselle/Info.plist)
dmg="$PWD/landing/dist/downloads/Focuselle-$version-arm64.dmg"
mount=$(mktemp -d "$PWD/.build/verify-dmg.XXXXXX")
cleanup() {
    hdiutil detach "$mount" -quiet || true
    rmdir "$mount" || true
}
trap cleanup EXIT
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount"
python3 scripts/verify-release.py "$mount/Focuselle.app" "$dmg"
(cd landing/dist/downloads && shasum -a 256 -c "Focuselle-$version-arm64.dmg.sha256")
