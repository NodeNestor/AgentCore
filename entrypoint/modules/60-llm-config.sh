#!/bin/bash
# Module: 60-llm-config
# Configure LLM proxy / API key with priority order:
#   1. CODEGATE_URL
#   2. LLM_PROXY_URL
#   3. ANTHROPIC_API_KEY
#   4. (warn: nothing configured)

SETTINGS_JSON=/home/agent/.claude/settings.json
API_KEY_HELPER=/home/agent/.claude/apiKeyHelper.sh

_write_api_key_helper() {
    local key="$1"
    cat > "$API_KEY_HELPER" <<HELPER_EOF
#!/bin/bash
echo "${key}"
HELPER_EOF
    chmod 755 "$API_KEY_HELPER"
    chown agent:agent "$API_KEY_HELPER"
    log_debug "  apiKeyHelper written."
}

_merge_llm_settings() {
    local base_url="$1"
    local use_helper="$2"   # "true" or "false"
    local direct_key="$3"   # used when use_helper=false

    python3 - <<PYEOF
import json, os

path = "$SETTINGS_JSON"
base_url   = """$base_url"""
use_helper = "$use_helper" == "true"
direct_key = """$direct_key"""

try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

data.setdefault("env", {})

if base_url:
    data["env"]["ANTHROPIC_BASE_URL"] = base_url

if use_helper:
    data["apiKeyHelper"] = "$API_KEY_HELPER"
    # Remove any hard-coded key when using a helper
    data["env"].pop("ANTHROPIC_API_KEY", None)
elif direct_key:
    data["env"]["ANTHROPIC_API_KEY"] = direct_key
    # Remove helper reference when using a direct key
    data.pop("apiKeyHelper", None)

# Always set skip permissions prompt
data["skipDangerousModePermissionPrompt"] = True

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
print(f"[INFO]  [60-llm-config] settings.json updated.")
PYEOF
    chown agent:agent "$SETTINGS_JSON" 2>/dev/null || true
}

mkdir -p /home/agent/.claude

if [ -n "$CODEGATE_URL" ]; then
    log_info "LLM config: using CodeGate proxy at $CODEGATE_URL"
    _write_api_key_helper "${PROXY_API_KEY:-proxy}"
    _merge_llm_settings "$CODEGATE_URL" "true" ""

elif [ -n "$LLM_PROXY_URL" ]; then
    log_info "LLM config: using LLM proxy at $LLM_PROXY_URL"
    _write_api_key_helper "${PROXY_API_KEY:-proxy}"
    _merge_llm_settings "$LLM_PROXY_URL" "true" ""

elif [ -n "$ANTHROPIC_API_KEY" ]; then
    log_info "LLM config: using direct Anthropic API key."
    _merge_llm_settings "" "false" "$ANTHROPIC_API_KEY"

else
    log_warn "No LLM configuration found. Set CODEGATE_URL, LLM_PROXY_URL, or ANTHROPIC_API_KEY."
    # Still write skipDangerousModePermissionPrompt even with no key
    python3 - <<PYEOF
import json, os

path = "$SETTINGS_JSON"
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

data["skipDangerousModePermissionPrompt"] = True

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
    chown agent:agent "$SETTINGS_JSON" 2>/dev/null || true
fi

log_info "LLM config complete."
