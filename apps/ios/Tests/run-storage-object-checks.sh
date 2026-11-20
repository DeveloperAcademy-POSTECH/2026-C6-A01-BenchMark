#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-storage-object-checks.XXXXXX")
trap 'rm -rf -- "$CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -module-cache-path "$CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiStorageObjectCache.swift" \
  "$IOS_ROOT/Tests/OiStorageObjectChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
