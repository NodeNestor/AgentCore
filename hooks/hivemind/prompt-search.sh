#!/bin/bash
# HiveMindDB Hook: UserPromptSubmit
# Runs when the user submits a prompt to Claude Code.
#
# Performs semantic search against HiveMindDB using the user's prompt,
# injecting relevant memories as context. This is essentially RAG —
# the agent automatically gets relevant knowledge from the hivemind.
#
# Returns additionalContext JSON with matching memories.

set -euo pipefail

HMDB_URL="${HIVEMINDDB_URL:-}"
HMDB_AGENT_ID="${AGENT_ID:-default}"

# Skip if HiveMindDB not configured
[ -z "$HMDB_URL" ] && exit 0

# Parse stdin JSON
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Skip empty or very short prompts (greetings, etc.)
[ ${#PROMPT} -lt 15 ] && exit 0

# Skip common non-knowledge prompts
case "$PROMPT" in
  /*)    exit 0 ;;  # slash commands
  y|n|yes|no|ok|sure|done|thanks*) exit 0 ;;
esac

# Semantic search HiveMindDB with the user's prompt
RESULTS=$(curl -sf -X POST "$HMDB_URL/api/v1/search" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg q "$PROMPT" '{ query: $q, limit: 5 }')" \
  2>/dev/null || echo "[]")

# Build context from search results
CONTEXT=""
if [ "$RESULTS" != "[]" ] && [ -n "$RESULTS" ]; then
  CONTEXT=$(echo "$RESULTS" | jq -r '
    [.[] | select(.content != null and .score != null and (.score > 0.3)) |
      "- [score: \(.score | tostring | .[0:4])] \(.content)"
    ] | join("\n")
  ' 2>/dev/null || echo "")
fi

# Only inject if we found relevant memories (score > 0.3)
if [ -n "$CONTEXT" ]; then
  jq -n --arg ctx "## Relevant HiveMind Memories\n\n$CONTEXT" \
    '{ additionalContext: $ctx }'
fi

exit 0
