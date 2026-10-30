#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/Story.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/StoryCard.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/CollectedStoryCard.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/StoryRepository.swift" \
  "$IOS_ROOT/OiDonation/Features/Campus/CampusStory.swift" \
  "$IOS_ROOT/OiDonation/Features/Profile/MYLibraryStore.swift" \
  "$IOS_ROOT/OiDonation/Features/Profile/CollectedStoryLibrary.swift" \
  "$IOS_ROOT/Tests/MYDemoChecks.swift" \
  -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
