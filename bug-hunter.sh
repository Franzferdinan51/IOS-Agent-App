#!/bin/bash
# bug-hunter.sh — Investigate and fix DualAgent bugs
# Works against local Hermes at http://127.0.0.1:8787

set -e
WORKDIR="/Users/duckets/Desktop/hermex_openclaw_project/DualAgent"
cd "$WORKDIR"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

HERMES_URL="http://127.0.0.1:8787"
PASSWORD="erWTCSpgDWGn2-S16kRUnLfo-1xKIt29"

echo "=== Bug Hunter — $(date) ==="

# Step 1: Check Hermes is reachable
if ! curl -s --connect-timeout 3 "$HERMES_URL/api/status" > /dev/null 2>&1; then
    echo "Hermes not reachable at $HERMES_URL — skipping"
    exit 0
fi

# Step 2: Login and verify sessions API works
COOKIES=$(mktemp)
LOGIN_RESP=$(curl -s --connect-timeout 5 -c "$COOKIES" -b "$COOKIES" \
    -X POST "$HERMES_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$PASSWORD\"}")
if ! echo "$LOGIN_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)"; then
    echo "Hermes login failed: $LOGIN_RESP"
    rm -f "$COOKIES"
    exit 0
fi

# Step 3: Get the raw sessions JSON — this is the ground truth
SESSIONS_JSON=$(curl -s --connect-timeout 5 -b "$COOKIES" \
    "$HERMES_URL/api/sessions?limit=5" | python3 -c "
import json,sys
d=json.load(sys.stdin)
# Print just the first session's keys as a sample
if d.get('sessions'):
    print('FIELDS:', sorted(d['sessions'][0].keys()))
    print('COUNT:', d.get('webui_session_count','?'))
" 2>&1)

echo "API Response: $SESSIONS_JSON"

# Step 4: Try creating a test session and immediately fetching
CREATE_RESP=$(curl -s --connect-timeout 5 -b "$COOKIES" -X POST \
    "$HERMES_URL/api/session/new" \
    -H "Content-Type: application/json" \
    -d '{"model":"MiniMax-M3","workspace":"/Users/duckets/workspace"}')
echo "Create response: $CREATE_RESP"

NEW_SESSION_ID=$(echo "$CREATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session',{}).get('session_id','') or '')" 2>/dev/null || echo "")

if [ -n "$NEW_SESSION_ID" ]; then
    echo "Created session: $NEW_SESSION_ID"
    
    # Fetch sessions again and check if the new one appears
    VERIFY=$(curl -s --connect-timeout 5 -b "$COOKIES" "$HERMES_URL/api/sessions?limit=50" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ids=[s.get('session_id','') for s in d.get('sessions',[])]
print('NEW_ID_FOUND' if '$NEW_SESSION_ID' in ids else 'NEW_ID_MISSING')
print('TOTAL:', len(ids))
" 2>&1)
    echo "Verify: $VERIFY"
fi

# Step 5: Check the Swift source for UnifiedSession and SessionsResponse
echo ""
echo "=== Checking Swift Models ==="
SWIFT_FILES=$(find "$WORKDIR/DualAgent" -name "*.swift" -type f)
for model in UnifiedSession SessionsResponse; do
    MATCHES=$(grep -rn "$model" "$WORKDIR/DualAgent" --include="*.swift" 2>/dev/null | head -20)
    if [ -n "$MATCHES" ]; then
        echo "Found $model:"
        echo "$MATCHES"
    else
        echo "MISSING: $model not found in Swift source"
    fi
done

# Step 6: Check HermesBackend.fetchSessions implementation
echo ""
echo "=== HermesBackend.fetchSessions ==="
grep -n "fetchSessions\|SessionsResponse\|UnifiedSession\|toUnifiedSession" \
    "$WORKDIR/DualAgent/Networking/HermesBackend.swift" 2>/dev/null | head -30

# Step 7: Check if the app actually reloads sessions after creation
echo ""
echo "=== Session List Reload Logic ==="
grep -rn "loadSessions\|fetchSessions\|sessions.*=.*\[\]" \
    "$WORKDIR/DualAgent/Features/SessionList/" 2>/dev/null | head -20

rm -f "$COOKIES"
echo "=== Bug Hunter Complete ==="
