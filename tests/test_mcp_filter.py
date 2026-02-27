"""
Tests for the MCP tool filtering logic extracted from
entrypoint/modules/50-mcp-tools.sh (the embedded Python block).

The standalone filter_mcp_tools() function replicates the filtering
logic faithfully so it can be exercised in isolation.
"""

import pytest


# ---------------------------------------------------------------------------
# Standalone reimplementation of the filtering logic
# (mirrors the Python block in 50-mcp-tools.sh exactly)
# ---------------------------------------------------------------------------

def filter_mcp_tools(library_data: dict, env_vars: dict, enable_desktop: bool) -> dict:
    """
    Filter MCP tools from library_data according to the rules in 50-mcp-tools.sh.

    Args:
        library_data:   Parsed contents of library.json (dict).
        env_vars:       Mapping of environment variable names to their values.
        enable_desktop: Whether desktop support is enabled (ENABLE_DESKTOP=true).

    Returns:
        A dict of the form {"mcpServers": { name: entry, ... }}.
    """
    servers = library_data.get("mcpServers", {})
    included = {}

    for name, tool in servers.items():
        # Skip desktop-only tools when desktop is not enabled
        if tool.get("requiresDesktop", False) and not enable_desktop:
            continue

        # Check required env vars
        required_env = tool.get("requiredEnv", [])
        has_env = True
        for var in required_env:
            if not env_vars.get(var):
                has_env = False
                break
        if not has_env:
            continue

        # Include if: default=true OR required env vars are all present (opt-in)
        is_default = tool.get("default", False)
        has_required_env = len(required_env) > 0 and has_env
        if not is_default and not has_required_env:
            continue

        # Build MCP entry
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

    return {"mcpServers": included}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _lib(*tools):
    """Build a library_data dict from a list of (name, config) tuples."""
    return {"mcpServers": {name: cfg for name, cfg in tools}}


def _tool(*, command="python3", args=None, default=False,
          requires_desktop=False, required_env=None, url=None):
    """Convenience builder for a single tool config dict."""
    cfg = {
        "command": command,
        "default": default,
        "requiresDesktop": requires_desktop,
    }
    if args is not None:
        cfg["args"] = args
    if required_env is not None:
        cfg["requiredEnv"] = required_env
    if url is not None:
        cfg["url"] = url
        del cfg["command"]  # url-style tools don't have command
    return cfg


# ===========================================================================
# Individual filter rules
# ===========================================================================

class TestDesktopFiltering:
    def test_desktop_only_tool_excluded_when_desktop_disabled(self):
        lib = _lib(("desk", _tool(requires_desktop=True, default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "desk" not in result["mcpServers"]

    def test_desktop_only_tool_included_when_desktop_enabled(self):
        lib = _lib(("desk", _tool(requires_desktop=True, default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=True)
        assert "desk" in result["mcpServers"]

    def test_non_desktop_tool_included_regardless_of_flag(self):
        lib = _lib(("plain", _tool(requires_desktop=False, default=True)))
        result_off = filter_mcp_tools(lib, {}, enable_desktop=False)
        result_on = filter_mcp_tools(lib, {}, enable_desktop=True)
        assert "plain" in result_off["mcpServers"]
        assert "plain" in result_on["mcpServers"]


class TestRequiredEnvFiltering:
    def test_tool_with_missing_required_env_excluded(self):
        lib = _lib(("gh", _tool(required_env=["GITHUB_TOKEN"])))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "gh" not in result["mcpServers"]

    def test_tool_with_present_required_env_included(self):
        lib = _lib(("gh", _tool(required_env=["GITHUB_TOKEN"])))
        result = filter_mcp_tools(lib, {"GITHUB_TOKEN": "ghp_abc123"}, enable_desktop=False)
        assert "gh" in result["mcpServers"]

    def test_tool_with_empty_string_env_value_excluded(self):
        lib = _lib(("gh", _tool(required_env=["GITHUB_TOKEN"])))
        result = filter_mcp_tools(lib, {"GITHUB_TOKEN": ""}, enable_desktop=False)
        assert "gh" not in result["mcpServers"]

    def test_tool_with_multiple_required_env_all_present(self):
        lib = _lib(("db", _tool(required_env=["DB_HOST", "DB_PASS"])))
        result = filter_mcp_tools(
            lib,
            {"DB_HOST": "localhost", "DB_PASS": "secret"},
            enable_desktop=False
        )
        assert "db" in result["mcpServers"]

    def test_tool_with_multiple_required_env_one_missing(self):
        lib = _lib(("db", _tool(required_env=["DB_HOST", "DB_PASS"])))
        result = filter_mcp_tools(lib, {"DB_HOST": "localhost"}, enable_desktop=False)
        assert "db" not in result["mcpServers"]


class TestDefaultAndOptInLogic:
    def test_default_tool_always_included(self):
        lib = _lib(("fs", _tool(default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "fs" in result["mcpServers"]

    def test_non_default_tool_without_required_env_excluded(self):
        lib = _lib(("optional", _tool(default=False)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "optional" not in result["mcpServers"]

    def test_non_default_tool_with_required_env_present_included(self):
        lib = _lib(("opt", _tool(default=False, required_env=["OPT_KEY"])))
        result = filter_mcp_tools(lib, {"OPT_KEY": "val"}, enable_desktop=False)
        assert "opt" in result["mcpServers"]

    def test_non_default_tool_with_required_env_missing_excluded(self):
        lib = _lib(("opt", _tool(default=False, required_env=["OPT_KEY"])))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "opt" not in result["mcpServers"]


class TestEdgeCases:
    def test_empty_library_returns_empty_output(self):
        result = filter_mcp_tools({}, {}, enable_desktop=False)
        assert result == {"mcpServers": {}}

    def test_missing_mcp_servers_key_returns_empty_output(self):
        result = filter_mcp_tools({"other": "data"}, {}, enable_desktop=False)
        assert result == {"mcpServers": {}}

    def test_multiple_tools_mixed_results(self):
        lib = _lib(
            ("default-tool", _tool(default=True)),
            ("opt-tool", _tool(default=False, required_env=["MY_KEY"])),
            ("excluded-tool", _tool(default=False)),
        )
        result = filter_mcp_tools(lib, {"MY_KEY": "val"}, enable_desktop=False)
        assert "default-tool" in result["mcpServers"]
        assert "opt-tool" in result["mcpServers"]
        assert "excluded-tool" not in result["mcpServers"]


class TestOutputStructure:
    def test_output_has_mcp_servers_dict(self):
        result = filter_mcp_tools({}, {}, enable_desktop=False)
        assert "mcpServers" in result
        assert isinstance(result["mcpServers"], dict)

    def test_included_entry_has_command(self):
        lib = _lib(("tool", _tool(command="npx", args=["pkg"], default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        entry = result["mcpServers"]["tool"]
        assert entry["command"] == "npx"

    def test_included_entry_has_args(self):
        lib = _lib(("tool", _tool(command="npx", args=["@pkg/server", "--flag"], default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        entry = result["mcpServers"]["tool"]
        assert entry["args"] == ["@pkg/server", "--flag"]

    def test_included_entry_has_url_when_url_style(self):
        lib = _lib(("web-tool", _tool(url="https://example.com/mcp", default=True)))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        entry = result["mcpServers"]["web-tool"]
        assert "url" in entry
        assert entry["url"] == "https://example.com/mcp"

    def test_included_entry_has_env_when_present(self):
        tool_cfg = _tool(default=True)
        tool_cfg["env"] = {"FOO": "bar"}
        lib = _lib(("envtool", tool_cfg))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        entry = result["mcpServers"]["envtool"]
        assert entry["env"] == {"FOO": "bar"}

    def test_excluded_fields_not_in_entry(self):
        """Fields like 'name', 'description', 'builtIn', 'category' etc. should not be copied."""
        tool_cfg = _tool(default=True)
        tool_cfg["name"] = "My Tool"
        tool_cfg["description"] = "Does stuff"
        tool_cfg["builtIn"] = True
        tool_cfg["category"] = "testing"
        lib = _lib(("t", tool_cfg))
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        entry = result["mcpServers"]["t"]
        assert "name" not in entry
        assert "description" not in entry
        assert "builtIn" not in entry
        assert "category" not in entry


# ===========================================================================
# Integration-style test against real library.json
# ===========================================================================

class TestRealLibraryFiltering:
    def test_default_tools_included_no_env(self, library_json_path):
        import json
        with open(library_json_path) as f:
            lib = json.load(f)
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        included = result["mcpServers"]
        # filesystem, playwright, context7, agent-memory are default=true and non-desktop
        for expected in ("filesystem", "playwright", "context7", "agent-memory"):
            assert expected in included, f"Expected '{expected}' to be included by default"

    def test_desktop_control_excluded_without_desktop(self, library_json_path):
        import json
        with open(library_json_path) as f:
            lib = json.load(f)
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "desktop-control" not in result["mcpServers"]

    def test_github_excluded_without_token(self, library_json_path):
        import json
        with open(library_json_path) as f:
            lib = json.load(f)
        result = filter_mcp_tools(lib, {}, enable_desktop=False)
        assert "github" not in result["mcpServers"]

    def test_github_included_with_token(self, library_json_path):
        import json
        with open(library_json_path) as f:
            lib = json.load(f)
        result = filter_mcp_tools(lib, {"GITHUB_TOKEN": "ghp_test"}, enable_desktop=False)
        assert "github" in result["mcpServers"]
