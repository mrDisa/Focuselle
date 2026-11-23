#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk=$(./scripts/prepare-sparkle.sh)
if [[ ! -f "$sdk/.verified-sdk" ]]; then
    echo 'Installer packaging requires the official checksum-verified Sparkle SDK. Run scripts/prepare-sparkle.sh --refresh.' >&2
    exit 1
fi
./scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/Focuselle.app/Contents/Info.plist)
stage="$PWD/.build/dmg-stage"
mkdir -p "$stage" landing/dist/downloads
# Only the package's own staging directory is refreshed; user data is never included.
if [[ -d "$stage/Focuselle.app" ]]; then rm -rf "$stage/Focuselle.app"; fi
ditto --noextattr --norsrc --noqtn .build/Focuselle.app "$stage/Focuselle.app"
xattr -cr "$stage/Focuselle.app"
codesign --verify --deep --strict "$stage/Focuselle.app"
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
# Finder needs the custom-icon attribute on the volume, as well as .VolumeIcon.icns.
# Set it on a writable image before creating the compressed installer.
writable="$PWD/.build/Focuselle-installer-rw.dmg"
mount=$(mktemp -d "$PWD/.build/installer-volume.XXXXXX")
cleanup() {
    if [[ -e "$mount/Focuselle.app" ]]; then
        hdiutil detach "$mount" -quiet || true
    fi
    rmdir "$mount" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil create -volname Focuselle -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$writable"
hdiutil attach "$writable" -nobrowse -noautoopen -mountpoint "$mount"
SetFile -a C "$mount"
hdiutil detach "$mount" -quiet
hdiutil convert "$writable" -format UDZO -o "$output" -ov
hdiutil verify "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
printf 'Packaged: %s\n' "$output"
