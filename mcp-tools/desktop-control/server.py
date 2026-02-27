#!/usr/bin/env python3
"""
Desktop Control MCP Server for Linux

Provides full OS desktop control capabilities including:
- Screen capture (full desktop or region)
- Mouse control (move, click, drag)
- Keyboard input (type text, press keys)
- Window management (list, focus, move, resize)
- Clipboard access (read, write)
- Command execution

Uses Linux tools: xdotool, scrot, xclip, wmctrl
"""

import asyncio
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from typing import Any, Dict, List, Optional

try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import Tool, TextContent, ImageContent, CallToolResult
except ImportError:
    print("MCP library not found. Install with: pip install mcp", file=sys.stderr)
    sys.exit(1)

server = Server("desktop-control")

def run_command(cmd, capture_output=True):
    return subprocess.run(cmd, capture_output=capture_output, text=True,
        env={**os.environ, 'DISPLAY': os.environ.get('DISPLAY', ':0')})

def get_screen_size():
    result = run_command(['xdotool', 'getdisplaygeometry'])
    if result.returncode == 0:
        parts = result.stdout.strip().split()
        return int(parts[0]), int(parts[1])
    return 1920, 1080


@server.list_tools()
async def list_tools() -> List[Tool]:
    return [
        Tool(
            name="screen_capture",
            description="Capture a screenshot of the desktop or a specific region",
            inputSchema={
                "type": "object",
                "properties": {
                    "x": {"type": "integer", "description": "X coordinate of the top-left corner (optional)"},
                    "y": {"type": "integer", "description": "Y coordinate of the top-left corner (optional)"},
                    "width": {"type": "integer", "description": "Width of the capture region (optional)"},
                    "height": {"type": "integer", "description": "Height of the capture region (optional)"}
                }
            }
        ),
        Tool(
            name="mouse_move",
            description="Move the mouse cursor to a specific position",
            inputSchema={
                "type": "object",
                "properties": {
                    "x": {"type": "integer", "description": "X coordinate"},
                    "y": {"type": "integer", "description": "Y coordinate"}
                },
                "required": ["x", "y"]
            }
        ),
        Tool(
            name="mouse_click",
            description="Click the mouse at a position or at the current position",
            inputSchema={
                "type": "object",
                "properties": {
                    "x": {"type": "integer", "description": "X coordinate (optional, uses current position if omitted)"},
                    "y": {"type": "integer", "description": "Y coordinate (optional, uses current position if omitted)"},
                    "button": {"type": "string", "enum": ["left", "right", "middle"], "description": "Mouse button to click (default: left)"},
                    "double": {"type": "boolean", "description": "Double click (default: false)"}
                }
            }
        ),
        Tool(
            name="mouse_drag",
            description="Click and drag the mouse from one position to another",
            inputSchema={
                "type": "object",
                "properties": {
                    "start_x": {"type": "integer", "description": "Starting X coordinate"},
                    "start_y": {"type": "integer", "description": "Starting Y coordinate"},
                    "end_x": {"type": "integer", "description": "Ending X coordinate"},
                    "end_y": {"type": "integer", "description": "Ending Y coordinate"},
                    "button": {"type": "string", "enum": ["left", "right", "middle"], "description": "Mouse button to hold during drag (default: left)"}
                },
                "required": ["start_x", "start_y", "end_x", "end_y"]
            }
        ),
        Tool(
            name="keyboard_type",
            description="Type text using the keyboard",
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {"type": "string", "description": "Text to type"},
                    "delay": {"type": "integer", "description": "Delay between keystrokes in milliseconds (default: 12)"}
                },
                "required": ["text"]
            }
        ),
        Tool(
            name="keyboard_key",
            description="Press one or more keyboard keys (supports key combinations like ctrl+c, alt+F4)",
            inputSchema={
                "type": "object",
                "properties": {
                    "key": {"type": "string", "description": "Key or key combination to press (e.g. 'Return', 'ctrl+c', 'alt+Tab', 'super')"}
                },
                "required": ["key"]
            }
        ),
        Tool(
            name="window_list",
            description="List all open windows with their IDs, names, and positions",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="window_focus",
            description="Focus (bring to front) a window by its ID or name",
            inputSchema={
                "type": "object",
                "properties": {
                    "window_id": {"type": "string", "description": "Window ID (from window_list)"},
                    "window_name": {"type": "string", "description": "Window name (partial match, used if window_id not provided)"}
                }
            }
        ),
        Tool(
            name="window_move",
            description="Move a window to a specific position",
            inputSchema={
                "type": "object",
                "properties": {
                    "window_id": {"type": "string", "description": "Window ID (from window_list)"},
                    "x": {"type": "integer", "description": "Target X position"},
                    "y": {"type": "integer", "description": "Target Y position"}
                },
                "required": ["window_id", "x", "y"]
            }
        ),
        Tool(
            name="window_resize",
            description="Resize a window to specific dimensions",
            inputSchema={
                "type": "object",
                "properties": {
                    "window_id": {"type": "string", "description": "Window ID (from window_list)"},
                    "width": {"type": "integer", "description": "Target width in pixels"},
                    "height": {"type": "integer", "description": "Target height in pixels"}
                },
                "required": ["window_id", "width", "height"]
            }
        ),
        Tool(
            name="window_close",
            description="Close a window by its ID",
            inputSchema={
                "type": "object",
                "properties": {
                    "window_id": {"type": "string", "description": "Window ID (from window_list)"}
                },
                "required": ["window_id"]
            }
        ),
        Tool(
            name="clipboard_read",
            description="Read the current contents of the clipboard",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="clipboard_write",
            description="Write text to the clipboard",
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {"type": "string", "description": "Text to write to the clipboard"}
                },
                "required": ["text"]
            }
        ),
        Tool(
            name="run_command",
            description="Execute a shell command and return its output",
            inputSchema={
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Shell command to execute"},
                    "timeout": {"type": "integer", "description": "Timeout in seconds (default: 30)"}
                },
                "required": ["command"]
            }
        ),
        Tool(
            name="get_mouse_position",
            description="Get the current mouse cursor position",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="get_active_window",
            description="Get information about the currently focused/active window",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="scroll",
            description="Scroll the mouse wheel at a position",
            inputSchema={
                "type": "object",
                "properties": {
                    "x": {"type": "integer", "description": "X coordinate (optional, uses current position if omitted)"},
                    "y": {"type": "integer", "description": "Y coordinate (optional, uses current position if omitted)"},
                    "direction": {"type": "string", "enum": ["up", "down", "left", "right"], "description": "Scroll direction (default: down)"},
                    "amount": {"type": "integer", "description": "Number of scroll clicks (default: 3)"}
                }
            }
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: Dict[str, Any]) -> List[TextContent | ImageContent]:
    display = os.environ.get('DISPLAY', ':0')
    env = {**os.environ, 'DISPLAY': display}

    if name == "screen_capture":
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
            tmp_path = f.name
        try:
            cmd = ['scrot', tmp_path]
            x = arguments.get('x')
            y = arguments.get('y')
            width = arguments.get('width')
            height = arguments.get('height')
            if all(v is not None for v in [x, y, width, height]):
                cmd = ['scrot', '-a', f'{x},{y},{width},{height}', tmp_path]
            result = subprocess.run(cmd, capture_output=True, text=True, env=env)
            if result.returncode != 0:
                return [TextContent(type="text", text=f"Screenshot failed: {result.stderr}")]
            with open(tmp_path, 'rb') as f:
                img_data = base64.b64encode(f.read()).decode('utf-8')
            w, h = get_screen_size()
            return [
                TextContent(type="text", text=f"Screenshot captured. Screen size: {w}x{h}"),
                ImageContent(type="image", data=img_data, mimeType="image/png")
            ]
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    elif name == "mouse_move":
        x = arguments['x']
        y = arguments['y']
        result = subprocess.run(['xdotool', 'mousemove', str(x), str(y)],
            capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Mouse move failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Mouse moved to ({x}, {y})")]

    elif name == "mouse_click":
        button_map = {"left": "1", "middle": "2", "right": "3"}
        button = button_map.get(arguments.get('button', 'left'), '1')
        double = arguments.get('double', False)
        x = arguments.get('x')
        y = arguments.get('y')

        cmd = ['xdotool']
        if x is not None and y is not None:
            cmd += ['mousemove', str(x), str(y)]
        if double:
            cmd += ['click', '--repeat', '2', button]
        else:
            cmd += ['click', button]

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Mouse click failed: {result.stderr}")]
        pos = f" at ({x}, {y})" if x is not None and y is not None else ""
        click_type = "Double clicked" if double else "Clicked"
        return [TextContent(type="text", text=f"{click_type} {arguments.get('button', 'left')} button{pos}")]

    elif name == "mouse_drag":
        button_map = {"left": "1", "middle": "2", "right": "3"}
        button = button_map.get(arguments.get('button', 'left'), '1')
        start_x = arguments['start_x']
        start_y = arguments['start_y']
        end_x = arguments['end_x']
        end_y = arguments['end_y']

        cmd = ['xdotool', 'mousemove', str(start_x), str(start_y),
               'mousedown', button,
               'mousemove', str(end_x), str(end_y),
               'mouseup', button]
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Mouse drag failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Dragged from ({start_x}, {start_y}) to ({end_x}, {end_y})")]

    elif name == "keyboard_type":
        text = arguments['text']
        delay = arguments.get('delay', 12)
        result = subprocess.run(
            ['xdotool', 'type', '--clearmodifiers', '--delay', str(delay), '--', text],
            capture_output=True, text=True, env=env
        )
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Keyboard type failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Typed {len(text)} characters")]

    elif name == "keyboard_key":
        key = arguments['key']
        result = subprocess.run(['xdotool', 'key', '--clearmodifiers', key],
            capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Key press failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Pressed key: {key}")]

    elif name == "window_list":
        result = subprocess.run(['wmctrl', '-l', '-G'], capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Window list failed: {result.stderr}")]
        windows = []
        for line in result.stdout.strip().splitlines():
            parts = line.split(None, 8)
            if len(parts) >= 8:
                windows.append({
                    "id": parts[0],
                    "desktop": parts[1],
                    "x": int(parts[2]),
                    "y": int(parts[3]),
                    "width": int(parts[4]),
                    "height": int(parts[5]),
                    "host": parts[6],
                    "name": parts[7] if len(parts) > 7 else ""
                })
        return [TextContent(type="text", text=json.dumps(windows, indent=2))]

    elif name == "window_focus":
        window_id = arguments.get('window_id')
        window_name = arguments.get('window_name')

        if window_id:
            result = subprocess.run(['xdotool', 'windowfocus', '--sync', window_id],
                capture_output=True, text=True, env=env)
        elif window_name:
            result = subprocess.run(['wmctrl', '-a', window_name],
                capture_output=True, text=True, env=env)
        else:
            return [TextContent(type="text", text="Error: provide window_id or window_name")]

        if result.returncode != 0:
            return [TextContent(type="text", text=f"Window focus failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Focused window: {window_id or window_name}")]

    elif name == "window_move":
        window_id = arguments['window_id']
        x = arguments['x']
        y = arguments['y']
        result = subprocess.run(
            ['xdotool', 'windowmove', window_id, str(x), str(y)],
            capture_output=True, text=True, env=env
        )
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Window move failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Moved window {window_id} to ({x}, {y})")]

    elif name == "window_resize":
        window_id = arguments['window_id']
        width = arguments['width']
        height = arguments['height']
        result = subprocess.run(
            ['xdotool', 'windowsize', window_id, str(width), str(height)],
            capture_output=True, text=True, env=env
        )
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Window resize failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Resized window {window_id} to {width}x{height}")]

    elif name == "window_close":
        window_id = arguments['window_id']
        result = subprocess.run(['xdotool', 'windowclose', window_id],
            capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Window close failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Closed window {window_id}")]

    elif name == "clipboard_read":
        result = subprocess.run(['xclip', '-selection', 'clipboard', '-o'],
            capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Clipboard read failed: {result.stderr}")]
        return [TextContent(type="text", text=result.stdout)]

    elif name == "clipboard_write":
        text = arguments['text']
        result = subprocess.run(
            ['xclip', '-selection', 'clipboard'],
            input=text, capture_output=True, text=True, env=env
        )
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Clipboard write failed: {result.stderr}")]
        return [TextContent(type="text", text=f"Written {len(text)} characters to clipboard")]

    elif name == "run_command":
        command = arguments['command']
        timeout = arguments.get('timeout', 30)
        try:
            result = subprocess.run(
                command, shell=True, capture_output=True, text=True,
                timeout=timeout, env=env
            )
            output = []
            if result.stdout:
                output.append(f"STDOUT:\n{result.stdout}")
            if result.stderr:
                output.append(f"STDERR:\n{result.stderr}")
            output.append(f"Return code: {result.returncode}")
            return [TextContent(type="text", text="\n".join(output))]
        except subprocess.TimeoutExpired:
            return [TextContent(type="text", text=f"Command timed out after {timeout} seconds")]

    elif name == "get_mouse_position":
        result = subprocess.run(['xdotool', 'getmouselocation', '--shell'],
            capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Get mouse position failed: {result.stderr}")]
        pos = {}
        for line in result.stdout.strip().splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                pos[k.strip()] = v.strip()
        return [TextContent(type="text", text=json.dumps(pos, indent=2))]

    elif name == "get_active_window":
        wid_result = subprocess.run(['xdotool', 'getactivewindow'],
            capture_output=True, text=True, env=env)
        if wid_result.returncode != 0:
            return [TextContent(type="text", text=f"Get active window failed: {wid_result.stderr}")]
        window_id = wid_result.stdout.strip()
        name_result = subprocess.run(['xdotool', 'getwindowname', window_id],
            capture_output=True, text=True, env=env)
        geo_result = subprocess.run(['xdotool', 'getwindowgeometry', '--shell', window_id],
            capture_output=True, text=True, env=env)
        info = {"id": window_id}
        if name_result.returncode == 0:
            info["name"] = name_result.stdout.strip()
        if geo_result.returncode == 0:
            for line in geo_result.stdout.strip().splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    info[k.strip().lower()] = v.strip()
        return [TextContent(type="text", text=json.dumps(info, indent=2))]

    elif name == "scroll":
        direction_map = {"up": "4", "down": "5", "left": "6", "right": "7"}
        direction = arguments.get('direction', 'down')
        button = direction_map.get(direction, '5')
        amount = arguments.get('amount', 3)
        x = arguments.get('x')
        y = arguments.get('y')

        cmd = ['xdotool']
        if x is not None and y is not None:
            cmd += ['mousemove', str(x), str(y)]
        cmd += ['click', '--repeat', str(amount), button]

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            return [TextContent(type="text", text=f"Scroll failed: {result.stderr}")]
        pos = f" at ({x}, {y})" if x is not None and y is not None else ""
        return [TextContent(type="text", text=f"Scrolled {direction} {amount} clicks{pos}")]

    else:
        return [TextContent(type="text", text=f"Unknown tool: {name}")]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
