#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <built-OiDonationClip.app>" >&2
  exit 1
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_CLIP_FONT_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-app-clip-fonts.XXXXXX")
trap 'rm -rf -- "$APP_CLIP_FONT_CHECK_DIR"' EXIT HUP INT TERM
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$APP_CLIP_FONT_CHECK_DIR/modules" \
  "$IOS_ROOT/Tests/AppClipFontChecks.swift" -o "$APP_CLIP_FONT_CHECK_DIR/checks"
"$APP_CLIP_FONT_CHECK_DIR/checks" "$1"
