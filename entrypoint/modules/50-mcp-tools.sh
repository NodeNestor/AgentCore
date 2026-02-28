#!/bin/bash
# Module: 50-mcp-tools
# MCP tool discovery, filtering, and configuration.
#
# Uses `claude mcp add-json` to register MCP servers through Claude Code's
# own config system. This ensures compatibility across Claude Code versions.
#
# Falls back to direct settings.json writing for non-Claude agent types.

MCP_LIBRARY=/opt/mcp-tools/library.json
MCP_CUSTOM_DIR=/opt/mcp-tools/custom
SETTINGS_JSON=/home/agent/.claude/settings.json

log_info "Configuring MCP tools..."

if [ ! -f "$MCP_LIBRARY" ]; then
    log_warn "MCP tool library not found at $MCP_LIBRARY. Skipping."
    return 0
fi

# Build the list of MCP servers to include (filtering by env/desktop)
INCLUDED_JSON=$(python3 - <<PYEOF
import json
import os
import sys

library_path = "$MCP_LIBRARY"
custom_dir   = "$MCP_CUSTOM_DIR"
enable_desktop = os.environ.get("ENABLE_DESKTOP", "false").lower()
hiveminddb_url = os.environ.get("HIVEMINDDB_URL", "")

try:
    with open(library_path) as f:
        library = json.load(f)
except Exception as e:
    print(f"[ERROR] Could not read MCP library: {e}", file=sys.stderr)
    print("{}")
    sys.exit(0)

servers = library.get("mcpServers", {})
included = {}

for name, tool in servers.items():
    # Skip agent-memory when HiveMindDB replaces it
    if name == "agent-memory" and hiveminddb_url:
        print(f"[INFO]  [50-mcp-tools] Skipping {name}: replaced by hiveminddb", file=sys.stderr)
        continue

    if tool.get("requiresDesktop", False) and enable_desktop != "true":
        print(f"[INFO]  [50-mcp-tools] Skipping {name}: requiresDesktop=true but desktop is off.", file=sys.stderr)
        continue

    required_env = tool.get("requiredEnv", [])
    has_env = True
    for var in required_env:
        if not os.environ.get(var):
            print(f"[INFO]  [50-mcp-tools] Skipping {name}: required env '{var}' is not set.", file=sys.stderr)
            has_env = False
            break
    if not has_env:
        continue

    is_default = tool.get("default", False)
    has_required_env = len(required_env) > 0 and has_env
    if not is_default and not has_required_env:
        print(f"[INFO]  [50-mcp-tools] Skipping {name}: not default and no env triggers.", file=sys.stderr)
        continue

    # Build MCP entry
    entry = {}
    for key in ("command", "args", "url"):
        if key in tool:
            entry[key] = tool[key]

    # Inject requiredEnv values into the entry's env block
    # so the MCP server process gets these vars at runtime
    env_block = dict(tool.get("env", {}))
    for var in required_env:
        val = os.environ.get(var, "")
        if val:
            env_block[var] = val
    if env_block:
        entry["env"] = env_block

    included[name] = entry
    print(f"[INFO]  [50-mcp-tools] Including tool: {name}", file=sys.stderr)

# Scan for custom tools
if os.path.isdir(custom_dir):
    for entry_name in os.listdir(custom_dir):
        tool_path = os.path.join(custom_dir, entry_name)
        manifest_path = os.path.join(tool_path, "manifest.json")
        if not os.path.isfile(manifest_path):
            continue
        try:
            with open(manifest_path) as f:
                manifest = json.load(f)
            name = manifest.get("name", entry_name)
            entry = {}
            for key in ("command", "args", "env", "url"):
                if key in manifest:
                    entry[key] = manifest[key]
            included[name] = entry
            print(f"[INFO]  [50-mcp-tools] Including custom tool: {name}", file=sys.stderr)
        except Exception as e:
            print(f"[WARN]  [50-mcp-tools] Failed to read custom tool: {manifest_path}: {e}", file=sys.stderr)

# Output as JSON to stdout
print(json.dumps(included))
PYEOF
)

if [ -z "$INCLUDED_JSON" ] || [ "$INCLUDED_JSON" = "{}" ]; then
    log_info "No MCP tools to configure."
    return 0
fi

TOOL_COUNT=$(echo "$INCLUDED_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
log_info "Registering $TOOL_COUNT MCP tool(s)..."

# For Claude agent types: use `claude mcp add-json` (officially supported)
case "$AGENT_TYPE" in
    claude|all)
        python3 - <<PYEOF
import json
import subprocess
import sys

included = json.loads('''$INCLUDED_JSON''')

for name, config in included.items():
    config_json = json.dumps(config)
    cmd = ["su", "-", "agent", "-c",
           f"claude mcp add-json -s user {name} '{config_json}' 2>&1"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        output = result.stdout.strip()
        if "Added" in output or "Updated" in output:
            print(f"[INFO]  [50-mcp-tools] Registered {name} via claude mcp add-json")
        else:
            print(f"[WARN]  [50-mcp-tools] claude mcp add-json {name}: {output}", file=sys.stderr)
    except Exception as e:
        print(f"[WARN]  [50-mcp-tools] Failed to register {name}: {e}", file=sys.stderr)

print(f"[INFO]  [50-mcp-tools] Registered {len(included)} MCP tool(s) via Claude Code CLI")
PYEOF
        ;;

    *)
        # For non-Claude agents: write directly to settings.json
        python3 - <<PYEOF
import json
import os

settings_path = "$SETTINGS_JSON"
included = json.loads('''$INCLUDED_JSON''')

try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

settings["mcpServers"] = included

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print(f"[INFO]  [50-mcp-tools] Wrote {len(included)} MCP tool(s) to {settings_path}")
PYEOF
        chown agent:agent "$SETTINGS_JSON" 2>/dev/null || true
        ;;
esac

log_info "MCP tool configuration complete."
