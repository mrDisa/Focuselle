#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/protection-probe .build/module-cache
probe_dir="$PWD/.build/protection-probe"
target="$(uname -m)-apple-macosx14.0"
compile=(xcrun swiftc -typecheck -swift-version 5 -target "$target" -module-cache-path "$PWD/.build/module-cache")

{
    printf 'Focuselle protection API probe (compile only)\n'
    printf 'Target: %s\n' "$target"
    xcrun --show-sdk-version
    "${compile[@]}" Probes/FocusProtection/AvailableAPIs.swift
    printf 'PASS: AppKit, NetworkExtension, SystemExtensions, SafariServices, EndpointSecurity declarations\n'
    for name in FamilyControls ManagedSettings; do
        if "${compile[@]}" "Probes/FocusProtection/Unavailable${name}.swift" > "$probe_dir/$name.log" 2>&1; then
            printf 'CHANGED: %s now compiles on native macOS; revisit the research\n' "$name"
            exit 1
        fi
        # An unrelated compiler failure must not be mistaken for platform unavailability.
        if ! /usr/bin/grep -q 'unavailable in macOS' "$probe_dir/$name.log"; then
            cat "$probe_dir/$name.log"
            exit 1
        fi
        printf 'PASS: %s rejects its control API on native macOS as expected\n' "$name"
    done
    printf 'No APIs were executed, permissions requested, or system settings changed.\n'
    printf 'Availability does not prove entitlement eligibility or runtime filtering.\n'
} | tee "$probe_dir/report.txt"
