#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  "$IOS_ROOT/OiDonation/Features/Campus/Placement/CampusCardLocation.swift" \
  "$IOS_ROOT/Tests/CampusCardLocationChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$IOS_ROOT/OiDonation/Resources/pohang-city-boundary.json"
