#!/bin/zsh
# Explicit opt-in integration check. Creates/removes only its own temporary list.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/Tools/swift-sdk.zsh"
check_app="$project_dir/.build/tests/Reminders Check.app"
mkdir -p "$check_app/Contents/MacOS"
cp "$project_dir/Info.plist" "$check_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.paperpin.reminderscheck' "$check_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RemindersCheck' "$check_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Paperpin Reminders Check' "$check_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Paperpin Reminders Check' "$check_app/Contents/Info.plist"
xcrun swiftc -sdk "$paperpin_sdk" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "$project_dir/Sources/RemindersModels.swift" "$project_dir/Sources/EventKitRemindersClient.swift" \
    "$project_dir/Tests/LiveRemindersChecks.swift" -o "$check_app/Contents/MacOS/RemindersCheck"
codesign --force --sign - "$check_app"
"$check_app/Contents/MacOS/RemindersCheck"
