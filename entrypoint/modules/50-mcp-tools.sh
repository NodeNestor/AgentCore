#!/bin/bash
# Module: 50-mcp-tools
# MCP tool discovery, filtering, and configuration.

MCP_LIBRARY=/opt/mcp-tools/library.json
MCP_CUSTOM_DIR=/opt/mcp-tools/custom
MCP_OUT=/home/agent/.claude/mcp.json

log_info "Configuring MCP tools..."

if [ ! -f "$MCP_LIBRARY" ]; then
    log_warn "MCP tool library not found at $MCP_LIBRARY. Skipping."
    return 0
fi

python3 - <<PYEOF
import json
import os
import sys

library_path = "$MCP_LIBRARY"
custom_dir   = "$MCP_CUSTOM_DIR"
out_path     = "$MCP_OUT"
enable_desktop = os.environ.get("ENABLE_DESKTOP", "false").lower()

try:
    with open(library_path) as f:
        library = json.load(f)
except Exception as e:
    print(f"[ERROR] Could not read MCP library: {e}", file=sys.stderr)
    sys.exit(0)

# library.json uses mcpServers dict: { "name": { ...config... } }
servers = library.get("mcpServers", {})

included = {}

for name, tool in servers.items():
    # Skip desktop-only tools when desktop is not enabled
    if tool.get("requiresDesktop", False) and enable_desktop != "true":
        print(f"[INFO]  [50-mcp-tools] Skipping {name}: requiresDesktop=true but desktop is off.")
        continue

    # Check required env vars
    required_env = tool.get("requiredEnv", [])
    has_env = True
    for var in required_env:
        if not os.environ.get(var):
            print(f"[INFO]  [50-mcp-tools] Skipping {name}: required env '{var}' is not set.")
            has_env = False
            break
    if not has_env:
        continue

    # Include if: default=true OR required env vars are all present (opt-in tools)
    is_default = tool.get("default", False)
    has_required_env = len(required_env) > 0 and has_env
    if not is_default and not has_required_env:
        print(f"[INFO]  [50-mcp-tools] Skipping {name}: not default and no env triggers.")
        continue

    # Build MCP entry — support both "command" style and "url" style
    entry = {}
    if "command" in tool:
        entry["command"] = tool["command"]
    if "args" in tool:
        entry["args"] = tool["args"]
    if "env" in tool:
        entry["env"] = tool["env"]
    if "url" in tool:
        entry["url"] = tool["url"]

    included[name] = entry
    print(f"[INFO]  [50-mcp-tools] Including tool: {name}")

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
            if "command" in manifest:
                entry["command"] = manifest["command"]
            if "args" in manifest:
                entry["args"] = manifest["args"]
            if "env" in manifest:
                entry["env"] = manifest["env"]
            if "url" in manifest:
                entry["url"] = manifest["url"]
            included[name] = entry
            print(f"[INFO]  [50-mcp-tools] Including custom tool: {name}")
        except Exception as e:
            print(f"[WARN]  [50-mcp-tools] Failed to read custom tool manifest {manifest_path}: {e}", file=sys.stderr)

# Write the final MCP config
mcp_config = {"mcpServers": included}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(mcp_config, f, indent=2)

print(f"[INFO]  [50-mcp-tools] Wrote {len(included)} MCP tool(s) to {out_path}")
PYEOF

chown agent:agent "$MCP_OUT" 2>/dev/null || true
log_info "MCP tool configuration complete."
