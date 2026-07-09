#!/bin/bash
set -e

cd /Users/duckets/Desktop/hermex_openclaw_project/DualAgent

# Regenerate Xcode project if needed
xcodegen generate 2>/dev/null || true

# Reuse the already-booted simulator first. Do not pick by device name;
# duplicate names/runtimes can make Xcode boot or target the wrong simulator.
SIMULATOR_UDID=$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/ {print $2; exit}')
if [ -z "$SIMULATOR_UDID" ]; then
    SIMULATOR_UDID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone|iPad/ {print $2; exit}')
    if [ -z "$SIMULATOR_UDID" ]; then
        echo "ERROR: No available iOS simulator found"
        exit 1
    fi
    xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
fi

echo "Using simulator UDID: $SIMULATOR_UDID"

# Build the project
xcodebuild -project DualAgent.xcodeproj -scheme DualAgent -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" build 2>&1 | tail -20

# Check build result
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "BUILD SUCCESS"
    exit 0
else
    echo "BUILD FAILED"
    exit 1
fi
