#!/bin/bash
#
# Builds and tests the Gameball Swift package for an iOS Simulator destination.
#
# Why this script exists, rather than `swift test` or a bare `xcodebuild`:
#
#   * `swift build` / `swift test` cannot build this package at all. The target
#     imports UIKit, which does not exist in the macOS SDK that SwiftPM defaults
#     to, so every file fails with "no such module 'UIKit'".
#
#   * `xcodebuild` run from the repository root auto-discovers the tracked
#     `_Pods.xcodeproj` symlink (-> Example/Pods/Pods.xcodeproj) and builds that
#     stale project instead of the package. It fails on 13 XIBs that no longer
#     exist in Sources/.
#
# The fix is a symlink farm outside the repository containing only Package.swift,
# Sources/ and Tests/. xcodebuild then resolves the package with no .xcodeproj in
# sight. Symlinks mean there is never a second copy of the sources to drift.
#
# Usage:
#   Scripts/test.sh                       # run the whole suite
#   Scripts/test.sh build                 # build only, no tests
#   Scripts/test.sh test -only-testing:GameballTests/MessageParserTests
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${GAMEBALL_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
FARM="${TMPDIR:-/tmp}gameball-spm-farm"
DERIVED="$FARM/.derived"

ACTION="${1:-test}"
if [ $# -gt 0 ]; then shift; fi

rm -rf "$FARM"
mkdir -p "$FARM"
ln -s "$REPO/Package.swift" "$FARM/Package.swift"
ln -s "$REPO/Sources"       "$FARM/Sources"
ln -s "$REPO/Tests"         "$FARM/Tests"

cd "$FARM"
exec xcodebuild \
  -scheme Gameball \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  "$ACTION" "$@"
