#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AR_RECOVERY_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-ar-video-recovery.XXXXXX")
trap 'rm -rf -- "$AR_RECOVERY_CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -module-cache-path "$AR_RECOVERY_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Features/AR/Services/Recording/ARVideoRecoveryStore.swift" \
  "$IOS_ROOT/Tests/ARVideoRecoveryChecks.swift" -o "$AR_RECOVERY_CHECK_DIR/checks"
"$AR_RECOVERY_CHECK_DIR/checks"
