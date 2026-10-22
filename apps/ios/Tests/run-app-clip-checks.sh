#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  "$IOS_ROOT/OiDonation/Domain/Models/Story.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/StoryRepository.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/PublicLinkParser.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/AppClipLink.swift" \
  "$IOS_ROOT/OiDonation/App/AppRouter.swift" \
  "$IOS_ROOT/OiDonationClip/AppClipViewModel.swift" \
  "$IOS_ROOT/Tests/AppClipInvocationChecks.swift" \
  -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
