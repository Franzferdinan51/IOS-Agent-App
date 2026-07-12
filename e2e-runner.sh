#!/bin/bash
# e2e-runner.sh — Run the DualAgent E2E UI test and report results
# Targets Hermes at http://127.0.0.1:8787 with password auth

set -e
WORKDIR="/Users/duckets/Desktop/hermex_openclaw_project/DualAgent"
cd "$WORKDIR"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

HERMES_URL="http://127.0.0.1:8787"
PASSWORD="erWTCSpgDWGn2-S16kRUnLfo-1xKIt29"

echo "=== E2E Runner — $(date) ==="

# 0. Check Hermes is reachable
if ! curl -s --connect-timeout 3 "$HERMES_URL/api/status" > /dev/null 2>&1; then
    echo "RESULT: SKIP — Hermes not reachable at $HERMES_URL"
    exit 0
fi

# 1. Find a booted simulator (prefer existing, don't create new)
SIMULATOR_UDID=$(xcrun simctl list devices booted 2>/dev/null | \
    awk -F '[()]' '/Booted/ {print $2; exit}')
if [ -z "$SIMULATOR_UDID" ]; then
    SIMULATOR_UDID=$(xcrun simctl list devices available 2>/dev/null | \
        awk -F '[()]' '/iPhone/ {print $2; exit}')
    if [ -z "$SIMULATOR_UDID" ]; then
        echo "RESULT: SKIP — No iOS simulator available"
        exit 0
    fi
    echo "Booting simulator: $SIMULATOR_UDID"
    xcrun simctl boot "$SIMULATOR_UDID" > /dev/null 2>&1 || {
        echo "RESULT: FAIL — Could not boot simulator"
        exit 1
    }
fi
echo "Using simulator: $SIMULATOR_UDID"

# 2. Build first so we fail fast on compile errors
echo ""
echo "=== Building ==="
BUILD_OUTPUT=$(xcodebuild -project DualAgent.xcodeproj \
    -scheme DualAgent \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    build 2>&1 | tail -5)
BUILD_STATUS=$(xcrun simctl inspect "$SIMULATOR_UDID" 2>/dev/null | head -1 || echo "build-ok")
if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED\|BUILD SUCCEEDED"; then
    echo "Build: OK"
else
    echo "Build: FAILED"
    echo "$BUILD_OUTPUT"
    echo "RESULT: FAIL — Build failed"
    exit 1
fi

# 3. Run the E2E test
echo ""
echo "=== Running E2E Test ==="
TEST_START=$(date +%s)

# Run with password via environment variable
TEST_OUTPUT=$(xcodebuild -project DualAgent.xcodeproj \
    -scheme DualAgentUITests \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -only-testing:DualAgentUITests/DualAgentEndToEndUITests/testRealHermesChatByTypingAndReturn \
    HERMES_WEBUI_PASSWORD="$PASSWORD" \
    2>&1)

TEST_END=$(date +%s)
DURATION=$((TEST_END - TEST_START))

# Parse results
PASSED=$(echo "$TEST_OUTPUT" | grep -c "TEST CASE.*PASSED" || true)
FAILED=$(echo "$TEST_OUTPUT" | grep -c "TEST CASE.*FAILED" || true)
ERRORS=$(echo "$TEST_OUTPUT" | grep "error:" | grep -v "XCTAssertFalse failed.*HERMES_WEBUI_PASSWORD" | head -5)

echo "Passed: $PASSED | Failed: $FAILED | Duration: ${DURATION}s"
if [ -n "$ERRORS" ]; then
    echo "Errors:"
    echo "$ERRORS"
fi

# Show failure reason
FAIL_REASON=$(echo "$TEST_OUTPUT" | grep -A2 "XCTAssertTrue failed\|XCTAssertFalse failed" | \
    grep -v "XCTAssertTrue failed\|XCTAssertFalse failed" | head -5)
if [ -n "$FAIL_REASON" ]; then
    echo "Failure detail: $FAIL_REASON"
fi

echo ""
if [ "$FAILED" -eq "0" ] && [ "$PASSED" -ge "1" ]; then
    echo "RESULT: PASS"
    exit 0
else
    echo "RESULT: FAIL"
    # Show key steps from test log for diagnosis
    STEPS=$(echo "$TEST_OUTPUT" | grep -E "t =     [0-9]+\.[0-9]+s.*(Wait|Tap|Type|Connect|Create|Send)" | tail -20)
    echo "Key steps:"
    echo "$STEPS"
    exit 1
fi
