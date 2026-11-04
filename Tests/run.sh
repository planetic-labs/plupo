#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/plupo-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  Plupo/ShelfItem.swift Plupo/PlupoTemporaryFiles.swift Plupo/ShelfViewModel.swift \
  Plupo/ShelfVisibilityState.swift Plupo/PreferencesStore.swift Tests/RegressionTests.swift \
  -o "$output_dir/regression-tests"
"$output_dir/regression-tests"
set --
for source in Plupo/*.swift; do
  case "$source" in
    Plupo/PlupoApp.swift) ;;
    *) set -- "$@" "$source" ;;
  esac
done
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  "$@" Tests/WindowRegressionTests.swift -o "$output_dir/window-tests"
"$output_dir/window-tests"

xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  Plupo/UpdateChecker.swift Tests/UpdateRegressionTests.swift -o "$output_dir/update-tests"
"$output_dir/update-tests"
