#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
app="$PWD/.build/Focuselle.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Focuselle -name '*.swift' -print | sort)
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$PWD/.build/module-cache" \
    "${sources[@]}" -o "$app/Contents/MacOS/Focuselle"
cp Focuselle/Info.plist "$app/Contents/Info.plist"
# CLT does not ship xcstringstool. Compile the same catalog into .strings here.
python3 - "$app/Contents/Resources" <<'PY'
import json, pathlib, sys
catalog = json.loads(pathlib.Path('Focuselle/Resources/Localizable.xcstrings').read_text())
for lang in ('ru', 'en'):
    folder = pathlib.Path(sys.argv[1]) / (lang + '.lproj')
    folder.mkdir(exist_ok=True)
    rows = []
    for key, entry in catalog['strings'].items():
        value = entry['localizations'][lang]['stringUnit']['value']
        rows.append(json.dumps(key, ensure_ascii=False) + ' = ' + json.dumps(value, ensure_ascii=False) + ';')
    (folder / 'Localizable.strings').write_text('\n'.join(rows) + '\n')
PY
codesign --force --sign - "$app"
printf 'Built: %s\n' "$app"
if [[ "${1:-}" == "--run" ]]; then open "$app"; fi
