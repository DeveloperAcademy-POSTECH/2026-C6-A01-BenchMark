#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -D DEBUG -module-cache-path "${TMPDIR:-/tmp}/oi-clip-module-cache" -parse-as-library \
 "$IOS_ROOT/OiDonationClip/Networking/ClipConfiguration.swift" \
 "$IOS_ROOT/OiDonationClip/Networking/ClipStory.swift" \
 "$IOS_ROOT/OiDonationClip/Networking/ClipContentClient.swift" \
 "$IOS_ROOT/Tests/AppClipContentChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "${1:-http://127.0.0.1:8765}"
