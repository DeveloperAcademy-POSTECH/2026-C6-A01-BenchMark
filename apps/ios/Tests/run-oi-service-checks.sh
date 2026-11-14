#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-service-checks.XXXXXX")
trap 'rm -rf -- "$CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -module-cache-path "$CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Domain/Models/StoryCard.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiDraftVault.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiWardrobeFieldTrial.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceAPI.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/AppClipLink.swift" \
  "$IOS_ROOT/OiDonation/Features/Operator/OiOperatorNFCTagModel.swift" \
  "$IOS_ROOT/OiDonation/Features/Operator/OiOperatorStoriesModel.swift" \
  "$IOS_ROOT/OiDonation/Features/Operator/OiOperatorAuditModel.swift" \
  "$IOS_ROOT/OiDonation/Features/Profile/Creation/OiCreationPresentation.swift" \
  "$IOS_ROOT/OiDonation/Features/Profile/Creation/OiCardGestureState.swift" \
  "$IOS_ROOT/Tests/OiServiceChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
