#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Focuselle -name '*.swift' ! -path '*/App/*' -print | sort)
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
    "${sources[@]}" scripts/render-preview.swift -lsqlite3 -o .build/RenderPreview
.build/RenderPreview
