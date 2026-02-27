"""
Validate JSON config files and sshd_config for AgentCore.

Covers:
- mcp-tools/library.json structure and content
- config/chrome-policies.json values
- config/sshd_config directives
"""

import json
import os
import re

import pytest


# ===========================================================================
# library.json
# ===========================================================================

class TestLibraryJson:
    @pytest.fixture(autouse=True)
    def load(self, library_json_path):
        with open(library_json_path) as f:
            self.data = json.load(f)

    def test_valid_json(self):
        # If we got here, json.load() succeeded
        assert isinstance(self.data, dict)

    def test_has_mcp_servers_key(self):
        assert "mcpServers" in self.data

    def test_every_entry_has_command_or_url(self):
        for name, tool in self.data["mcpServers"].items():
            assert "command" in tool or "url" in tool, (
                f"Tool '{name}' has neither 'command' nor 'url'"
            )

    def test_required_env_is_list_when_present(self):
        for name, tool in self.data["mcpServers"].items():
            if "requiredEnv" in tool:
                assert isinstance(tool["requiredEnv"], list), (
                    f"Tool '{name}': requiredEnv must be a list"
                )

    def test_requires_desktop_is_boolean_when_present(self):
        for name, tool in self.data["mcpServers"].items():
            if "requiresDesktop" in tool:
                assert isinstance(tool["requiresDesktop"], bool), (
                    f"Tool '{name}': requiresDesktop must be bool"
                )

    def test_default_is_boolean_when_present(self):
        for name, tool in self.data["mcpServers"].items():
            if "default" in tool:
                assert isinstance(tool["default"], bool), (
                    f"Tool '{name}': default must be bool"
                )

    def test_args_is_list_when_present(self):
        for name, tool in self.data["mcpServers"].items():
            if "args" in tool:
                assert isinstance(tool["args"], list), (
                    f"Tool '{name}': args must be a list"
                )

    def test_all_12_expected_tools_present(self):
        expected = {
            "desktop-control",
            "filesystem",
            "playwright",
            "context7",
            "github",
            "postgres",
            "sqlite",
            "memory",
            "fetch",
            "agent-memory",
            "mem0",
            "qdrant",
        }
        present = set(self.data["mcpServers"].keys())
        missing = expected - present
        assert not missing, f"Missing tools in library.json: {missing}"

    def test_desktop_only_tools_have_requires_desktop_true(self):
        desktop_tools = {"desktop-control"}
        for name in desktop_tools:
            tool = self.data["mcpServers"].get(name, {})
            assert tool.get("requiresDesktop") is True, (
                f"Tool '{name}' should have requiresDesktop=true"
            )

    def test_tools_with_required_env_are_not_default_true(self):
        """
        Tools that require env vars are opt-in and should not be default=true.
        (They would be silently skipped if a user doesn't have the env var,
        so defaulting them to true would cause confusing missing-tool errors.)
        """
        for name, tool in self.data["mcpServers"].items():
            if tool.get("requiredEnv"):
                assert tool.get("default", False) is False, (
                    f"Tool '{name}' has requiredEnv but is also default=true; "
                    "it should be opt-in (default=false)"
                )

    def test_desktop_control_is_not_default(self):
        tool = self.data["mcpServers"]["desktop-control"]
        assert tool.get("default", False) is False

    def test_filesystem_is_default(self):
        tool = self.data["mcpServers"]["filesystem"]
        assert tool.get("default") is True

    def test_playwright_is_default(self):
        tool = self.data["mcpServers"]["playwright"]
        assert tool.get("default") is True

    def test_context7_is_default(self):
        tool = self.data["mcpServers"]["context7"]
        assert tool.get("default") is True

    def test_agent_memory_is_default(self):
        tool = self.data["mcpServers"]["agent-memory"]
        assert tool.get("default") is True

    def test_github_has_required_env(self):
        tool = self.data["mcpServers"]["github"]
        assert "requiredEnv" in tool
        assert "GITHUB_TOKEN" in tool["requiredEnv"]

    def test_postgres_has_required_env(self):
        tool = self.data["mcpServers"]["postgres"]
        assert "requiredEnv" in tool

    def test_mem0_has_required_env(self):
        tool = self.data["mcpServers"]["mem0"]
        assert "requiredEnv" in tool
        assert "MEM0_API_KEY" in tool["requiredEnv"]

    def test_qdrant_has_required_env(self):
        tool = self.data["mcpServers"]["qdrant"]
        assert "requiredEnv" in tool
        assert "QDRANT_URL" in tool["requiredEnv"]


# ===========================================================================
# chrome-policies.json
# ===========================================================================

class TestChromePolicies:
    @pytest.fixture(autouse=True)
    def load(self, chrome_policies_path):
        with open(chrome_policies_path) as f:
            self.data = json.load(f)

    def test_valid_json(self):
        assert isinstance(self.data, dict)

    def test_metrics_reporting_disabled(self):
        assert self.data.get("MetricsReportingEnabled") is False

    def test_sync_disabled(self):
        assert self.data.get("SyncDisabled") is True

    def test_browser_sign_in_disabled(self):
        # BrowserSignin: 0 means sign-in is disabled
        assert self.data.get("BrowserSignin") == 0

    def test_hardware_acceleration_disabled(self):
        assert self.data.get("HardwareAccelerationModeEnabled") is False

    def test_password_manager_disabled(self):
        assert self.data.get("PasswordManagerEnabled") is False

    def test_background_mode_disabled(self):
        assert self.data.get("BackgroundModeEnabled") is False

    def test_default_browser_setting_disabled(self):
        assert self.data.get("DefaultBrowserSettingEnabled") is False


# ===========================================================================
# sshd_config
# ===========================================================================

def _parse_sshd_config(path):
    """
    Return a dict of {directive: value} from sshd_config.
    Lines starting with # are ignored; keys are lowercased.
    Multiple occurrences: last value wins.
    Lines with "Subsystem" are stored as-is for a separate assertion.
    """
    directives = {}
    subsystem_lines = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                key, val = parts
                if key.lower() == "subsystem":
                    subsystem_lines.append(line)
                directives[key.lower()] = val
    return directives, subsystem_lines


class TestSshdConfig:
    @pytest.fixture(autouse=True)
    def load(self, sshd_config_path):
        self.directives, self.subsystem_lines = _parse_sshd_config(sshd_config_path)

    def test_permit_root_login_no(self):
        assert self.directives.get("permitrootlogin", "").lower() == "no"

    def test_pubkey_authentication_yes(self):
        assert self.directives.get("pubkeyauthentication", "").lower() == "yes"

    def test_allow_users_agent(self):
        assert self.directives.get("allowusers") == "agent"

    def test_x11_forwarding_yes(self):
        assert self.directives.get("x11forwarding", "").lower() == "yes"

    def test_port_22(self):
        assert self.directives.get("port") == "22"

    def test_has_subsystem_sftp_line(self):
        assert any("sftp" in line.lower() for line in self.subsystem_lines), (
            "Expected a 'Subsystem sftp' line in sshd_config"
        )

    def test_use_pam_yes(self):
        assert self.directives.get("usepam", "").lower() == "yes"

    def test_max_auth_tries(self):
        # Should be a numeric value
        val = self.directives.get("maxauthtries", "")
        assert val.isdigit(), f"MaxAuthTries should be numeric, got: {val!r}"

    def test_strict_modes_yes(self):
        assert self.directives.get("strictmodes", "").lower() == "yes"
