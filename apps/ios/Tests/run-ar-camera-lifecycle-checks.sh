#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AR_CAMERA_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-ar-camera-lifecycle.XXXXXX")
trap 'rm -rf -- "$AR_CAMERA_CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$AR_CAMERA_CHECK_DIR/modules" \
  "$IOS_ROOT/Tests/ARCameraLifecycleFakes.swift" \
  "$IOS_ROOT/OiDonation/Features/AR/Views/Camera/ARCameraViewModel.swift" \
  "$IOS_ROOT/Tests/ARCameraLifecycleChecks.swift" -o "$AR_CAMERA_CHECK_DIR/checks"
"$AR_CAMERA_CHECK_DIR/checks"
