#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library \
  "$IOS_ROOT/OiDonation/Features/PhotoTest/CollageGeometry.swift" \
  "$IOS_ROOT/Tests/CollageGeometryChecks.swift" \
  -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
