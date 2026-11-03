#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONNECTION_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-account-connection-checks.XXXXXX")
trap 'rm -rf -- "$CONNECTION_CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -module-cache-path "$CONNECTION_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Features/Profile/OiAccountConnectionFlow.swift" \
  "$IOS_ROOT/Tests/OiAccountConnectionFlowChecks.swift" -o "$CONNECTION_CHECK_DIR/checks"
"$CONNECTION_CHECK_DIR/checks"
