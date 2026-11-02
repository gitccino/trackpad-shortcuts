#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Build this app on macOS with Xcode Command Line Tools installed." >&2
    exit 1
fi
app="build/Trackpad Shortcuts.app"
mkdir -p "$app/Contents/MacOS"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=12.0 \
    -framework AppKit -framework ApplicationServices \
    Sources/main.m Sources/Trackpad.m Sources/Diagnostics.m Sources/Gesture.c \
    -o "$app/Contents/MacOS/TrackpadShortcuts"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier xyz.trackpadshortcuts.app "$app"
echo "Built: $app"
