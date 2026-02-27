#!/usr/bin/env python3
"""
AgentCore Control API Server

A lightweight HTTP control plane for managing agent instances and
inspecting runtime state. Runs on port 8080.

Authentication: Bearer token via API_AUTH_TOKEN environment variable.
If API_AUTH_TOKEN is not set, authentication is disabled.

Endpoints:
  GET  /health           Public. Returns agent health and status.
  GET  /ready            Public. Returns readiness status.
  GET  /instances        List all tmux windows (agent sessions).
  POST /instances        Create a new agent session in a tmux window.
  DELETE /instances/:id  Kill a tmux window by index.
  POST /exec             Execute a shell command.
  GET  /logs             Return last N lines of tmux pane output.
"""

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs


PORT = int(os.environ.get("API_PORT", "8080"))
AUTH_TOKEN = os.environ.get("API_AUTH_TOKEN", "")
AGENT_TYPE = os.environ.get("AGENT_TYPE", "claude")
AGENT_ID = os.environ.get("AGENT_ID", os.environ.get("HOSTNAME", "unknown"))
TMUX_SESSION = os.environ.get("TMUX_SESSION", "agent")
AGENT_USER = "agent"


def run_shell(cmd, timeout=30, as_agent=False):
    """Run a shell command. If as_agent=True, run as the agent user."""
    if as_agent:
        cmd = f"su - {AGENT_USER} -c {_shell_quote(cmd)}"
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", f"Command timed out after {timeout}s", 1
    except Exception as e:
        return "", str(e), 1


def _shell_quote(s):
    """Quote a string for safe shell embedding."""
    return "'" + s.replace("'", "'\\''") + "'"


def tmux_session_exists(session_name):
    _, _, code = run_shell(f"tmux has-session -t {session_name} 2>/dev/null", as_agent=True)
    return code == 0


def list_tmux_windows():
    fmt = "#{window_index}|#{window_name}|#{pane_current_command}|#{window_active}"
    stdout, stderr, code = run_shell(
        f"tmux list-windows -t {TMUX_SESSION} -F '{fmt}'", as_agent=True
    )
    if code != 0:
        return []
    windows = []
    for line in stdout.splitlines():
        parts = line.split('|')
        if len(parts) >= 4:
            windows.append({
                "index": int(parts[0]) if parts[0].isdigit() else parts[0],
                "name": parts[1],
                "command": parts[2],
                "active": parts[3] == "1"
            })
    return windows


def get_tmux_pane_output(lines=100):
    stdout, stderr, code = run_shell(
        f"tmux capture-pane -t {TMUX_SESSION} -p -S -{lines}", as_agent=True
    )
    if code != 0:
        return stderr
    return stdout


def create_tmux_window(name, agent_type):
    agent_commands = {
        "claude": "claude --dangerously-skip-permissions",
        "opencode": "opencode",
        "aider": "aider",
        "bash": "bash"
    }
    agent_cmd = agent_commands.get(agent_type, agent_type)

    # Create window and send agent command
    _, stderr1, code1 = run_shell(
        f"tmux new-window -t {TMUX_SESSION} -n {name}", as_agent=True
    )
    if code1 != 0:
        return False, stderr1

    _, stderr2, code2 = run_shell(
        f"tmux send-keys -t {TMUX_SESSION}:{name} '{agent_cmd}' Enter", as_agent=True
    )
    return code2 == 0, stderr2


def kill_tmux_window(window_index):
    stdout, stderr, code = run_shell(
        f"tmux kill-window -t {TMUX_SESSION}:{window_index}", as_agent=True
    )
    return code == 0, stderr


class AgentAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[API] {self.address_string()} - {format % args}", file=sys.stderr)

    def send_json(self, status_code, data):
        body = json.dumps(data, indent=2).encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status_code, message):
        self.send_json(status_code, {"error": message})

    def check_auth(self):
        if not AUTH_TOKEN:
            return True
        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]
            if token == AUTH_TOKEN:
                return True
        self.send_error_json(401, "Unauthorized: valid Bearer token required")
        return False

    def read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode('utf-8'))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')
        query = parse_qs(parsed.query)

        if path == '/health':
            session_alive = tmux_session_exists(TMUX_SESSION)
            status = "healthy" if session_alive else "degraded"
            self.send_json(200, {
                "status": status,
                "agent_type": AGENT_TYPE,
                "agent_id": AGENT_ID,
                "tmux_session": session_alive
            })
            return

        if path == '/ready':
            self.send_json(200, {"ready": True})
            return

        if not self.check_auth():
            return

        if path == '/instances':
            windows = list_tmux_windows()
            self.send_json(200, {"windows": windows})
            return

        if path == '/logs':
            lines = int(query.get('lines', ['100'])[0])
            output = get_tmux_pane_output(lines)
            self.send_json(200, {"lines": lines, "output": output})
            return

        self.send_error_json(404, f"Not found: {path}")

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')

        if not self.check_auth():
            return

        body = self.read_body()

        if path == '/instances':
            name = body.get('name', 'worker')
            agent_type = body.get('agent_type', AGENT_TYPE)

            if not tmux_session_exists(TMUX_SESSION):
                self.send_error_json(503, f"tmux session '{TMUX_SESSION}' not found")
                return

            success, err = create_tmux_window(name, agent_type)
            if not success:
                self.send_error_json(500, f"Failed to create window: {err}")
                return

            windows = list_tmux_windows()
            new_window = next((w for w in windows if w['name'] == name), None)
            self.send_json(201, {
                "created": True,
                "name": name,
                "agent_type": agent_type,
                "window": new_window
            })
            return

        if path == '/exec':
            command = body.get('command')
            if not command:
                self.send_error_json(400, "Missing required field: command")
                return
            timeout = int(body.get('timeout', 30))
            stdout, stderr, code = run_shell(command, timeout=timeout)
            self.send_json(200, {
                "command": command,
                "stdout": stdout,
                "stderr": stderr,
                "return_code": code
            })
            return

        self.send_error_json(404, f"Not found: {path}")

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')

        if not self.check_auth():
            return

        parts = path.split('/')
        if len(parts) >= 3 and parts[1] == 'instances':
            window_id = parts[2]
            success, err = kill_tmux_window(window_id)
            if not success:
                self.send_error_json(500, f"Failed to kill window: {err}")
                return
            self.send_json(200, {"deleted": True, "window_id": window_id})
            return

        self.send_error_json(404, f"Not found: {path}")


def main():
    auth_status = f"enabled (token configured)" if AUTH_TOKEN else "disabled (no API_AUTH_TOKEN set)"
    print(f"[API] AgentCore Control API starting on port {PORT}", file=sys.stderr)
    print(f"[API] Auth: {auth_status}", file=sys.stderr)
    print(f"[API] Agent type: {AGENT_TYPE}, ID: {AGENT_ID}", file=sys.stderr)
    print(f"[API] tmux session: {TMUX_SESSION}", file=sys.stderr)

    httpd = HTTPServer(('0.0.0.0', PORT), AgentAPIHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[API] Shutting down.", file=sys.stderr)
        httpd.server_close()


if __name__ == "__main__":
    main()
