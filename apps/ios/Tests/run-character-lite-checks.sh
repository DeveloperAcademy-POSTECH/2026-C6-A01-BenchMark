#!/bin/sh
set -eu
IOS_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d)
trap 'rm -f "$CHECK_DIR/checks"; rmdir "$CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/oi-character-module-cache" -parse-as-library \
  "$IOS_ROOT/Tests/CharacterLiteChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$IOS_ROOT"
