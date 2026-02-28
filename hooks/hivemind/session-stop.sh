#!/bin/bash
# HiveMindDB Hook: Stop
# Runs ASYNC when Claude Code finishes responding.
#
# Actions:
#   1. Skip if stop_hook_active (prevent infinite loop)
#   2. Send heartbeat to HiveMindDB
#   3. Mark session activity

set -euo pipefail

HMDB_URL="${HIVEMINDDB_URL:-}"
HMDB_AGENT_ID="${AGENT_ID:-default}"

# Skip if HiveMindDB not configured
[ -z "$HMDB_URL" ] && exit 0

# Parse stdin JSON
INPUT=$(cat)

# Prevent infinite loop — skip if stop hook already active
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Heartbeat — let HiveMindDB know agent is alive
curl -sf -X POST "$HMDB_URL/api/v1/agents/$HMDB_AGENT_ID/heartbeat" \
  >/dev/null 2>&1 || true

exit 0
