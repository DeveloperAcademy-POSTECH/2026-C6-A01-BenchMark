#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "${TMPDIR:-/tmp}/oi-campus-swift-module-cache" \
  "$IOS_ROOT/OiDonation/Features/Campus/Scene/CampusGeoreference.swift" \
  "$IOS_ROOT/OiDonation/Features/Campus/Placement/CampusPlacement.swift" \
  "$IOS_ROOT/OiDonation/Features/Campus/Shared/CampusSharedAPI.swift" \
  "$IOS_ROOT/Tests/CampusSharedChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
