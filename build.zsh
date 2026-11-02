#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$project_dir/.build/release"
output_app="${1:-$project_dir/.build/Paperpin.app}"
mkdir -p "$build_dir" "$output_app/Contents/MacOS" "$output_app/Contents/Resources"
for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" "$project_dir"/Sources/*.swift -o "$build_dir/Paperpin-$arch"
done
xcrun lipo -create "$build_dir/Paperpin-arm64" "$build_dir/Paperpin-x86_64" -output "$output_app/Contents/MacOS/Paperpin"
xcrun swiftc "$project_dir/Sources/PaperArt.swift" "$project_dir/Tools/MakeIcon.swift" -o "$build_dir/make-icon"
"$build_dir/make-icon" "$build_dir/Paperpin.iconset"
iconutil --convert icns "$build_dir/Paperpin.iconset" --output "$output_app/Contents/Resources/Paperpin.icns"
cp "$project_dir/Info.plist" "$output_app/Contents/Info.plist"
plutil -lint "$output_app/Contents/Info.plist"
codesign --force --sign - --identifier local.paperpin.mac "$output_app"
codesign --verify --deep --strict "$output_app"
printf '%s\n' "$output_app"
