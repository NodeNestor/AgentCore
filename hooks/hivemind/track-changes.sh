#!/bin/bash
# HiveMindDB Hook: PostToolUse (matcher: Edit|Write)
# Runs ASYNC after file edits/writes — does not block the agent.
#
# Records file changes as lightweight memories in HiveMindDB
# so the hivemind knows what files were modified across sessions.

set -euo pipefail

HMDB_URL="${HIVEMINDDB_URL:-}"
HMDB_AGENT_ID="${AGENT_ID:-default}"

# Skip if HiveMindDB not configured
[ -z "$HMDB_URL" ] && exit 0

# Parse stdin JSON
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

# Skip if no file path
[ -z "$FILE_PATH" ] && exit 0

# Store as a lightweight memory
curl -sf -X POST "$HMDB_URL/api/v1/memories" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
    --arg content "Modified file: $FILE_PATH (via $TOOL_NAME)" \
    --arg agent "$HMDB_AGENT_ID" \
    '{
      content: $content,
      agent_id: $agent,
      topic: "file-changes",
      tags: ["auto", "file-change"],
      metadata: { type: "file_change", tool: "'"$TOOL_NAME"'" }
    }')" >/dev/null 2>&1 || true

exit 0
