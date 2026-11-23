#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Focuselle/Info.plist)
tag="v$version"
if gh release view "$tag" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
    echo 'Release already exists. Published update archives must never be replaced.' >&2
    exit 1
fi
gh release create "$tag" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --title "Focuselle $version" --notes 'Classic and Olive themes, nine interface languages, refined focus controls and interface fixes. Update from the app or download the installer.' \
    "landing/dist/downloads/Focuselle-$version-arm64.dmg" \
    "landing/dist/downloads/Focuselle-$version-arm64.dmg.sha256" \
    "landing/dist/downloads/Focuselle-$version-arm64.zip" \
    "landing/dist/downloads/Focuselle-$version-arm64.zip.sha256"
