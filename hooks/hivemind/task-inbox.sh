#!/bin/bash
# task-inbox.sh — UserPromptSubmit hook
# Checks the task inbox file for new HiveMind tasks and injects them
# as additionalContext so the agent becomes aware of pending work.
# Clears the inbox after reading so tasks are only surfaced once.

set -euo pipefail

TASK_INBOX_FILE="${TASK_INBOX_FILE:-/workspace/.state/task-inbox.json}"

# Read and discard stdin (hook payload — not used)
cat > /dev/null

# Exit silently if inbox file doesn't exist
if [ ! -f "$TASK_INBOX_FILE" ]; then
  exit 0
fi

# Read inbox contents
INBOX_CONTENT="$(cat "$TASK_INBOX_FILE" 2>/dev/null || echo "[]")"

# Exit silently if empty or just an empty array
if [ -z "$INBOX_CONTENT" ] || [ "$INBOX_CONTENT" = "[]" ] || [ "$INBOX_CONTENT" = "[ ]" ]; then
  exit 0
fi

# Parse task count using Python (jq may not be available everywhere)
TASK_COUNT="$(python3 -c "
import json, sys
try:
    tasks = json.loads(sys.argv[1])
    if not isinstance(tasks, list):
        print(0)
    else:
        print(len(tasks))
except Exception:
    print(0)
" "$INBOX_CONTENT" 2>/dev/null || echo "0")"

# Exit silently if no tasks
if [ "$TASK_COUNT" -eq 0 ] 2>/dev/null; then
  exit 0
fi

# Build the task list for context injection
TASK_LIST="$(python3 -c "
import json, sys

tasks = json.loads(sys.argv[1])
lines = []
for t in tasks:
    tid = t.get('id', '?')
    title = t.get('title', 'Untitled')
    desc = t.get('description', 'No description')
    priority = t.get('priority', 'N/A')
    lines.append(f'- [#{tid}] {title}: {desc} (priority: {priority})')
print('\n'.join(lines))
" "$INBOX_CONTENT" 2>/dev/null)"

# Clear the inbox (truncate to empty array)
echo "[]" > "$TASK_INBOX_FILE"

# Output additionalContext JSON to stdout
python3 -c "
import json, sys
context = '''## New HiveMind Tasks Available

The following tasks have been assigned or are available:
${TASK_LIST}

Use \`task_claim\` to accept a task, then \`task_start\` to begin work, and \`task_complete\` when done.'''

result = {
    'additionalContext': context
}
print(json.dumps(result))
"
