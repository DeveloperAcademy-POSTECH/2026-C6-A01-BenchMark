#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <task-owned-booted-simulator-udid> <fresh-output-directory>" >&2
  exit 1
fi
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOTION_SIMULATOR=$1
MOTION_OUTPUT=$2
MOTION_BUNDLE=kr.ac.postech.benchmark.postcardmotionchecks
if [ -e "$MOTION_OUTPUT/result.txt" ]; then
  echo "Use a fresh output directory so an old result cannot count as a pass." >&2
  exit 1
fi
if xcrun simctl get_app_container "$MOTION_SIMULATOR" "$MOTION_BUNDLE" >/dev/null 2>&1; then
  echo "A checks app already exists; use an isolated task-owned simulator." >&2
  exit 1
fi
MOTION_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-postcard-motion.XXXXXX")
MOTION_APP="$MOTION_CHECK_DIR/PostcardMotionChecks.app"
MOTION_INSTALLED=0
cleanup() {
  if [ "$MOTION_INSTALLED" -eq 1 ]; then
    xcrun simctl terminate "$MOTION_SIMULATOR" "$MOTION_BUNDLE" >/dev/null 2>&1 || :
    xcrun simctl uninstall "$MOTION_SIMULATOR" "$MOTION_BUNDLE"
  fi
  rm -rf -- "$MOTION_CHECK_DIR"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$MOTION_APP" "$MOTION_OUTPUT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
plutil -create xml1 "$MOTION_APP/Info.plist"
plutil -insert CFBundleExecutable -string checks "$MOTION_APP/Info.plist"
plutil -insert CFBundleIdentifier -string "$MOTION_BUNDLE" "$MOTION_APP/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$MOTION_APP/Info.plist"
plutil -insert CFBundleVersion -string 1 "$MOTION_APP/Info.plist"
plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false}' "$MOTION_APP/Info.plist"
plutil -insert UILaunchScreen -json '{}' "$MOTION_APP/Info.plist"
cp "$IOS_ROOT/Tests/Fixtures/AppClipStoryCardPreview.png" "$MOTION_APP/AppClipStoryCardPreview.png"
xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -sdk "$SDK" -target "$(uname -m)-apple-ios26.2-simulator" -module-cache-path "$MOTION_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Features/Profile/Creation/OiPostcardMotion.swift" \
  "$IOS_ROOT/OiDonationClip/Views/ScratchPostcard/ScratchPostcardEffects.swift" \
  "$IOS_ROOT/Tests/PostcardMotionChecks.swift" -o "$MOTION_APP/checks"
xcrun simctl install "$MOTION_SIMULATOR" "$MOTION_APP"
MOTION_INSTALLED=1
xcrun simctl launch --console "$MOTION_SIMULATOR" "$MOTION_BUNDLE" "$MOTION_OUTPUT"
test "$(cat "$MOTION_OUTPUT/result.txt")" = PASS
if xcrun simctl get_app_container "$MOTION_SIMULATOR" "$MOTION_BUNDLE" >/dev/null 2>&1; then
  xcrun simctl uninstall "$MOTION_SIMULATOR" "$MOTION_BUNDLE"
  MOTION_INSTALLED=0
fi
