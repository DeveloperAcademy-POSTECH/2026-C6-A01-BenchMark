#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ADOPTION_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oi-draft-adoption-checks.XXXXXX")
trap 'rm -rf -- "$ADOPTION_CHECK_DIR"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -module-cache-path "$ADOPTION_CHECK_DIR/modules" \
  "$IOS_ROOT/OiDonation/Domain/Models/StoryCard.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiServiceModels.swift" \
  "$IOS_ROOT/OiDonation/Data/Networking/OiDraftVault.swift" \
  "$IOS_ROOT/Tests/OiDraftAdoptionChecks.swift" -o "$ADOPTION_CHECK_DIR/checks"
"$ADOPTION_CHECK_DIR/checks"
