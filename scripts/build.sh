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
    Sources/main.m Sources/Trackpad.m Sources/Diagnostics.m Sources/SessionLog.m Sources/CursorLock.m Sources/CursorPolicy.c Sources/Gesture.c \
    -o "$app/Contents/MacOS/TrackpadShortcuts"
cp Info.plist "$app/Contents/Info.plist"
task_revision=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
if ! git diff --quiet HEAD -- Sources scripts Info.plist 2>/dev/null; then task_revision="$task_revision-dirty"; fi
/usr/libexec/PlistBuddy -c "Add :TrackpadBuildRevision string $task_revision" "$app/Contents/Info.plist"
codesign --force --sign - --identifier xyz.trackpadshortcuts.app "$app"
echo "Built: $app"
