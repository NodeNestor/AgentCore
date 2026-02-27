#!/bin/bash
# Module: 99-cred-refresh
# Start credential refresh loop in background.
# Also applies ad-block hosts if ENABLE_ADBLOCK=true.

CREDS_ROOT=/credentials
SETTINGS_JSON=/home/agent/.claude/settings.json
SETTINGS_LOCAL=/home/agent/.claude/settings.local.json

# --- Ad-blocking ---
if [ "$ENABLE_ADBLOCK" = "true" ]; then
    ADBLOCK_HOSTS=/opt/adblock-hosts.txt
    if [ -f "$ADBLOCK_HOSTS" ]; then
        log_info "Applying ad-block hosts from $ADBLOCK_HOSTS..."
        # Append only if not already present (idempotent)
        if ! grep -q "# AgentCore adblock" /etc/hosts 2>/dev/null; then
            echo "" >> /etc/hosts
            echo "# AgentCore adblock" >> /etc/hosts
            cat "$ADBLOCK_HOSTS" >> /etc/hosts
            log_info "Ad-block hosts applied."
        else
            log_debug "Ad-block hosts already present in /etc/hosts."
        fi
    else
        log_warn "ENABLE_ADBLOCK=true but $ADBLOCK_HOSTS not found."
    fi
fi

# --- Credential refresh daemon ---
log_info "Starting credential refresh daemon (interval: ${CRED_REFRESH_INTERVAL}s)..."

(
    while true; do
        sleep "$CRED_REFRESH_INTERVAL"

        # Re-copy credentials if mount is present
        if [ -d "$CREDS_ROOT" ]; then

            # Claude credentials
            CREDS_CLAUDE="$CREDS_ROOT/claude"
            if [ -d "$CREDS_CLAUDE" ]; then
                for file in .credentials.json statsig; do
                    src="$CREDS_CLAUDE/$file"
                    dst="/home/agent/.claude/$file"
                    if [ -e "$src" ]; then
                        if [ -d "$src" ]; then
                            cp -r "$src" "$dst" 2>/dev/null || true
                        else
                            cp "$src" "$dst" 2>/dev/null || true
                        fi
                    fi
                done

                # Merge settings.json — preserve apiKeyHelper and proxy env vars
                if [ -f "$CREDS_CLAUDE/settings.json" ]; then
                    python3 - <<PYEOF
import json, os

incoming_path = "$CREDS_CLAUDE/settings.json"
current_path  = "$SETTINGS_JSON"

try:
    with open(incoming_path) as f:
        incoming = json.load(f)
except Exception:
    incoming = {}

try:
    with open(current_path) as f:
        current = json.load(f)
except Exception:
    current = {}

# Fields to preserve from the current (runtime) config
PRESERVE_KEYS = ["apiKeyHelper", "env", "skipDangerousModePermissionPrompt"]

merged = {**incoming}
for key in PRESERVE_KEYS:
    if key in current:
        if key == "env" and key in incoming:
            # Deep merge env: incoming values are overridden by current runtime values
            merged_env = {**incoming.get("env", {})}
            # Preserve proxy-related and key-related runtime env vars
            PRESERVE_ENV = [
                "ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY",
                "LLM_PROXY_URL", "CODEGATE_URL",
                "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
            ]
            for evar in PRESERVE_ENV:
                if evar in current.get("env", {}):
                    merged_env[evar] = current["env"][evar]
            merged["env"] = merged_env
        else:
            merged[key] = current[key]

os.makedirs(os.path.dirname(current_path), exist_ok=True)
with open(current_path, "w") as f:
    json.dump(merged, f, indent=2)
PYEOF
                fi

                # Merge settings.local.json
                if [ -f "$CREDS_CLAUDE/settings.local.json" ]; then
                    python3 - <<PYEOF
import json, os

incoming_path = "$CREDS_CLAUDE/settings.local.json"
current_path  = "$SETTINGS_LOCAL"

try:
    with open(incoming_path) as f:
        incoming = json.load(f)
except Exception:
    incoming = {}

try:
    with open(current_path) as f:
        current = json.load(f)
except Exception:
    current = {}

# Merge: incoming provides base, current runtime values win
merged = {**incoming, **current}

os.makedirs(os.path.dirname(current_path), exist_ok=True)
with open(current_path, "w") as f:
    json.dump(merged, f, indent=2)
PYEOF
                fi

                chown -R agent:agent /home/agent/.claude 2>/dev/null || true
            fi

            # SSH credentials
            CREDS_SSH="$CREDS_ROOT/ssh"
            if [ -d "$CREDS_SSH" ]; then
                cp -r "$CREDS_SSH/." /home/agent/.ssh/ 2>/dev/null || true
                chmod 700 /home/agent/.ssh 2>/dev/null || true
                find /home/agent/.ssh -type f -exec chmod 600 {} \; 2>/dev/null || true
                chown -R agent:agent /home/agent/.ssh 2>/dev/null || true
            fi

            # API key .env files
            CREDS_API="$CREDS_ROOT/api-keys"
            if [ -d "$CREDS_API" ]; then
                while IFS= read -r -d '' envfile; do
                    # shellcheck disable=SC1090
                    source "$envfile" 2>/dev/null || true
                done < <(find "$CREDS_API" -name "*.env" -print0)
            fi
        fi

    done
) &

log_info "Credential refresh daemon started (pid $!)."
