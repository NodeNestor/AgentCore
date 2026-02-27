#!/bin/bash
# Module: 40-agent-setup
# Configure the selected coding agent based on AGENT_TYPE.

log_info "Setting up agent: $AGENT_TYPE"

case "$AGENT_TYPE" in

    claude)
        log_info "Configuring Claude Code..."

        # 1. Accept ToS / trigger first-run binary init
        log_info "Accepting Claude ToS..."
        su - agent -c "claude --dangerously-skip-permissions --version" 2>/dev/null || true

        # 2. First-run conversation to initialize workspace state
        log_info "Running Claude first-run initialization..."
        su - agent -c "cd /workspace/projects && claude -p 'ready' --dangerously-skip-permissions" 2>/dev/null || true

        # 3. Set onboarding flags in ~/.claude.json
        log_info "Writing ~/.claude.json onboarding flags..."
        CLAUDE_JSON=/home/agent/.claude.json
        python3 - <<PYEOF
import json

path = "$CLAUDE_JSON"
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

data["hasCompletedOnboarding"] = True
data["hasCompletedAuthFlow"] = True
data["lastOnboardingVersion"] = "latest"

with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
        chown agent:agent "$CLAUDE_JSON" 2>/dev/null || true

        # 4. Merge settings.local.json
        log_info "Writing settings.local.json..."
        SETTINGS_LOCAL=/home/agent/.claude/settings.local.json
        python3 - <<PYEOF
import json, os

path = "$SETTINGS_LOCAL"
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

data.setdefault("hasCompletedOnboarding", True)
data.setdefault("hasCompletedAuthFlow", True)
data.setdefault("theme", "dark")
data.setdefault("preferredNotifChannel", "terminal_bell")
data.setdefault("teamMode", "tmux")

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
        chown agent:agent "$SETTINGS_LOCAL" 2>/dev/null || true

        # 5. Enable experimental teams in settings.json env block
        log_info "Enabling experimental agent teams in settings.json..."
        SETTINGS_JSON=/home/agent/.claude/settings.json
        python3 - <<PYEOF
import json, os

path = "$SETTINGS_JSON"
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

data.setdefault("env", {})
data["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
        chown agent:agent "$SETTINGS_JSON" 2>/dev/null || true

        log_info "Claude setup complete."
        ;;

    opencode)
        log_info "OpenCode setup - no special config needed"
        ;;

    aider)
        log_info "Aider setup - no special config needed"
        ;;

    none)
        log_info "No agent selected"
        ;;

    *)
        log_warn "Unknown AGENT_TYPE: '$AGENT_TYPE'. Skipping agent setup."
        ;;
esac
