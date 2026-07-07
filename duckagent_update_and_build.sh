#!/bin/bash
set -e

cd /Users/duckets/Desktop/hermex_openclaw_project/DualAgent

# Regenerate Xcode project if needed
xcodegen generate 2>/dev/null || true

# Find an available simulator
SIMULATOR=$(xcrun simctl list devices available | grep -E "iPhone|iPad" | head -1 | awk '{print $1}')
if [ -z "$SIMULATOR" ]; then
    echo "ERROR: No available iOS simulator found"
    exit 1
fi

# Build the project
xcodebuild -project DualAgent.xcodeproj -scheme DualAgent -configuration Debug -destination "platform=iOS Simulator,name=$SIMULATOR" build 2>&1 | tail -20

# Check build result
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "BUILD SUCCESS"
    exit 0
else
    echo "BUILD FAILED"
    exit 1
fi
