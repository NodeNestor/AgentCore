"""
Shared pytest fixtures for AgentCore test suite.
"""

import os
import tempfile
import pytest

# Absolute paths to real config/data files
AGENTCORE_ROOT = os.path.join(os.path.dirname(__file__), "..")
LIBRARY_JSON_PATH = os.path.abspath(
    os.path.join(AGENTCORE_ROOT, "mcp-tools", "library.json")
)
CHROME_POLICIES_PATH = os.path.abspath(
    os.path.join(AGENTCORE_ROOT, "config", "chrome-policies.json")
)
SSHD_CONFIG_PATH = os.path.abspath(
    os.path.join(AGENTCORE_ROOT, "config", "sshd_config")
)


@pytest.fixture
def tmp_memory_dir(tmp_path):
    """Temporary directory for agent-memory tests."""
    mem_dir = tmp_path / "agent-memory"
    mem_dir.mkdir()
    return str(mem_dir)


@pytest.fixture
def library_json_path():
    """Path to the real mcp-tools/library.json."""
    return LIBRARY_JSON_PATH


@pytest.fixture
def chrome_policies_path():
    """Path to the real config/chrome-policies.json."""
    return CHROME_POLICIES_PATH


@pytest.fixture
def sshd_config_path():
    """Path to the real config/sshd_config."""
    return SSHD_CONFIG_PATH
