#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/Focuselle.app/Contents/Info.plist)
stage="$PWD/.build/dmg-stage"
mkdir -p "$stage" landing/dist/downloads
# Only the package's own staging directory is refreshed; user data is never included.
if [[ -d "$stage/Focuselle.app" ]]; then rm -rf "$stage/Focuselle.app"; fi
ditto .build/Focuselle.app "$stage/Focuselle.app"
ln -sfn /Applications "$stage/Applications"
cp Focuselle/Resources/AppIcon.icns "$stage/.VolumeIcon.icns"
cat > "$stage/Read me.txt" <<TEXT
Focuselle $version — Early access

macOS 14 or newer · Apple Silicon (M1 or newer)
Drag Focuselle.app to Applications.

This early build has an ad hoc signature and is not notarized by Apple.
macOS Gatekeeper may prevent a downloaded copy from opening.
A signed public release is still in preparation.

Tasks and focus sessions stay on your Mac.
Source: https://github.com/mrDisa/Focuselle
TEXT
output="$PWD/landing/dist/downloads/Focuselle-$version-arm64.dmg"
# Build the HFS filesystem in a file; this also works without attaching a virtual disk.
hdiutil makehybrid -hfs -hfs-volume-name Focuselle -o "$PWD/.build/Focuselle-hybrid.dmg" -ov "$stage"
hdiutil convert "$PWD/.build/Focuselle-hybrid.dmg" -format UDZO -o "$output" -ov
hdiutil verify "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
printf 'Packaged: %s\n' "$output"
