#!/bin/bash
# enhancement-hunter.sh — Find code smells, edge cases, missing states, accessibility gaps
# in the DualAgent iOS app

set -e
WORKDIR="/Users/duckets/Desktop/hermex_openclaw_project/DualAgent"
cd "$WORKDIR"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "=== Enhancement Hunter — $(date) ==="

# 1. Missing accessibility identifiers
echo ""
echo "=== Missing Accessibility Identifiers ==="
# Look for SwiftUI Views with @State but no .accessibilityIdentifier
SWIFT_FILES=$(find "$WORKDIR/DualAgent" -name "*.swift" -type f)
COUNT=$(grep -rl "Button\|TextField\|Toggle\|NavigationLink" "$WORKDIR/DualAgent" --include="*.swift" | \
    xargs grep -L "accessibilityIdentifier\|accessibilityLabel" 2>/dev/null | wc -l | tr -d ' ')
echo "Swift files with interactive views but NO accessibilityIdentifier: $COUNT"
if [ "$COUNT" -lt 20 ]; then
    grep -rl "Button\|TextField\|Toggle\|NavigationLink" "$WORKDIR/DualAgent" --include="*.swift" | \
        xargs grep -L "accessibilityIdentifier\|accessibilityLabel" 2>/dev/null | head -20
fi

# 2. Missing error states
echo ""
echo "=== Potential Missing Error States ==="
# Find published errorMessage vars that may not be shown in UI
ERROR_COUNT=$(grep -rn "errorMessage\|error.*:.*Error\|\.failure\|catch\|Result<" \
    "$WORKDIR/DualAgent" --include="*.swift" | grep -v "errorMessage.*=.*nil" | \
    grep -v "// " | wc -l | tr -d ' ')
echo "Error-handling sites found: $ERROR_COUNT"

# 3. Look for force-unwrap risks (XXX!, as!)
echo ""
echo "=== Force Unwraps (!) and Force Casts (as!) ==="
FORCE_COUNT=$(grep -rn "![^?]\|as![a-zA-Z]" "$WORKDIR/DualAgent" --include="*.swift" | \
    grep -v "// \|debug\|print\|url!" | wc -l | tr -d ' ')
echo "Potential force-unwrap/cast sites: $FORCE_COUNT"
if [ "$FORCE_COUNT" -lt 30 ]; then
    grep -rn "![^?]\|as![a-zA-Z]" "$WORKDIR/DualAgent" --include="*.swift" | \
        grep -v "// \|debug\|print\|url!" | head -20
fi

# 4. Async/await without proper error handling
echo ""
echo "=== Task { } without return or error handling ==="
TASK_COUNT=$(grep -rn "Task\s*{" "$WORKDIR/DualAgent" --include="*.swift" | \
    grep -v "Task\s*{.*return\|Task\s*{.*\\.runDetached" | wc -l | tr -d ' ')
echo "Task blocks needing review: $TASK_COUNT"

# 5. Check for memory leaks — @StateObject/@ObservedObject without proper lifecycle
echo ""
echo "=== ViewModels without onAppear or onDisappear cleanup ==="
VM_FILES=$(find "$WORKDIR/DualAgent" -name "*ViewModel*.swift" -type f)
for f in $VM_FILES; do
    if ! grep -q "onAppear\|onDisappear\|Task\s*{" "$f"; then
        echo "POTENTIAL_LEAK: $(basename $f) — no lifecycle handlers"
    fi
done

# 6. Look for hardcoded URLs/ports
echo ""
echo "=== Hardcoded URLs and Ports ==="
grep -rn "127.0.0.1:8\|localhost:8\|http://\|wss://" \
    "$WORKDIR/DualAgent" --include="*.swift" | grep -v "hermesURL\|baseURL\|// " | head -20

# 7. Check the session creation flow for missing validation
echo ""
echo "=== Session Creation Flow Audit ==="
grep -rn "createSession\|fetchDefaultWorkspace\|resolvedWorkspace" \
    "$WORKDIR/DualAgent/Features/SessionList/" 2>/dev/null | head -20

# 8. Check for NSPredicate format strings (SQL injection / accessibility reliability)
echo ""
echo "=== Hardcoded NSPredicates in UI Tests ==="
grep -rn "BEGINSWITH\|CONTAINS\|like\|== " \
    "$WORKDIR/DualAgent/DualAgentUITests/" --include="*.swift" 2>/dev/null | head -20

# 9. Look for missing loading states during async operations
echo ""
echo "=== Async Operations Missing Loading State ==="
# Count published isLoading vars vs async functions
LOADING_COUNT=$(grep -rc "@Published var isLoading\|@Published var loading\|@Published var isLoading" \
    "$WORKDIR/DualAgent" --include="*.swift" 2>/dev/null | grep -v ":0$" | wc -l | tr -d ' ')
ASYNC_COUNT=$(grep -rc "async\|await\|Task" "$WORKDIR/DualAgent" --include="*.swift" 2>/dev/null | \
    grep -v ":0$" | wc -l | tr -d ' ')
echo "Files with loading state: $LOADING_COUNT / Files with async: $ASYNC_COUNT"

# 10. Find all UI files that DON'T use a ViewModel (raw @ObservableObject)
echo ""
echo "=== Views Without ObservableObject Pattern ==="
find "$WORKDIR/DualAgent" -name "*.swift" -path "*Features*" ! -name "*ViewModel*" ! -name "*Model*" | \
    xargs grep -l "@State\|@StateObject\|@ObservedObject" 2>/dev/null | head -10

echo ""
echo "=== Enhancement Hunter Complete — $(date) ==="
