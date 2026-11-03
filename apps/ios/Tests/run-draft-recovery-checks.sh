#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiDraftVault.swift" \
  "$IOS_ROOT/Tests/OiDraftRecoveryChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
