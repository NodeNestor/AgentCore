"""
Tests for the LLM configuration merge logic extracted from
entrypoint/modules/60-llm-config.sh (the _merge_llm_settings Python block).

The standalone merge_llm_settings() function replicates the logic faithfully
so it can be unit-tested without running bash.
"""

import json
import os

import pytest


# ---------------------------------------------------------------------------
# Standalone reimplementation of the merge logic from 60-llm-config.sh
# (mirrors the Python block in _merge_llm_settings exactly)
# ---------------------------------------------------------------------------

API_KEY_HELPER_PATH = "/home/agent/.claude/apiKeyHelper.sh"


def merge_llm_settings(existing_data: dict, base_url: str,
                       use_helper: bool, direct_key: str) -> dict:
    """
    Replicate _merge_llm_settings from 60-llm-config.sh.

    Args:
        existing_data: The existing settings.json content (or {} if missing).
        base_url:      Value to set for ANTHROPIC_BASE_URL (empty string = skip).
        use_helper:    If True, set apiKeyHelper and remove ANTHROPIC_API_KEY.
        direct_key:    If use_helper is False and this is non-empty, set
                       ANTHROPIC_API_KEY and remove apiKeyHelper.

    Returns:
        The updated settings dict (not written to disk).
    """
    data = dict(existing_data)  # shallow copy so we don't mutate the input
    data.setdefault("env", {})

    if base_url:
        data["env"]["ANTHROPIC_BASE_URL"] = base_url

    if use_helper:
        data["apiKeyHelper"] = API_KEY_HELPER_PATH
        data["env"].pop("ANTHROPIC_API_KEY", None)
    elif direct_key:
        data["env"]["ANTHROPIC_API_KEY"] = direct_key
        data.pop("apiKeyHelper", None)

    # Always set skip permissions prompt
    data["skipDangerousModePermissionPrompt"] = True

    return data


# ===========================================================================
# CODEGATE_URL / base_url tests
# ===========================================================================

class TestBaseUrl:
    def test_base_url_sets_anthropic_base_url(self):
        result = merge_llm_settings({}, "http://localhost:9212", use_helper=True, direct_key="")
        assert result["env"]["ANTHROPIC_BASE_URL"] == "http://localhost:9212"

    def test_codegate_url_sets_base_url(self):
        result = merge_llm_settings({}, "https://codegate.example.com", use_helper=True, direct_key="")
        assert result["env"]["ANTHROPIC_BASE_URL"] == "https://codegate.example.com"

    def test_empty_base_url_does_not_set_anthropic_base_url(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="sk-abc")
        assert "ANTHROPIC_BASE_URL" not in result["env"]

    def test_existing_base_url_overwritten_when_provided(self):
        existing = {"env": {"ANTHROPIC_BASE_URL": "https://old.example.com"}}
        result = merge_llm_settings(existing, "https://new.example.com", use_helper=True, direct_key="")
        assert result["env"]["ANTHROPIC_BASE_URL"] == "https://new.example.com"

    def test_existing_base_url_preserved_when_no_new_url(self):
        existing = {"env": {"ANTHROPIC_BASE_URL": "https://keep.example.com"}}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="")
        assert result["env"]["ANTHROPIC_BASE_URL"] == "https://keep.example.com"


# ===========================================================================
# use_helper=True tests
# ===========================================================================

class TestUseHelper:
    def test_use_helper_sets_api_key_helper(self):
        result = merge_llm_settings({}, "http://proxy", use_helper=True, direct_key="")
        assert result.get("apiKeyHelper") == API_KEY_HELPER_PATH

    def test_use_helper_removes_anthropic_api_key_from_env(self):
        existing = {"env": {"ANTHROPIC_API_KEY": "sk-existing"}}
        result = merge_llm_settings(existing, "http://proxy", use_helper=True, direct_key="")
        assert "ANTHROPIC_API_KEY" not in result["env"]

    def test_use_helper_does_not_set_api_key_in_env(self):
        result = merge_llm_settings({}, "http://proxy", use_helper=True, direct_key="")
        assert "ANTHROPIC_API_KEY" not in result["env"]

    def test_use_helper_true_overrides_existing_api_key(self):
        existing = {"env": {"ANTHROPIC_API_KEY": "sk-old"}, "apiKeyHelper": "/old/path"}
        result = merge_llm_settings(existing, "http://proxy", use_helper=True, direct_key="")
        assert result["apiKeyHelper"] == API_KEY_HELPER_PATH
        assert "ANTHROPIC_API_KEY" not in result["env"]


# ===========================================================================
# use_helper=False with direct_key tests
# ===========================================================================

class TestDirectKey:
    def test_direct_key_sets_anthropic_api_key(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="sk-direct123")
        assert result["env"]["ANTHROPIC_API_KEY"] == "sk-direct123"

    def test_direct_key_removes_api_key_helper(self):
        existing = {"apiKeyHelper": API_KEY_HELPER_PATH}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="sk-direct123")
        assert "apiKeyHelper" not in result

    def test_no_direct_key_and_no_helper_leaves_env_unchanged(self):
        existing = {"env": {"OTHER": "value"}}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="")
        assert "ANTHROPIC_API_KEY" not in result["env"]
        assert "apiKeyHelper" not in result

    def test_direct_key_replaces_old_api_key(self):
        existing = {"env": {"ANTHROPIC_API_KEY": "sk-old"}}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="sk-new")
        assert result["env"]["ANTHROPIC_API_KEY"] == "sk-new"


# ===========================================================================
# skipDangerousModePermissionPrompt always True
# ===========================================================================

class TestSkipPermissions:
    def test_skip_prompt_always_set_to_true(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="")
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_skip_prompt_set_even_with_no_llm_config(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="")
        assert result.get("skipDangerousModePermissionPrompt") is True

    def test_skip_prompt_set_when_using_helper(self):
        result = merge_llm_settings({}, "http://proxy", use_helper=True, direct_key="")
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_skip_prompt_set_when_using_direct_key(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="sk-abc")
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_skip_prompt_overrides_existing_false(self):
        existing = {"skipDangerousModePermissionPrompt": False}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="")
        assert result["skipDangerousModePermissionPrompt"] is True


# ===========================================================================
# Existing settings are preserved
# ===========================================================================

class TestExistingSettingsPreserved:
    def test_existing_top_level_keys_preserved(self):
        existing = {"theme": "dark", "fontSize": 14}
        result = merge_llm_settings(existing, "http://proxy", use_helper=True, direct_key="")
        assert result["theme"] == "dark"
        assert result["fontSize"] == 14

    def test_existing_env_keys_preserved(self):
        existing = {"env": {"CUSTOM_VAR": "custom_value", "PATH": "/usr/bin"}}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="sk-abc")
        assert result["env"]["CUSTOM_VAR"] == "custom_value"
        assert result["env"]["PATH"] == "/usr/bin"

    def test_existing_env_keys_not_overwritten_unless_targeted(self):
        existing = {"env": {"UNRELATED": "stays", "ANTHROPIC_API_KEY": "sk-old"}}
        result = merge_llm_settings(existing, "", use_helper=False, direct_key="sk-new")
        assert result["env"]["UNRELATED"] == "stays"
        assert result["env"]["ANTHROPIC_API_KEY"] == "sk-new"

    def test_empty_existing_data_initializes_correctly(self):
        result = merge_llm_settings({}, "http://proxy", use_helper=True, direct_key="")
        assert "env" in result
        assert isinstance(result["env"], dict)

    def test_none_like_empty_dict_produces_valid_output(self):
        result = merge_llm_settings({}, "", use_helper=False, direct_key="")
        assert result["skipDangerousModePermissionPrompt"] is True
        assert "env" in result


# ===========================================================================
# Roundtrip: simulate bash module decision logic
# ===========================================================================

class TestModuleScenarios:
    """Simulate the three code paths in 60-llm-config.sh."""

    def test_codegate_url_scenario(self):
        """CODEGATE_URL set → use_helper=True, base_url=CODEGATE_URL."""
        result = merge_llm_settings(
            {},
            base_url="http://codegate:9212",
            use_helper=True,
            direct_key=""
        )
        assert result["env"]["ANTHROPIC_BASE_URL"] == "http://codegate:9212"
        assert result["apiKeyHelper"] == API_KEY_HELPER_PATH
        assert "ANTHROPIC_API_KEY" not in result["env"]
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_llm_proxy_url_scenario(self):
        """LLM_PROXY_URL set → same as codegate path."""
        result = merge_llm_settings(
            {},
            base_url="https://proxy.internal",
            use_helper=True,
            direct_key=""
        )
        assert result["env"]["ANTHROPIC_BASE_URL"] == "https://proxy.internal"
        assert result["apiKeyHelper"] == API_KEY_HELPER_PATH
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_direct_api_key_scenario(self):
        """ANTHROPIC_API_KEY set → use_helper=False, direct_key=key."""
        result = merge_llm_settings(
            {},
            base_url="",
            use_helper=False,
            direct_key="sk-ant-12345"
        )
        assert result["env"]["ANTHROPIC_API_KEY"] == "sk-ant-12345"
        assert "ANTHROPIC_BASE_URL" not in result["env"]
        assert "apiKeyHelper" not in result
        assert result["skipDangerousModePermissionPrompt"] is True

    def test_no_config_scenario(self):
        """No env set → use_helper=False, base_url='', direct_key=''."""
        result = merge_llm_settings({}, "", use_helper=False, direct_key="")
        assert result["skipDangerousModePermissionPrompt"] is True
        assert "ANTHROPIC_API_KEY" not in result["env"]
        assert "ANTHROPIC_BASE_URL" not in result["env"]
        assert "apiKeyHelper" not in result
