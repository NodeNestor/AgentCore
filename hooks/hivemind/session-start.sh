#!/bin/bash
# HiveMindDB Hook: SessionStart
# Runs when Claude Code session starts or resumes.
#
# Actions:
#   1. Register/heartbeat agent with HiveMindDB
#   2. Recall recent memories and inject as context
#
# Returns additionalContext JSON so Claude sees previous session memories.

set -euo pipefail

HMDB_URL="${HIVEMINDDB_URL:-}"
HMDB_AGENT_ID="${AGENT_ID:-default}"
HMDB_AGENT_NAME="${AGENT_NAME:-$HMDB_AGENT_ID}"

# Skip if HiveMindDB not configured
[ -z "$HMDB_URL" ] && exit 0

# Parse stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SOURCE=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# 1. Register agent (idempotent — updates if exists)
curl -sf -X POST "$HMDB_URL/api/v1/agents/register" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
    --arg id "$HMDB_AGENT_ID" \
    --arg name "$HMDB_AGENT_NAME" \
    --arg sid "${SESSION_ID:-unknown}" \
    --arg cwd "${CWD:-/workspace}" \
    '{
      agent_id: $id,
      name: $name,
      agent_type: "claude",
      capabilities: ["code", "memory", "hooks"],
      metadata: { session_id: $sid, cwd: $cwd }
    }')" >/dev/null 2>&1 || true

# 2. Heartbeat
curl -sf -X POST "$HMDB_URL/api/v1/agents/$HMDB_AGENT_ID/heartbeat" >/dev/null 2>&1 || true

# 3. Recall recent memories (last 10)
MEMORIES=$(curl -sf "$HMDB_URL/api/v1/memories?limit=10" 2>/dev/null || echo "[]")

# Build context string from memories
CONTEXT=""
if [ "$MEMORIES" != "[]" ] && [ -n "$MEMORIES" ]; then
  CONTEXT=$(echo "$MEMORIES" | jq -r '
    [.[] | select(.content != null) |
      "- [\(.topic // "general")] \(.content)"
    ] | join("\n")
  ' 2>/dev/null || echo "")
fi

# 4. Return additional context if we have memories
if [ -n "$CONTEXT" ]; then
  jq -n --arg ctx "## Recent HiveMind Memories\n\nThe following memories were recalled from the shared HiveMindDB memory system:\n\n$CONTEXT\n\nUse the hiveminddb MCP tools (remember, recall, search, extract) to store new knowledge." \
    '{ additionalContext: $ctx }'
fi

exit 0
