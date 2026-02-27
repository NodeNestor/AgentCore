#!/usr/bin/env python3
"""
Agent Memory MCP Server

Provides persistent markdown-based memory storage for agents.
Memories are stored as markdown files in /workspace/.agent-memory/
organized by topic.

Tools:
- remember: Store a memory under a topic
- recall: Read memories for a topic
- forget: Delete a topic's memories
- search: Search all memories for a keyword
- list_topics: List all available memory topics
"""

import asyncio
import json
import os
import sys
import glob
from datetime import datetime, timezone
from typing import Any, Dict, List

try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import Tool, TextContent, CallToolResult
except ImportError:
    print("MCP library not found. Install with: pip install mcp", file=sys.stderr)
    sys.exit(1)

MEMORY_DIR = os.environ.get("AGENT_MEMORY_DIR", "/workspace/.agent-memory")

server = Server("agent-memory")


def ensure_memory_dir():
    os.makedirs(MEMORY_DIR, exist_ok=True)


def topic_to_filename(topic: str) -> str:
    safe = "".join(c if c.isalnum() or c in ('-', '_', ' ') else '_' for c in topic)
    safe = safe.strip().replace(' ', '-').lower()
    return os.path.join(MEMORY_DIR, f"{safe}.md")


def get_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


@server.list_tools()
async def list_tools() -> List[Tool]:
    return [
        Tool(
            name="remember",
            description="Store a memory under a topic. Appends to the topic's markdown file with a timestamp.",
            inputSchema={
                "type": "object",
                "properties": {
                    "topic": {
                        "type": "string",
                        "description": "The topic/category for this memory (e.g. 'project-notes', 'user-preferences', 'task-progress')"
                    },
                    "content": {
                        "type": "string",
                        "description": "The memory content to store"
                    }
                },
                "required": ["topic", "content"]
            }
        ),
        Tool(
            name="recall",
            description="Read all stored memories for a given topic",
            inputSchema={
                "type": "object",
                "properties": {
                    "topic": {
                        "type": "string",
                        "description": "The topic to recall memories for"
                    }
                },
                "required": ["topic"]
            }
        ),
        Tool(
            name="forget",
            description="Delete all memories for a specific topic",
            inputSchema={
                "type": "object",
                "properties": {
                    "topic": {
                        "type": "string",
                        "description": "The topic whose memories should be deleted"
                    }
                },
                "required": ["topic"]
            }
        ),
        Tool(
            name="search",
            description="Search all stored memories for a keyword or phrase",
            inputSchema={
                "type": "object",
                "properties": {
                    "keyword": {
                        "type": "string",
                        "description": "The keyword or phrase to search for (case-insensitive)"
                    }
                },
                "required": ["keyword"]
            }
        ),
        Tool(
            name="list_topics",
            description="List all available memory topics",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: Dict[str, Any]) -> List[TextContent]:
    ensure_memory_dir()

    if name == "remember":
        topic = arguments["topic"]
        content = arguments["content"]
        filepath = topic_to_filename(topic)
        timestamp = get_timestamp()

        file_exists = os.path.exists(filepath)
        with open(filepath, 'a', encoding='utf-8') as f:
            if not file_exists:
                f.write(f"# {topic}\n\n")
            f.write(f"## {timestamp}\n\n")
            f.write(content.strip())
            f.write("\n\n")

        return [TextContent(
            type="text",
            text=f"Memory stored under topic '{topic}' at {timestamp}.\nFile: {filepath}"
        )]

    elif name == "recall":
        topic = arguments["topic"]
        filepath = topic_to_filename(topic)

        if not os.path.exists(filepath):
            return [TextContent(
                type="text",
                text=f"No memories found for topic '{topic}'."
            )]

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        if not content.strip():
            return [TextContent(
                type="text",
                text=f"Topic '{topic}' exists but contains no memories."
            )]

        return [TextContent(
            type="text",
            text=f"Memories for topic '{topic}':\n\n{content}"
        )]

    elif name == "forget":
        topic = arguments["topic"]
        filepath = topic_to_filename(topic)

        if not os.path.exists(filepath):
            return [TextContent(
                type="text",
                text=f"No memories found for topic '{topic}' — nothing to delete."
            )]

        os.remove(filepath)
        return [TextContent(
            type="text",
            text=f"All memories for topic '{topic}' have been deleted."
        )]

    elif name == "search":
        keyword = arguments["keyword"].lower()
        pattern = os.path.join(MEMORY_DIR, "*.md")
        matches = []

        for filepath in sorted(glob.glob(pattern)):
            topic = os.path.splitext(os.path.basename(filepath))[0]
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                matching_lines = [
                    (i + 1, line.rstrip())
                    for i, line in enumerate(lines)
                    if keyword in line.lower()
                ]
                if matching_lines:
                    matches.append({
                        "topic": topic,
                        "file": filepath,
                        "matches": [
                            {"line": lineno, "content": text}
                            for lineno, text in matching_lines
                        ]
                    })
            except (IOError, OSError):
                continue

        if not matches:
            return [TextContent(
                type="text",
                text=f"No memories found containing '{keyword}'."
            )]

        result_lines = [f"Search results for '{keyword}':\n"]
        for m in matches:
            result_lines.append(f"\n### Topic: {m['topic']}")
            for hit in m["matches"]:
                result_lines.append(f"  Line {hit['line']}: {hit['content']}")

        return [TextContent(type="text", text="\n".join(result_lines))]

    elif name == "list_topics":
        pattern = os.path.join(MEMORY_DIR, "*.md")
        files = sorted(glob.glob(pattern))

        if not files:
            return [TextContent(
                type="text",
                text=f"No memory topics found in {MEMORY_DIR}."
            )]

        topics = []
        for filepath in files:
            topic = os.path.splitext(os.path.basename(filepath))[0]
            size = os.path.getsize(filepath)
            mtime = datetime.fromtimestamp(os.path.getmtime(filepath), tz=timezone.utc)
            topics.append({
                "topic": topic,
                "file": filepath,
                "size_bytes": size,
                "last_modified": mtime.strftime("%Y-%m-%d %H:%M:%S UTC")
            })

        result_lines = [f"Available memory topics ({len(topics)} total):\n"]
        for t in topics:
            result_lines.append(
                f"  - {t['topic']}  ({t['size_bytes']} bytes, last modified {t['last_modified']})"
            )

        return [TextContent(type="text", text="\n".join(result_lines))]

    else:
        return [TextContent(type="text", text=f"Unknown tool: {name}")]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
