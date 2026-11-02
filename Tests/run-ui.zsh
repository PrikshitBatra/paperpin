#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/Tools/swift-sdk.zsh"
build_dir="$project_dir/.build/tests"
mkdir -p "$build_dir"
qa_app="$build_dir/Paperpin Preview.app"
qa_dir="$(mktemp -d "$build_dir/ui-run.XXXXXX")"
printf '%s\n' "$qa_dir" > "$build_dir/latest-ui-run"
mkdir -p "$qa_app/Contents/MacOS" "$qa_app/Contents/Resources"
cp "$project_dir/Info.plist" "$qa_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.paperpin.windowchecks' "$qa_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Paperpin Preview' "$qa_app/Contents/Info.plist"
xcrun swiftc -sdk "$paperpin_sdk" -D PAPERPIN_QA -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "$project_dir"/Sources/*.swift "$project_dir/Tests/WindowChecks.swift" "$project_dir/Tests/PolishChecks.swift" -o "$qa_app/Contents/MacOS/Paperpin"
codesign --force --sign - "$qa_app"
for preference in DesktopMode SidebarHidden FloatBoard MinimalMode MinimalOpenNotes MinimalWindowFrames MinimalModeInitialized LiquidGlassEnabled; do
    defaults delete local.paperpin.windowchecks "$preference" 2>/dev/null || true
done
if [[ "${PAPERPIN_CHECK_LAYOUT:-0}" == "1" ]]; then
    # Simulate an upgrade from a version that put the entire board on the desktop.
    defaults write local.paperpin.windowchecks DesktopMode -bool true
fi
PAPERPIN_TEST_DIRECTORY="$qa_dir" "$qa_app/Contents/MacOS/Paperpin" > "$qa_dir/results.txt" 2>&1
cat "$qa_dir/results.txt"
if /usr/bin/grep -q "^FAIL" "$qa_dir/results.txt"; then exit 1; fi
PAPERPIN_TEST_DIRECTORY="$qa_dir" PAPERPIN_VERIFY_RELAUNCH=1 "$qa_app/Contents/MacOS/Paperpin" > "$qa_dir/relaunch.txt" 2>&1
cat "$qa_dir/relaunch.txt"
if /usr/bin/grep -q "^FAIL" "$qa_dir/relaunch.txt"; then exit 1; fi
