#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library \
  "$IOS_ROOT/OiDonation/Domain/Models/Participation.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/HomeDashboard.swift" \
  "$IOS_ROOT/OiDonation/Domain/Models/Story.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/Repositories.swift" \
  "$IOS_ROOT/OiDonation/Domain/Repositories/StoryRepository.swift" \
  "$IOS_ROOT/OiDonation/Domain/Routing/PublicLinkParser.swift" \
  "$IOS_ROOT/OiDonation/Data/Repositories/PilotRepositories.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/APIClient.swift" \
  "$IOS_ROOT/Tests/ArchitectureChecks.swift" \
  -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
