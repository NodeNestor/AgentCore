"""
Tests for AgentCore Control API server (api/server.py).

Covers:
- _shell_quote() helper
- list_tmux_windows() parsing
- check_auth() behavior
- read_body() parsing
- create_tmux_window() agent command mapping
- HTTP route behavior via mocked handler
"""

import importlib
import io
import json
import os
import sys
import types
import unittest.mock as mock
from unittest.mock import MagicMock, patch, call

import pytest

# ---------------------------------------------------------------------------
# Module import
# The server uses module-level globals populated from env vars at import time,
# so we import it once and patch globals directly in individual tests.
# ---------------------------------------------------------------------------

API_SERVER_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "api")
)

# Add the api directory to sys.path so we can import server.py
if API_SERVER_PATH not in sys.path:
    sys.path.insert(0, API_SERVER_PATH)

import server as api_server


# ===========================================================================
# _shell_quote()
# ===========================================================================

class TestShellQuote:
    def test_basic_string(self):
        assert api_server._shell_quote("hello") == "'hello'"

    def test_string_with_spaces(self):
        assert api_server._shell_quote("hello world") == "'hello world'"

    def test_string_with_single_quotes(self):
        # Single quotes inside must be escaped as '\''
        result = api_server._shell_quote("it's a test")
        assert result == "'it'\\''s a test'"

    def test_empty_string(self):
        assert api_server._shell_quote("") == "''"

    def test_string_with_special_shell_chars(self):
        # Characters like $ and ! should remain literal inside single quotes
        result = api_server._shell_quote("echo $HOME && ls")
        assert result == "'echo $HOME && ls'"

    def test_multiple_single_quotes(self):
        result = api_server._shell_quote("a'b'c")
        assert result == "'a'\\''b'\\''c'"


# ===========================================================================
# list_tmux_windows()
# ===========================================================================

class TestListTmuxWindows:
    def test_valid_output_parsed_correctly(self):
        mock_output = "0|main|bash|1\n1|worker|claude|0\n2|logs|tail|0"
        with patch.object(api_server, "run_shell", return_value=(mock_output, "", 0)):
            windows = api_server.list_tmux_windows()

        assert len(windows) == 3

        assert windows[0]["index"] == 0
        assert windows[0]["name"] == "main"
        assert windows[0]["command"] == "bash"
        assert windows[0]["active"] is True

        assert windows[1]["index"] == 1
        assert windows[1]["name"] == "worker"
        assert windows[1]["command"] == "claude"
        assert windows[1]["active"] is False

        assert windows[2]["index"] == 2
        assert windows[2]["name"] == "logs"
        assert windows[2]["command"] == "tail"
        assert windows[2]["active"] is False

    def test_empty_output_returns_empty_list(self):
        with patch.object(api_server, "run_shell", return_value=("", "", 0)):
            windows = api_server.list_tmux_windows()
        assert windows == []

    def test_tmux_failure_returns_empty_list(self):
        with patch.object(api_server, "run_shell", return_value=("", "no server running", 1)):
            windows = api_server.list_tmux_windows()
        assert windows == []

    def test_malformed_lines_skipped(self):
        # Lines with fewer than 4 pipe-separated parts are skipped
        mock_output = "0|main|bash|1\nBADLINE\n1|worker\n2|ok|cmd|0"
        with patch.object(api_server, "run_shell", return_value=(mock_output, "", 0)):
            windows = api_server.list_tmux_windows()

        # Only lines with 4+ parts should be included
        assert len(windows) == 2
        assert windows[0]["index"] == 0
        assert windows[1]["index"] == 2

    def test_non_digit_index_kept_as_string(self):
        mock_output = "abc|special|bash|0"
        with patch.object(api_server, "run_shell", return_value=(mock_output, "", 0)):
            windows = api_server.list_tmux_windows()
        assert len(windows) == 1
        assert windows[0]["index"] == "abc"

    def test_single_window(self):
        with patch.object(api_server, "run_shell", return_value=("0|base|bash|1", "", 0)):
            windows = api_server.list_tmux_windows()
        assert len(windows) == 1
        assert windows[0]["active"] is True


# ===========================================================================
# check_auth() — tested via a mock HTTP handler instance
# ===========================================================================

def _make_handler(auth_header=None, token=""):
    """
    Build a minimal AgentAPIHandler-like object with a fake headers dict
    and a mock wfile/send_error_json, without starting a real server.
    """
    handler = api_server.AgentAPIHandler.__new__(api_server.AgentAPIHandler)
    handler.headers = {}
    if auth_header is not None:
        handler.headers["Authorization"] = auth_header
    handler.send_error_json = MagicMock()
    # Patch the module-level AUTH_TOKEN
    return handler


class TestCheckAuth:
    def test_no_auth_token_configured_always_passes(self):
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = ""
            handler = _make_handler(auth_header=None)
            result = handler.check_auth()
            assert result is True
            handler.send_error_json.assert_not_called()
        finally:
            api_server.AUTH_TOKEN = original

    def test_valid_bearer_token_passes(self):
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = "secret123"
            handler = _make_handler(auth_header="Bearer secret123")
            result = handler.check_auth()
            assert result is True
            handler.send_error_json.assert_not_called()
        finally:
            api_server.AUTH_TOKEN = original

    def test_wrong_bearer_token_returns_401(self):
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = "secret123"
            handler = _make_handler(auth_header="Bearer wrongtoken")
            result = handler.check_auth()
            assert result is False
            handler.send_error_json.assert_called_once_with(401, mock.ANY)
        finally:
            api_server.AUTH_TOKEN = original

    def test_missing_auth_header_returns_401(self):
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = "secret123"
            handler = _make_handler(auth_header=None)
            result = handler.check_auth()
            assert result is False
            handler.send_error_json.assert_called_once_with(401, mock.ANY)
        finally:
            api_server.AUTH_TOKEN = original

    def test_malformed_token_scheme_returns_401(self):
        """'Token xxx' scheme (not Bearer) must fail."""
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = "secret123"
            handler = _make_handler(auth_header="Token secret123")
            result = handler.check_auth()
            assert result is False
            handler.send_error_json.assert_called_once_with(401, mock.ANY)
        finally:
            api_server.AUTH_TOKEN = original

    def test_basic_scheme_returns_401(self):
        original = api_server.AUTH_TOKEN
        try:
            api_server.AUTH_TOKEN = "secret123"
            handler = _make_handler(auth_header="Basic dXNlcjpwYXNz")
            result = handler.check_auth()
            assert result is False
        finally:
            api_server.AUTH_TOKEN = original


# ===========================================================================
# read_body()
# ===========================================================================

def _make_handler_with_body(body_bytes, content_length=None):
    handler = api_server.AgentAPIHandler.__new__(api_server.AgentAPIHandler)
    if content_length is None:
        content_length = len(body_bytes)
    handler.headers = {"Content-Length": str(content_length)}
    handler.rfile = io.BytesIO(body_bytes)
    return handler


class TestReadBody:
    def test_valid_json(self):
        payload = json.dumps({"command": "ls", "timeout": 10}).encode()
        handler = _make_handler_with_body(payload)
        result = handler.read_body()
        assert result == {"command": "ls", "timeout": 10}

    def test_empty_body_content_length_zero(self):
        handler = _make_handler_with_body(b"", content_length=0)
        result = handler.read_body()
        assert result == {}

    def test_invalid_json_returns_empty_dict(self):
        handler = _make_handler_with_body(b"this is not json")
        result = handler.read_body()
        assert result == {}

    def test_missing_content_length_defaults_to_zero(self):
        handler = api_server.AgentAPIHandler.__new__(api_server.AgentAPIHandler)
        handler.headers = {}
        handler.rfile = io.BytesIO(b'{"key": "value"}')
        result = handler.read_body()
        assert result == {}

    def test_nested_json(self):
        payload = json.dumps({"nested": {"a": 1, "b": [1, 2, 3]}}).encode()
        handler = _make_handler_with_body(payload)
        result = handler.read_body()
        assert result["nested"]["b"] == [1, 2, 3]

    def test_truncated_json_returns_empty_dict(self):
        handler = _make_handler_with_body(b'{"key": ')
        result = handler.read_body()
        assert result == {}


# ===========================================================================
# create_tmux_window() — agent command mapping
# ===========================================================================

class TestCreateTmuxWindow:
    def _run(self, agent_type, run_shell_return=None):
        """Call create_tmux_window with mocked run_shell."""
        if run_shell_return is None:
            run_shell_return = ("", "", 0)
        calls = []

        def fake_run_shell(cmd, timeout=30, as_agent=False):
            calls.append(cmd)
            return run_shell_return

        with patch.object(api_server, "run_shell", side_effect=fake_run_shell):
            success, err = api_server.create_tmux_window("testwin", agent_type)
        return success, err, calls

    def test_claude_maps_to_dangerously_skip_permissions(self):
        _, _, calls = self._run("claude")
        send_keys_cmd = calls[1]
        assert "claude --dangerously-skip-permissions" in send_keys_cmd

    def test_opencode_maps_to_opencode(self):
        _, _, calls = self._run("opencode")
        assert "opencode" in calls[1]
        assert "claude" not in calls[1]

    def test_aider_maps_to_aider(self):
        _, _, calls = self._run("aider")
        assert "aider" in calls[1]

    def test_bash_maps_to_bash(self):
        _, _, calls = self._run("bash")
        assert "bash" in calls[1]

    def test_unknown_agent_type_used_as_passthrough(self):
        _, _, calls = self._run("my-custom-agent")
        assert "my-custom-agent" in calls[1]

    def test_returns_false_when_new_window_fails(self):
        with patch.object(api_server, "run_shell", return_value=("", "session not found", 1)):
            success, err = api_server.create_tmux_window("win", "bash")
        assert success is False
        assert "session not found" in err

    def test_returns_true_on_success(self):
        with patch.object(api_server, "run_shell", return_value=("", "", 0)):
            success, err = api_server.create_tmux_window("win", "claude")
        assert success is True


# ===========================================================================
# Route-level tests using a minimal fake HTTP request
# ===========================================================================

def _make_full_handler(path, method="GET", body=b"", headers=None,
                       auth_token="", agent_type="claude", agent_id="test-agent"):
    """
    Construct an AgentAPIHandler with enough state to call do_GET / do_POST /
    do_DELETE without a real socket.
    """
    handler = api_server.AgentAPIHandler.__new__(api_server.AgentAPIHandler)
    handler.path = path
    handler.command = method
    handler.headers = headers or {}
    if body:
        handler.headers["Content-Length"] = str(len(body))
    handler.rfile = io.BytesIO(body)

    # Capture the JSON response
    handler._response_status = None
    handler._response_body = None

    def fake_send_json(status, data):
        handler._response_status = status
        handler._response_body = data

    def fake_send_error_json(status, message):
        handler._response_status = status
        handler._response_body = {"error": message}

    handler.send_json = fake_send_json
    handler.send_error_json = fake_send_error_json

    # Patch module-level globals
    api_server.AUTH_TOKEN = auth_token
    api_server.AGENT_TYPE = agent_type
    api_server.AGENT_ID = agent_id

    return handler


class TestRouteHealth:
    def test_get_health_returns_200(self):
        handler = _make_full_handler("/health")
        with patch.object(api_server, "tmux_session_exists", return_value=True):
            handler.do_GET()
        assert handler._response_status == 200

    def test_get_health_returns_agent_type_and_id(self):
        handler = _make_full_handler("/health", agent_type="opencode", agent_id="box42")
        with patch.object(api_server, "tmux_session_exists", return_value=True):
            handler.do_GET()
        assert handler._response_body["agent_type"] == "opencode"
        assert handler._response_body["agent_id"] == "box42"

    def test_get_health_no_auth_required(self):
        """Health endpoint must respond 200 even when AUTH_TOKEN is set and no token provided."""
        handler = _make_full_handler("/health", auth_token="secret")
        with patch.object(api_server, "tmux_session_exists", return_value=False):
            handler.do_GET()
        assert handler._response_status == 200

    def test_get_health_degraded_when_tmux_down(self):
        handler = _make_full_handler("/health")
        with patch.object(api_server, "tmux_session_exists", return_value=False):
            handler.do_GET()
        assert handler._response_body["status"] == "degraded"
        assert handler._response_body["tmux_session"] is False

    def test_get_health_healthy_when_tmux_up(self):
        handler = _make_full_handler("/health")
        with patch.object(api_server, "tmux_session_exists", return_value=True):
            handler.do_GET()
        assert handler._response_body["status"] == "healthy"
        assert handler._response_body["tmux_session"] is True


class TestRouteReady:
    def test_get_ready_returns_200(self):
        handler = _make_full_handler("/ready")
        handler.do_GET()
        assert handler._response_status == 200

    def test_get_ready_body(self):
        handler = _make_full_handler("/ready")
        handler.do_GET()
        assert handler._response_body == {"ready": True}

    def test_get_ready_no_auth_required(self):
        handler = _make_full_handler("/ready", auth_token="topsecret")
        handler.do_GET()
        assert handler._response_status == 200


class TestRouteNotFound:
    def test_unknown_path_returns_404(self):
        handler = _make_full_handler("/unknown")
        handler.do_GET()
        assert handler._response_status == 404

    def test_unknown_path_with_trailing_slash(self):
        handler = _make_full_handler("/nonexistent/")
        handler.do_GET()
        assert handler._response_status == 404


class TestRouteExec:
    def _exec_handler(self, body_dict, auth_token=""):
        body = json.dumps(body_dict).encode()
        handler = _make_full_handler(
            "/exec", method="POST", body=body, auth_token=auth_token
        )
        return handler

    def test_exec_without_command_returns_400(self):
        handler = self._exec_handler({})
        handler.do_POST()
        assert handler._response_status == 400

    def test_exec_with_command_returns_200(self):
        handler = self._exec_handler({"command": "echo hello"})
        with patch.object(api_server, "run_shell", return_value=("hello", "", 0)):
            handler.do_POST()
        assert handler._response_status == 200

    def test_exec_response_has_stdout_stderr_return_code(self):
        handler = self._exec_handler({"command": "ls"})
        with patch.object(api_server, "run_shell", return_value=("file.txt", "", 0)):
            handler.do_POST()
        body = handler._response_body
        assert "stdout" in body
        assert "stderr" in body
        assert "return_code" in body
        assert body["stdout"] == "file.txt"
        assert body["return_code"] == 0

    def test_exec_with_nonzero_return_code(self):
        handler = self._exec_handler({"command": "false"})
        with patch.object(api_server, "run_shell", return_value=("", "error msg", 1)):
            handler.do_POST()
        assert handler._response_body["return_code"] == 1
        assert handler._response_body["stderr"] == "error msg"

    def test_exec_requires_auth_when_token_set(self):
        body = json.dumps({"command": "ls"}).encode()
        handler = _make_full_handler(
            "/exec", method="POST", body=body,
            auth_token="secret",
            headers={}  # no auth header
        )
        handler.do_POST()
        assert handler._response_status == 401

    def test_exec_with_valid_auth_passes(self):
        body = json.dumps({"command": "ls"}).encode()
        handler = _make_full_handler(
            "/exec", method="POST", body=body,
            auth_token="secret",
            headers={"Authorization": "Bearer secret"}
        )
        handler.headers["Content-Length"] = str(len(body))
        with patch.object(api_server, "run_shell", return_value=("", "", 0)):
            handler.do_POST()
        assert handler._response_status == 200


class TestRouteDeleteInstance:
    def test_delete_instance_calls_kill_tmux_window(self):
        handler = _make_full_handler("/instances/0", method="DELETE")
        with patch.object(api_server, "kill_tmux_window", return_value=(True, "")) as mock_kill:
            handler.do_DELETE()
        mock_kill.assert_called_once_with("0")

    def test_delete_instance_returns_200_on_success(self):
        handler = _make_full_handler("/instances/0", method="DELETE")
        with patch.object(api_server, "kill_tmux_window", return_value=(True, "")):
            handler.do_DELETE()
        assert handler._response_status == 200
        assert handler._response_body["deleted"] is True

    def test_delete_instance_returns_500_on_failure(self):
        handler = _make_full_handler("/instances/5", method="DELETE")
        with patch.object(api_server, "kill_tmux_window", return_value=(False, "no such window")):
            handler.do_DELETE()
        assert handler._response_status == 500

    def test_delete_requires_auth_when_token_set(self):
        handler = _make_full_handler(
            "/instances/0", method="DELETE",
            auth_token="secret", headers={}
        )
        handler.do_DELETE()
        assert handler._response_status == 401

    def test_delete_nonexistent_path_returns_404(self):
        handler = _make_full_handler("/other/0", method="DELETE")
        handler.do_DELETE()
        assert handler._response_status == 404
