#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
sparkle_sdk=$(./scripts/prepare-sparkle.sh)
app="$PWD/.build/Focuselle.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Focuselle -name '*.swift' -print | sort)
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$PWD/.build/module-cache" \
    "${sources[@]}" -F "$sparkle_sdk" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -lsqlite3 -o "$app/Contents/MacOS/Focuselle"
mkdir -p "$app/Contents/Frameworks"
ditto "$sparkle_sdk/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
if [[ -f Focuselle/Resources/AppIcon.icns ]]; then cp Focuselle/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"; fi
if [[ -f Focuselle/Resources/AppIconLight.png ]]; then cp Focuselle/Resources/AppIconLight.png "$app/Contents/Resources/AppIconLight.png"; fi
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
# Preserve Sparkle's signed helper applications; only sign the host for local builds.
# A public notarized release must use the same Developer ID identity for embedded code.
identity="${FOCUS_CODE_SIGN_IDENTITY:--}"
if [[ "$identity" != - ]]; then
    codesign --force --sign "$identity" --options runtime --timestamp "$app/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign "$identity" --options runtime --timestamp "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
if [[ "${1:-}" == "--run" ]]; then open "$app"; fi
