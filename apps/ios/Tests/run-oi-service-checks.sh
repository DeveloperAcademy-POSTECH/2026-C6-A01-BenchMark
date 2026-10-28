#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiDraftVault.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceAPI.swift" \
  "$IOS_ROOT/Tests/OiServiceChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
