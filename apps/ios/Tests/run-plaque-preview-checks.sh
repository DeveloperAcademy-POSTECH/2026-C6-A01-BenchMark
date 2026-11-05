#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/oi-plaque-module-cache" -parse-as-library \
  "$IOS_ROOT/OiDonation/Domain/Models/BenchPlaquePreview.swift" \
  "$IOS_ROOT/OiDonation/Features/Participation/PlaquePreview/PlaquePreviewRenderer.swift" \
  "$IOS_ROOT/Tests/PlaquePreviewChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$IOS_ROOT/OiDonation/Assets.xcassets/HomeBench.imageset/HomeBench.png"
