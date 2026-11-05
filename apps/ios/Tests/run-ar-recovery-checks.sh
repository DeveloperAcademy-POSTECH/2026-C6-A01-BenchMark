#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AR_RECOVERY_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-ar-recovery-checks.XXXXXX")
trap 'rm -rf "$AR_RECOVERY_CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "$AR_RECOVERY_CHECK_DIR/module-cache" -parse-as-library \
  "$IOS_ROOT/OiDonation/Features/AR/Models/ARSessionRecovery.swift" \
  "$IOS_ROOT/Tests/ARRecoveryChecks.swift" \
  -o "$AR_RECOVERY_CHECK_DIR/checks"
"$AR_RECOVERY_CHECK_DIR/checks"
