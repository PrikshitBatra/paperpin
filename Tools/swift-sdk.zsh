#!/bin/zsh
# Source from build/test scripts. Some Command Line Tools SDKs omit SwiftUI's
# macro plugin; select a working SDK rather than silently changing app code.
# Prefer the complete Xcode toolchain when installed. Some CLT distributions
# ship an arm-only Swift compatibility archive even though swiftc targets Intel.
# Keep this choice local to the script; respect an explicit developer directory.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
paperpin_sdk="${PAPERPIN_SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
paperpin_probe=$'import SwiftUI\nstruct SDKProbe: View { @State private var value = false; var body: some View { Text(value ? "a" : "b") } }'
if ! xcrun swiftc -sdk "$paperpin_sdk" -swift-version 5 -typecheck - <<< "$paperpin_probe" 2>/dev/null; then
    if [[ -z "${PAPERPIN_SDKROOT:-}" && -d "${paperpin_sdk:h}/MacOSX26.sdk" ]] &&
       xcrun swiftc -sdk "${paperpin_sdk:h}/MacOSX26.sdk" -swift-version 5 -typecheck - <<< "$paperpin_probe" 2>/dev/null; then
        paperpin_sdk="${paperpin_sdk:h}/MacOSX26.sdk"
        print -u2 "Using $paperpin_sdk (default SDK SwiftUI compiler plugin unavailable)."
    else
        print -u2 "SwiftUI SDK check failed. Install matching Xcode/Command Line Tools or set PAPERPIN_SDKROOT to a working macOS 26+ SDK."
        return 1
    fi
fi
