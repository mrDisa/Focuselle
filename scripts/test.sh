#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" \
    Focuselle/Models/FocusTimer.swift Tests/FocusTimerTests.swift -o .build/FocusTimerTests
.build/FocusTimerTests
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" \
    Focuselle/Models/FocusTimer.swift Focuselle/Models/Records.swift \
    Focuselle/Models/SessionController.swift Focuselle/Storage/Database.swift \
    Focuselle/Storage/FocusStore.swift Tests/StorageTests.swift -lsqlite3 -o .build/StorageTests
.build/StorageTests
