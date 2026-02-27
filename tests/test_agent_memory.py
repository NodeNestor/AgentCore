"""
Tests for the agent-memory MCP server.
(mcp-tools/agent-memory/server.py)

We test the pure-Python helper functions directly (topic_to_filename,
get_timestamp) and invoke the async call_tool() handler via asyncio.run()
so no special pytest-asyncio version is needed.
"""

import asyncio
import os
import re
import sys
import types
from unittest.mock import MagicMock

import pytest

# ---------------------------------------------------------------------------
# Stub the mcp package before importing the server so we don't need it
# installed in the test environment.
# ---------------------------------------------------------------------------

def _install_mcp_stubs():
    """Create minimal stub modules for mcp, mcp.server, etc."""
    if "mcp" in sys.modules and not isinstance(sys.modules["mcp"], types.ModuleType):
        return

    # Only install stubs if the real mcp package is not available
    try:
        import mcp  # noqa: F401 — real mcp is present, don't stub
        return
    except ImportError:
        pass

    mcp_stub = types.ModuleType("mcp")
    server_stub = types.ModuleType("mcp.server")
    stdio_stub = types.ModuleType("mcp.server.stdio")
    types_stub = types.ModuleType("mcp.types")

    # Minimal Server class
    class _Server:
        def __init__(self, name):
            self.name = name

        def list_tools(self):
            def decorator(fn):
                return fn
            return decorator

        def call_tool(self):
            def decorator(fn):
                return fn
            return decorator

        def create_initialization_options(self):
            return {}

    # Minimal Tool and TextContent
    class _Tool:
        def __init__(self, name, description, inputSchema):
            self.name = name
            self.description = description
            self.inputSchema = inputSchema

    class _TextContent:
        def __init__(self, type, text):
            self.type = type
            self.text = text

    class _CallToolResult:
        pass

    import contextlib

    @contextlib.asynccontextmanager
    async def _stdio_server():
        yield MagicMock(), MagicMock()

    server_stub.Server = _Server
    stdio_stub.stdio_server = _stdio_server
    types_stub.Tool = _Tool
    types_stub.TextContent = _TextContent
    types_stub.CallToolResult = _CallToolResult

    mcp_stub.server = server_stub
    sys.modules["mcp"] = mcp_stub
    sys.modules["mcp.server"] = server_stub
    sys.modules["mcp.server.stdio"] = stdio_stub
    sys.modules["mcp.types"] = types_stub


_install_mcp_stubs()

# ---------------------------------------------------------------------------
# Import the server module, being careful about name collision with
# api/server.py which may already be in sys.modules under the key "server".
# ---------------------------------------------------------------------------

MEMORY_SERVER_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "mcp-tools", "agent-memory")
)

# Temporarily adjust sys.path so we pick up the right server.py
_saved_path = sys.path[:]
if MEMORY_SERVER_PATH not in sys.path:
    sys.path.insert(0, MEMORY_SERVER_PATH)

# Remove any previously cached "server" module (could be api/server.py)
_saved_server_module = sys.modules.pop("server", None)

import server as memory_server  # noqa: E402

# Restore sys.path and the previous "server" entry (api tests may need it)
sys.path[:] = _saved_path
if _saved_server_module is not None:
    sys.modules["server"] = _saved_server_module


# ---------------------------------------------------------------------------
# Helper: run an async call_tool call synchronously
# ---------------------------------------------------------------------------

def _run(coro):
    return asyncio.run(coro)


def _call(tool_name, args, mem_dir):
    """Call call_tool with MEMORY_DIR set to mem_dir."""
    memory_server.MEMORY_DIR = mem_dir
    return _run(memory_server.call_tool(tool_name, args))


# ===========================================================================
# topic_to_filename()
# ===========================================================================

class TestTopicToFilename:
    """Tests use os.path.join so they are cross-platform."""

    def _filename(self, topic, mem_dir):
        old = memory_server.MEMORY_DIR
        memory_server.MEMORY_DIR = mem_dir
        path = memory_server.topic_to_filename(topic)
        memory_server.MEMORY_DIR = old
        return path

    def test_simple_topic(self, tmp_path):
        path = self._filename("notes", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "notes.md")

    def test_spaces_become_hyphens(self, tmp_path):
        path = self._filename("project notes", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "project-notes.md")

    def test_special_chars_become_underscores(self, tmp_path):
        path = self._filename("my@topic!", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "my_topic_.md")

    def test_uppercase_lowercased(self, tmp_path):
        path = self._filename("MyTopic", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "mytopic.md")

    def test_leading_trailing_spaces_stripped(self, tmp_path):
        path = self._filename("  hello  ", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "hello.md")

    def test_mixed_case_with_spaces(self, tmp_path):
        path = self._filename("  Project Notes  ", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "project-notes.md")

    def test_already_safe_topic(self, tmp_path):
        path = self._filename("task-progress", str(tmp_path))
        assert path == os.path.join(str(tmp_path), "task-progress.md")


# ===========================================================================
# get_timestamp()
# ===========================================================================

class TestGetTimestamp:
    def test_matches_utc_format(self):
        ts = memory_server.get_timestamp()
        pattern = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC$"
        assert re.match(pattern, ts), f"Timestamp '{ts}' does not match expected format"

    def test_year_is_current_ish(self):
        ts = memory_server.get_timestamp()
        year = int(ts[:4])
        assert 2020 <= year <= 2100

    def test_two_calls_close_in_time(self):
        ts1 = memory_server.get_timestamp()
        ts2 = memory_server.get_timestamp()
        assert ts1[:10] == ts2[:10]


# ===========================================================================
# call_tool("remember", ...)
# ===========================================================================

class TestCallToolRemember:
    def test_creates_file_on_first_call(self, tmp_memory_dir):
        _call("remember", {"topic": "notes", "content": "Hello"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("notes")
        assert os.path.exists(filepath)

    def test_writes_topic_header_on_first_call(self, tmp_memory_dir):
        _call("remember", {"topic": "notes", "content": "Hello"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("notes")
        with open(filepath) as f:
            content = f.read()
        assert content.startswith("# notes\n")

    def test_appends_on_second_call(self, tmp_memory_dir):
        _call("remember", {"topic": "notes", "content": "First entry"}, tmp_memory_dir)
        _call("remember", {"topic": "notes", "content": "Second entry"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("notes")
        with open(filepath) as f:
            content = f.read()
        assert "First entry" in content
        assert "Second entry" in content

    def test_no_duplicate_header_on_second_call(self, tmp_memory_dir):
        _call("remember", {"topic": "notes", "content": "A"}, tmp_memory_dir)
        _call("remember", {"topic": "notes", "content": "B"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("notes")
        with open(filepath) as f:
            content = f.read()
        assert content.count("# notes") == 1

    def test_appends_timestamp(self, tmp_memory_dir):
        _call("remember", {"topic": "ts-test", "content": "data"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("ts-test")
        with open(filepath) as f:
            content = f.read()
        assert re.search(r"## \d{4}-\d{2}-\d{2}", content)

    def test_result_text_mentions_topic(self, tmp_memory_dir):
        result = _call("remember", {"topic": "plans", "content": "Do stuff"}, tmp_memory_dir)
        assert len(result) == 1
        assert "plans" in result[0].text


# ===========================================================================
# call_tool("recall", ...)
# ===========================================================================

class TestCallToolRecall:
    def test_nonexistent_topic_returns_message(self, tmp_memory_dir):
        result = _call("recall", {"topic": "ghost"}, tmp_memory_dir)
        assert len(result) == 1
        assert "ghost" in result[0].text
        assert "No memories" in result[0].text

    def test_existing_topic_returns_content(self, tmp_memory_dir):
        _call("remember", {"topic": "ideas", "content": "Build something cool"}, tmp_memory_dir)
        result = _call("recall", {"topic": "ideas"}, tmp_memory_dir)
        assert "Build something cool" in result[0].text

    def test_empty_file_returns_message(self, tmp_memory_dir):
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("empty-topic")
        with open(filepath, "w") as f:
            f.write("   ")  # whitespace only
        result = _call("recall", {"topic": "empty-topic"}, tmp_memory_dir)
        text = result[0].text.lower()
        assert "no memories" in text or "contains no" in text


# ===========================================================================
# call_tool("forget", ...)
# ===========================================================================

class TestCallToolForget:
    def test_deletes_existing_file(self, tmp_memory_dir):
        _call("remember", {"topic": "temp", "content": "delete me"}, tmp_memory_dir)
        memory_server.MEMORY_DIR = tmp_memory_dir
        filepath = memory_server.topic_to_filename("temp")
        assert os.path.exists(filepath)
        _call("forget", {"topic": "temp"}, tmp_memory_dir)
        assert not os.path.exists(filepath)

    def test_nonexistent_topic_returns_message(self, tmp_memory_dir):
        result = _call("forget", {"topic": "nonexistent"}, tmp_memory_dir)
        text = result[0].text.lower()
        assert "no memories" in text or "nothing to delete" in text

    def test_result_text_confirms_deletion(self, tmp_memory_dir):
        _call("remember", {"topic": "todelete", "content": "bye"}, tmp_memory_dir)
        result = _call("forget", {"topic": "todelete"}, tmp_memory_dir)
        assert "todelete" in result[0].text
        assert "deleted" in result[0].text.lower()


# ===========================================================================
# call_tool("search", ...)
# ===========================================================================

class TestCallToolSearch:
    def test_finds_keyword(self, tmp_memory_dir):
        _call("remember", {"topic": "work", "content": "Fix the deploy pipeline"}, tmp_memory_dir)
        result = _call("search", {"keyword": "deploy"}, tmp_memory_dir)
        assert "deploy" in result[0].text.lower()

    def test_case_insensitive_search(self, tmp_memory_dir):
        _call("remember", {"topic": "notes", "content": "Important TODO item"}, tmp_memory_dir)
        result = _call("search", {"keyword": "todo"}, tmp_memory_dir)
        assert "TODO" in result[0].text or "todo" in result[0].text.lower()

    def test_no_matches_returns_message(self, tmp_memory_dir):
        _call("remember", {"topic": "abc", "content": "some text"}, tmp_memory_dir)
        result = _call("search", {"keyword": "xyzzy_not_found"}, tmp_memory_dir)
        text = result[0].text
        assert "No memories" in text or "xyzzy_not_found" in text

    def test_searches_multiple_files(self, tmp_memory_dir):
        _call("remember", {"topic": "file1", "content": "shared keyword here"}, tmp_memory_dir)
        _call("remember", {"topic": "file2", "content": "shared keyword there"}, tmp_memory_dir)
        result = _call("search", {"keyword": "shared keyword"}, tmp_memory_dir)
        text = result[0].text
        assert "file1" in text
        assert "file2" in text

    def test_reports_line_numbers(self, tmp_memory_dir):
        _call("remember", {"topic": "lined", "content": "find this"}, tmp_memory_dir)
        result = _call("search", {"keyword": "find this"}, tmp_memory_dir)
        assert re.search(r"Line \d+:", result[0].text)


# ===========================================================================
# call_tool("list_topics", ...)
# ===========================================================================

class TestCallToolListTopics:
    def test_empty_dir_returns_message(self, tmp_memory_dir):
        result = _call("list_topics", {}, tmp_memory_dir)
        assert "No memory topics" in result[0].text

    def test_shows_all_files(self, tmp_memory_dir):
        _call("remember", {"topic": "alpha", "content": "a"}, tmp_memory_dir)
        _call("remember", {"topic": "beta", "content": "b"}, tmp_memory_dir)
        result = _call("list_topics", {}, tmp_memory_dir)
        assert "alpha" in result[0].text
        assert "beta" in result[0].text

    def test_shows_size_and_mtime(self, tmp_memory_dir):
        _call("remember", {"topic": "sized", "content": "some content"}, tmp_memory_dir)
        result = _call("list_topics", {}, tmp_memory_dir)
        assert "bytes" in result[0].text
        assert re.search(r"\d{4}-\d{2}-\d{2}", result[0].text)

    def test_count_in_header(self, tmp_memory_dir):
        _call("remember", {"topic": "one", "content": "x"}, tmp_memory_dir)
        _call("remember", {"topic": "two", "content": "y"}, tmp_memory_dir)
        result = _call("list_topics", {}, tmp_memory_dir)
        assert "2 total" in result[0].text


# ===========================================================================
# Unknown tool
# ===========================================================================

class TestCallToolUnknown:
    def test_unknown_tool_returns_error_message(self, tmp_memory_dir):
        result = _call("nonexistent_tool", {}, tmp_memory_dir)
        assert len(result) == 1
        assert "Unknown tool" in result[0].text or "nonexistent_tool" in result[0].text
