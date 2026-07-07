#!/bin/bash
set -euo pipefail

# CI check script for DualAgent iOS app
# Runs build and updates timestamp on success

PROJECT_DIR="/Users/duckets/Desktop/hermex_openclaw_project/DualAgent"
cd "$PROJECT_DIR" || { echo "Failed to change directory to $PROJECT_DIR"; exit 1; }

echo "[$(date)] Starting CI check..."

# Resolve Swift Package Manager dependencies
echo "Resolving dependencies..."
swift package resolve

# Build the project using xcodecode (for iOS app)
echo "Building project..."
xcodebuild -scheme DualAgent -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' build -quiet

# If we reach here, build succeeded
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
echo "Last successful build: $TIMESTAMP" > LAST_CHECKED.txt

# Commit and push if there are changes
if git diff --quiet; then
    echo "No changes to commit."
else
    echo "Changes detected, committing..."
    git add LAST_CHECKED.txt
    git commit -m "Update last checked timestamp: $TIMESTAMP"
    git push origin main
    echo "Pushed changes to main."
fi

echo "[$(date)] CI check completed successfully."