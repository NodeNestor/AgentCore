#!/bin/bash
# Module: 52-memory-hooks
# Install HiveMindDB auto-memory hooks into agent configuration.
#
# When HIVEMINDDB_URL is set, this module wires Claude Code hooks that:
#   - SessionStart:      Register agent + recall memories → inject as context
#   - UserPromptSubmit:  Semantic search → inject relevant memories (RAG)
#   - PostToolUse:       Track file changes as memories (async)
#   - Stop:              Heartbeat (async)
#
# For Aider/OpenCode: injects a system prompt reminder about memory tools.
# Hooks are no-ops when HIVEMINDDB_URL is unset (scripts check internally).

HOOKS_SRC=/opt/agentcore/hooks/hivemind
HOOKS_DST=/home/agent/.claude/hooks/hivemind
SETTINGS_JSON=/home/agent/.claude/settings.json
# Note: MCP server registration (including agent-memory removal and hiveminddb
# env injection) is handled entirely by 50-mcp-tools.sh. This module only
# manages hooks and env vars in settings.json.

# -----------------------------------------------------------------
# Guard: skip if HiveMindDB not configured
# -----------------------------------------------------------------
if [ -z "${HIVEMINDDB_URL:-}" ]; then
    log_info "HIVEMINDDB_URL not set — skipping memory hooks."
    return 0
fi

log_info "Installing HiveMindDB memory hooks..."

# -----------------------------------------------------------------
# 1. Copy hook scripts to agent home
# -----------------------------------------------------------------
mkdir -p "$HOOKS_DST"
if [ -d "$HOOKS_SRC" ]; then
    cp -f "$HOOKS_SRC"/*.sh "$HOOKS_DST/" 2>/dev/null || true
    chmod +x "$HOOKS_DST"/*.sh 2>/dev/null || true
    chown -R agent:agent "$HOOKS_DST" 2>/dev/null || true
    log_info "  Copied hook scripts to $HOOKS_DST"
else
    log_warn "  Hook scripts not found at $HOOKS_SRC"
    return 0
fi

# -----------------------------------------------------------------
# 2. Merge hooks into Claude Code settings.json
# -----------------------------------------------------------------
case "$AGENT_TYPE" in
    claude|all)
        log_info "  Wiring hooks into Claude Code settings.json..."

        python3 - <<PYEOF
import json
import os

path = "$SETTINGS_JSON"

try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

hooks_dir = "$HOOKS_DST"
hiveminddb_url = "$HIVEMINDDB_URL"
agent_id = "$AGENT_ID"
agent_name = "$AGENT_NAME"

# Inject env vars so hooks and MCP servers can access them
# (su - agent strips exported vars from the entrypoint)
data.setdefault("env", {})
data["env"]["HIVEMINDDB_URL"] = hiveminddb_url
data["env"]["AGENT_ID"] = agent_id
data["env"]["AGENT_NAME"] = agent_name

# Define the HiveMindDB hooks
hivemind_hooks = {
    "SessionStart": [
        {
            "matcher": "startup",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/session-start.sh",
                    "timeout": 10
                }
            ]
        }
    ],
    "UserPromptSubmit": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/prompt-search.sh",
                    "timeout": 5
                }
            ]
        }
    ],
    "PostToolUse": [
        {
            "matcher": "Edit|Write",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/track-changes.sh",
                    "timeout": 5,
                    "async": True
                }
            ]
        }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/session-stop.sh",
                    "timeout": 5,
                    "async": True
                }
            ]
        }
    ]
}

# Merge into existing hooks (preserve user-defined hooks)
existing_hooks = data.get("hooks", {})
for event, hook_list in hivemind_hooks.items():
    if event not in existing_hooks:
        existing_hooks[event] = []
    # Avoid duplicates — check if hivemind hook already present
    has_hivemind = any(
        "hivemind" in str(h.get("hooks", [{}])[0].get("command", ""))
        for h in existing_hooks[event]
        if isinstance(h, dict)
    )
    if not has_hivemind:
        existing_hooks[event].extend(hook_list)

data["hooks"] = existing_hooks

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)

print(f"[INFO]  [52-memory-hooks] Installed 4 HiveMindDB hooks into settings.json")
PYEOF
        chown agent:agent "$SETTINGS_JSON" 2>/dev/null || true
        ;;

    aider|opencode)
        # Aider and OpenCode don't have Claude Code's hooks system.
        # Instead, write a system prompt reminder about memory tools.
        log_info "  $AGENT_TYPE: writing memory prompt reminder (no hooks API)."

        MEMORY_PROMPT=/home/agent/.hivemind-prompt.md
        cat > "$MEMORY_PROMPT" <<'PROMPT_EOF'
## HiveMindDB Memory System

You are connected to a shared HiveMindDB memory system. Use these MCP tools:

- **remember** — Store facts, preferences, decisions under a topic
- **recall** — Recall all memories for a topic
- **search** — Semantic search across all memories
- **extract** — Auto-extract knowledge from conversation text
- **forget** — Invalidate outdated memories

At the start of each session, use `recall` to check for relevant context.
Before finishing, use `remember` to store important discoveries.
PROMPT_EOF
        chown agent:agent "$MEMORY_PROMPT" 2>/dev/null || true
        ;;

    *)
        log_info "  No hooks to install for AGENT_TYPE=$AGENT_TYPE"
        ;;
esac

log_info "HiveMindDB memory hooks installed."
