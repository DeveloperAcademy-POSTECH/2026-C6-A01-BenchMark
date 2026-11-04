#!/bin/sh
set -eu
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <task-owned-booted-simulator-udid> <output-directory> <built-OiDonationClip.app>" >&2
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
# Test the packaged resources, never a source-only substitute.
sh "$IOS_ROOT/Tests/run-app-clip-font-checks.sh" "$3"
cp "$3/Assets.car" "$APP_DIR/Assets.car"
python3 - "$3" "$APP_DIR" <<'PY_COPY'
from pathlib import Path
import shutil,sys
source=Path(sys.argv[1]); target=Path(sys.argv[2])
for path in source.rglob('*.ttf'):
    shutil.copyfile(path,target/path.name)
for name in ['61272.png','0e35d.png','9ac42.png','aeb3a.png']:
    matches=list(source.rglob(name))
    assert len(matches)==1, f'Missing bundled cucumber: {name}'
    shutil.copyfile(matches[0],target/name)
preview=list(source.rglob('AppClipStoryCardPreview.png'))
assert len(preview)==1, 'Missing packaged preview fixture'
shutil.copyfile(preview[0],target/preview[0].name)
PY_COPY
GAME_DIR="$IOS_ROOT/OiDonationClip/Views/ARGame"
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -sdk "$SDK" -target "$(uname -m)-apple-ios27.0-simulator" \
  "$GAME_DIR/ARGameIntroView.swift" "$GAME_DIR/ARGameFailureView.swift" \
  "$GAME_DIR/ARGameHUD.swift" "$GAME_DIR/ARGameStartOverlay.swift" "$GAME_DIR/ARGameSuccessView.swift" \
  "$GAME_DIR/CucumberCharacterImage.swift" "$GAME_DIR/CucumberArtwork.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/StoryRepository.swift" \
  "$IOS_ROOT/Tests/AppClipPublicStoryChecks.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/Story.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/StoryCard.swift" \
  "$IOS_ROOT/OiDonationClip/Models/AppClipExperience.swift" \
  "$IOS_ROOT/OiDonationClip/Views/StoryCard/AppClipStoryCardView.swift" \
  "$IOS_ROOT/OiDonation/Shared/Components/ARCollectionResultView.swift" \
  "$IOS_ROOT/OiDonation/Shared/Components/OiStoryCardArtwork.swift" \
  "$IOS_ROOT/Tests/ARGameVisualChecks.swift" -o "$APP_DIR/checks"
xcrun simctl install "$1" "$APP_DIR"
INSTALLED=1
xcrun simctl launch --console "$1" "$BUNDLE_ID" "$2"
test "$(cat "$2/result.txt")" = PASS
