#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/Tools/swift-sdk.zsh"
check_dir="$project_dir/.build/tests"
mkdir -p "$check_dir"
for suite in StoreChecks PersistenceChecks; do
    xcrun swiftc -sdk "$paperpin_sdk" -swift-version 5 "$project_dir/Sources/BoardStore.swift" \
        "$project_dir/Tests/$suite.swift" -o "$check_dir/$suite"
    "$check_dir/$suite" "$check_dir"
done
xcrun swiftc -sdk "$paperpin_sdk" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "$project_dir/Sources/Appearance.swift" "$project_dir/Sources/LoginItemController.swift" \
    "$project_dir/Sources/Theme.swift" "$project_dir/Sources/BoardStore.swift" "$project_dir/Sources/PaperArt.swift" \
    "$project_dir/Tests/AppearanceChecks.swift" -o "$check_dir/AppearanceChecks"
"$check_dir/AppearanceChecks"
