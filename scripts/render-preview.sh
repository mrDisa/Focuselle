#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
sparkle_sdk=$(./scripts/prepare-sparkle.sh)
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Focuselle -name '*.swift' ! -path '*/App/*' -print | sort)
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
    "${sources[@]}" scripts/render-preview.swift -F "$sparkle_sdk" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle_sdk" -lsqlite3 -o .build/RenderPreview
.build/RenderPreview
