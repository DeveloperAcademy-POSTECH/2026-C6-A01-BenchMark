#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OI_PALM_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-palm-checks.XXXXXX")
trap 'rm -rf -- "$OI_PALM_CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$OI_PALM_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Features/AR/Models/ARCaptureSettings.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Models/ARCharacter.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Palm/ARPalmGeometry.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Palm/ARPalmWorkGate.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Palm/ARPalmPlacementState.swift" \
  "$IOS_ROOT/Tests/ARPalmChecks.swift" -o "$OI_PALM_CHECK_DIR/checks"
"$OI_PALM_CHECK_DIR/checks"
