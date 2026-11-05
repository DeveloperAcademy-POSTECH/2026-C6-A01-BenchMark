#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/oi-ar-background-module-cache" -parse-as-library \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Background/ARBackgroundGeometry.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Background/ARBenchMaskSelection.swift" \
  "$IOS_ROOT/Tests/ARBackgroundChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$IOS_ROOT/OiDonation/Features/AR/Services/Background/ARStadiumComposite.metalSource"
