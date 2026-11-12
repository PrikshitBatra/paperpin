#!/bin/zsh
# Build a free, ad hoc signed distribution. This is NOT Apple notarization.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="${1:-$project_dir/.build/distribution}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
image_name="Paperpin-$version-universal.dmg"
if [[ -e "$output_dir/$image_name" || -e "$output_dir/$image_name.sha256" ]]; then
    print -u2 "An installer already exists at $output_dir/$image_name. Use a new output directory."
    exit 1
fi

work_dir="$(mktemp -d "$output_dir/.package.XXXXXX")"
mount_dir="$work_dir/mounted"
mounted=0
cleanup() {
    if (( mounted )); then
        if ! hdiutil detach "$mount_dir" -quiet; then
            print -u2 "Could not eject $mount_dir. Keeping temporary files at $work_dir."
            return
        fi
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$project_dir/build.zsh" "$work_dir/Paperpin.app"
mkdir -p "$work_dir/staging" "$mount_dir"
# Only package the freshly built app; never copy an installed app or user data.
ditto --noextattr --noqtn "$work_dir/Paperpin.app" "$work_dir/staging/Paperpin.app"
ln -s /Applications "$work_dir/staging/Applications"
cp "$project_dir/Tools/Install.txt" "$work_dir/staging/Read me first.txt"
codesign --verify --all-architectures --deep --strict "$work_dir/staging/Paperpin.app"
if xattr -lr "$work_dir/staging/Paperpin.app" | /usr/bin/grep -q 'com.apple.quarantine:'; then
    print -u2 "The staging folder contains quarantined files; refusing to package it."
    exit 1
fi

hdiutil create -volname "Paperpin $version" -srcfolder "$work_dir/staging" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$work_dir/$image_name"
hdiutil verify "$work_dir/$image_name"
hdiutil attach "$work_dir/$image_name" -readonly -nobrowse -mountpoint "$mount_dir" -quiet
mounted=1
[[ "$(readlink "$mount_dir/Applications")" == /Applications ]]
[[ -f "$mount_dir/Read me first.txt" ]]
ditto "$mount_dir/Paperpin.app" "$work_dir/install-check/Paperpin.app"
installed_app="$work_dir/install-check/Paperpin.app"
codesign --verify --all-architectures --deep --strict "$installed_app"
architectures=" $(xcrun lipo -archs "$installed_app/Contents/MacOS/Paperpin") "
[[ "$architectures" == *' arm64 '* && "$architectures" == *' x86_64 '* ]]
cmp "$work_dir/Paperpin.app/Contents/MacOS/Paperpin" "$installed_app/Contents/MacOS/Paperpin"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$installed_app/Contents/Info.plist")" == 13.0 ]]
if xattr -lr "$installed_app" | /usr/bin/grep -q 'com.apple.quarantine:'; then
    print -u2 "The packaged app contains quarantine metadata; refusing to distribute it."
    exit 1
fi
hdiutil detach "$mount_dir" -quiet
mounted=0

# Publish only after mount, copy, architecture, signature and integrity checks.
mv "$work_dir/$image_name" "$output_dir/$image_name"
(cd "$output_dir" && shasum -a 256 "$image_name" > "$image_name.sha256")
print "Created $output_dir/$image_name"
print "Ad hoc signed; not notarized. Share a browser download link, not a chat attachment."
print "Recipients may need System Settings > Privacy & Security > Open Anyway."
