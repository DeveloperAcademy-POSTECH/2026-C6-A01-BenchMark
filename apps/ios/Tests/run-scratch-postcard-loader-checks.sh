#!/bin/sh
set -eu
# Runs UIKit loader checks in an already booted iOS Simulator. No production requests.
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRATCH_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-scratch-loader.XXXXXX")
trap 'rm -rf -- "$SCRATCH_CHECK_DIR"' EXIT HUP INT TERM
SCRATCH_SIMULATOR=${1:-booted}
SCRATCH_ARCH=$(uname -m)
xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target "$SCRATCH_ARCH-apple-ios17.0-simulator" \
  -module-cache-path "$SCRATCH_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Domain/Models/OiContentSafetyStore.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/Story.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/StoryCard.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/StoryRepository.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/PublicLinkParser.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/AppClipLink.swift" \
  "$IOS_ROOT/OiDonationClip/Views/ScratchPostcard/ScratchPostcardLoader.swift" \
  "$IOS_ROOT/Tests/ScratchPostcardLoaderChecks.swift" -o "$SCRATCH_CHECK_DIR/checks"
xcrun simctl spawn "$SCRATCH_SIMULATOR" "$SCRATCH_CHECK_DIR/checks"
