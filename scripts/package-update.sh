#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Optional output directory permits staging releases without changing the website.
output="${1:-$PWD/landing/dist}"
sdk=$(./scripts/prepare-sparkle.sh)
if [[ ! -f "$sdk/.verified-sdk" && "${FOCUS_ALLOW_LOCAL_SDK:-0}" != 1 ]]; then
    echo 'Release packaging requires the official checksum-verified Sparkle SDK. Refresh .build/Sparkle-2.9.1 with prepare-sparkle.sh.' >&2
    exit 1
fi
./scripts/build.sh
app="$PWD/.build/Focuselle.app"
public_key=$(./scripts/update-signing.sh public-key)
bundled_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
[[ "$public_key" == "$bundled_key" ]] || { echo 'Signing key does not match the application public key' >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p "$output/downloads"
archive="$output/downloads/Focuselle-$version-$(uname -m).zip"
[[ ! -e "$archive" ]] || { echo 'Update archive already exists; bump version/build for a new release' >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
signature=$(./scripts/update-signing.sh sign "$archive")
./scripts/update-signing.sh verify "$archive" "$public_key" "$signature"
python3 scripts/create-appcast.py --app "$app" --archive "$archive" \
    --signature "$signature" --output "$output/appcast.xml" \
    --base-url "https://github.com/mrDisa/Focuselle/releases/download/v$version/"
(cd "$output/downloads" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Prepared signed update: %s\nFeed: %s/appcast.xml\n' "$archive" "$output"
