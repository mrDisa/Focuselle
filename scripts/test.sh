#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" \
    Focuselle/Models/FocusTimer.swift Tests/FocusTimerTests.swift -o .build/FocusTimerTests
.build/FocusTimerTests
