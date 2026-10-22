#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <booted-simulator-udid> <output-directory>" >&2
  exit 1
fi
if [ -e "$2/result.txt" ]; then
  echo "Use a fresh output directory so an old result cannot count as a pass." >&2
  exit 1
fi
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if xcrun simctl get_app_container "$1" kr.ac.postech.benchmark.collagechecks >/dev/null 2>&1; then
  echo "A checks app already exists on this simulator; use an isolated task-owned simulator." >&2
  exit 1
fi
CHECK_DIR=$(mktemp -d)
APP_DIR="$CHECK_DIR/CollageChecks.app"
mkdir "$APP_DIR"
INSTALLED=0
cleanup() {
  if [ "$INSTALLED" -eq 1 ]; then
    xcrun simctl terminate "$1" kr.ac.postech.benchmark.collagechecks >/dev/null 2>&1 || :
    xcrun simctl uninstall "$1" kr.ac.postech.benchmark.collagechecks
  fi
  rm -rf "$CHECK_DIR"
}
trap 'cleanup "$1"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
export SDKROOT="$SDK"
plutil -create xml1 "$APP_DIR/Info.plist"
plutil -insert CFBundleExecutable -string checks "$APP_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string kr.ac.postech.benchmark.collagechecks "$APP_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$APP_DIR/Info.plist"
plutil -insert CFBundleVersion -string 1 "$APP_DIR/Info.plist"
plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false}' "$APP_DIR/Info.plist"
xcrun actool "$IOS_ROOT/OiDonation/Assets.xcassets" --compile "$APP_DIR" \
  --platform iphonesimulator --minimum-deployment-target 26.2 --target-device iphone \
  --output-partial-info-plist "$CHECK_DIR/asset-info.plist"
xcrun swiftc -parse-as-library -sdk "$SDK" -target "$(uname -m)-apple-ios26.2-simulator" \
  "$IOS_ROOT"/OiDonation/Features/PhotoTest/*.swift \
  "$IOS_ROOT/OiDonation/Features/AR/Services/ARPhotoLibraryService.swift" \
  "$IOS_ROOT/Tests/CollageImageChecks.swift" -o "$APP_DIR/checks"
xcrun simctl install "$1" "$APP_DIR"
INSTALLED=1
xcrun simctl launch --console "$1" kr.ac.postech.benchmark.collagechecks "$2"
test "$(cat "$2/result.txt")" = PASS
