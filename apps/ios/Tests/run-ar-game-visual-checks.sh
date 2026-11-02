#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <task-owned-booted-simulator-udid> <output-directory>" >&2
  exit 1
fi
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
APP_DIR="$CHECK_DIR/ARGameChecks.app"
BUNDLE_ID=kr.ac.postech.benchmark.argamechecks
INSTALLED=0
cleanup() {
  if [ "$INSTALLED" -eq 1 ]; then
    xcrun simctl terminate "$1" "$BUNDLE_ID" >/dev/null 2>&1 || :
    xcrun simctl uninstall "$1" "$BUNDLE_ID"
  fi
  rm -rf "$CHECK_DIR"
}
trap 'cleanup "$1"' EXIT
if xcrun simctl get_app_container "$1" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "Checks app already exists; use an isolated task-owned simulator." >&2
  exit 1
fi
if [ -e "$2/result.txt" ]; then
  echo "Output already contains a result; use a fresh directory." >&2
  exit 1
fi
mkdir -p "$APP_DIR"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
export SDKROOT="$SDK"
plutil -create xml1 "$APP_DIR/Info.plist"
plutil -insert CFBundleExecutable -string checks "$APP_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$APP_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP_DIR/Info.plist"
plutil -insert CFBundleVersion -string 1 "$APP_DIR/Info.plist"
plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false}' "$APP_DIR/Info.plist"
plutil -insert UILaunchScreen -json '{}' "$APP_DIR/Info.plist"
xcrun actool "$IOS_ROOT/OiDonationClip/Assets.xcassets" --compile "$APP_DIR" \
  --platform iphonesimulator --minimum-deployment-target 27.0 --target-device iphone \
  --output-partial-info-plist "$CHECK_DIR/assets.plist" >/dev/null
cp "$IOS_ROOT/OiDonation/Resources/Fonts/PearToucan-Regular.ttf" "$APP_DIR/"
cp "$IOS_ROOT/OiDonation/Resources/Fonts/Paperlogy-7Bold.ttf" "$APP_DIR/"
GAME_DIR="$IOS_ROOT/OiDonationClip/Views/ARGame"
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -sdk "$SDK" -target "$(uname -m)-apple-ios27.0-simulator" \
  "$GAME_DIR/ARGameIntroView.swift" "$GAME_DIR/ARGameFailureView.swift" \
  "$GAME_DIR/ARGameHUD.swift" "$GAME_DIR/ARGameStartOverlay.swift" "$GAME_DIR/ARGameSuccessView.swift" \
  "$GAME_DIR/CucumberCharacterImage.swift" "$GAME_DIR/CucumberArtwork.swift" \
  "$IOS_ROOT/Tests/ARGameVisualChecks.swift" -o "$APP_DIR/checks"
xcrun simctl install "$1" "$APP_DIR"
INSTALLED=1
xcrun simctl launch --console "$1" "$BUNDLE_ID" "$2"
test "$(cat "$2/result.txt")" = PASS
