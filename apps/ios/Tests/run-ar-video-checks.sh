#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AR_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-ar-checks.XXXXXX")
trap 'rm -f "$AR_CHECK_DIR/checks"; rmdir "$AR_CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library "$IOS_ROOT/OiDonation/Features/AR/Services/Recording/ARVideoCropGeometry.swift" "$IOS_ROOT/Tests/ARVideoCropGeometryChecks.swift" -o "$AR_CHECK_DIR/checks"
"$AR_CHECK_DIR/checks"
