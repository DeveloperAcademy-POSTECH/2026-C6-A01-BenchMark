#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$CHECK_DIR"
  test ! -e "$CHECK_DIR"
}
trap cleanup EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$CHECK_DIR/module-cache" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceAPI.swift" \
  "$IOS_ROOT/Tests/OiAppleExchangeChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
