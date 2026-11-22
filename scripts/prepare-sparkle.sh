#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.9.1
sdk="$PWD/.build/Sparkle-$version"
if [[ -d "$sdk/Sparkle.framework" && "${1:-}" != --refresh ]]; then
    printf '%s\n' "$sdk"
    exit 0
fi
mkdir -p "$sdk"
archive="$PWD/.build/Sparkle-$version.tar.xz"
curl --fail --location --retry 2 --connect-timeout 15 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
expected=c0dde519fd2a43ddfc6a1eb76aec284d7d888fe281414f9177de3164d98ba4c7
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
[[ "$actual" == "$expected" ]] || { echo 'Sparkle SDK checksum mismatch' >&2; exit 1; }
stage=$(mktemp -d "$PWD/.build/sparkle-extract.XXXXXX")
trap 'rm -rf "$stage"' EXIT
tar -xf "$archive" -C "$stage"
[[ -d "$stage/Sparkle.framework" ]] || { echo 'Sparkle SDK archive has no framework' >&2; exit 1; }
# Refresh only this dependency's generated cache, after the download was verified.
rm -rf "$sdk"
mv "$stage" "$sdk"
printf '%s\n' "$expected" > "$sdk/.verified-sdk"
printf '%s\n' "$sdk"
