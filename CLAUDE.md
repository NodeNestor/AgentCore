# CLAUDE.md — AgentCore Developer Guide

## What is AgentCore?

AgentCore is a universal, reusable Docker container for coding agents. It provides a fully equipped environment that any orchestrator or swarm project can use as a building block.

`docker run agentcore` gives you a container with: coding agent (Claude Code/OpenCode/Aider), SSH, optional desktop (VNC/noVNC), MCP tools, auto-update, credential management, and a control API.

---

## Quick Commands

```bash
# Build minimal image
docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .

# Build full Ubuntu image
docker build -f dockerfiles/Dockerfile.ubuntu -t agentcore:ubuntu .

# Build Kali image
docker build -f dockerfiles/Dockerfile.kali -t agentcore:kali .

# Run with Claude Code
docker run -d -e AGENT_TYPE=claude -p 2222:22 -p 8080:8080 agentcore:minimal

# Run with desktop
docker run -d -e AGENT_TYPE=claude -e ENABLE_DESKTOP=true -p 2222:22 -p 6080:6080 -p 8080:8080 agentcore:ubuntu

# Run tests
bash tests/test-minimal.sh
bash tests/test-api.sh
```

---

## Project Structure

```
AgentCore/
├── dockerfiles/
│   ├── Dockerfile.minimal       # Debian slim: SSH + agent + API
│   ├── Dockerfile.ubuntu        # Ubuntu: + desktop (Xvfb/VNC/noVNC/Chrome)
│   └── Dockerfile.kali          # Kali Linux: + security tools
├── entrypoint/
│   ├── entrypoint.sh            # Main entry: sources modules in order
│   ├── 00-env.sh                # Environment defaults + validation
│   ├── 10-ssh.sh                # SSH server setup
│   ├── 20-credentials.sh        # Credential injection from /credentials
│   ├── 30-repos.sh              # Git repo cloning/syncing
│   ├── 40-desktop.sh            # Xvfb + VNC + noVNC (skipped if ENABLE_DESKTOP!=true)
│   ├── 50-mcp.sh                # MCP tool discovery + configuration
│   ├── 60-agent.sh              # Agent launch (selected by AGENT_TYPE)
│   ├── 70-api.sh                # Control API server start
│   └── 80-auto-update.sh        # Background updater (skipped if ENABLE_AUTO_UPDATE!=true)
├── base/
│   ├── install-claude.sh        # Claude Code installer
│   ├── install-opencode.sh      # OpenCode installer
│   ├── install-aider.sh         # Aider installer
│   └── install-common.sh        # Shared tools (git, curl, jq, etc.)
├── api/
│   └── server.sh                # Lightweight HTTP control API (bash + socat/netcat)
├── config/
│   └── mcp-library.json         # MCP tool definitions keyed by env var
├── mcp-tools/
│   ├── browser/                 # Browser MCP tool
│   ├── shell/                   # Shell MCP tool
│   └── memory/                  # Memory MCP tool
├── auto-update/
│   └── updater.sh               # Background agent version checker
├── repo-sync/
│   └── sync.sh                  # Git repo sync loop
├── plugins/
│   └── loader.sh                # Plugin repo loader
├── examples/
│   ├── .env.example             # All environment variables with docs
│   ├── docker-compose.yml       # Single agent quick start
│   └── docker-compose.swarm.yml # Multi-agent swarm with CodeGate + Qdrant
└── tests/
    ├── test-minimal.sh          # Minimal image smoke test
    ├── test-ubuntu.sh           # Ubuntu image + desktop smoke test
    └── test-api.sh              # Control API endpoint tests
```

---

## Architecture

Entrypoint is modular: `entrypoint/entrypoint.sh` sources numbered modules (00-99) in order. Each module handles one concern. Modules can be skipped based on env vars (e.g., desktop module skips if `ENABLE_DESKTOP!=true`).

```
Container startup flow:
  entrypoint.sh
    00-env.sh       → validate/default all env vars
    10-ssh.sh       → configure and start sshd
    20-credentials.sh → mount /credentials, inject keys/tokens
    30-repos.sh     → clone/sync REPOS (background loop)
    40-desktop.sh   → Xvfb + VNC + noVNC + Chrome (if ENABLE_DESKTOP=true)
    50-mcp.sh       → discover MCP tools from config/mcp-library.json
    60-agent.sh     → launch selected agent (AGENT_TYPE)
    70-api.sh       → start control API on :8080 (if ENABLE_API=true)
    80-auto-update.sh → background update loop (if ENABLE_AUTO_UPDATE=true)
```

---

## Key Design Decisions

1. **Separate Dockerfiles + shared base scripts** — not a monolithic image. Each Dockerfile installs what it needs and calls shared base scripts.
2. **Numbered module entrypoint** — not a 500-line script. Each module is independently readable, testable, and skippable.
3. **All agents pre-installed, env var selects at runtime** — images are built once; `AGENT_TYPE` decides which agent is active.
4. **/credentials as single read-only mount point** — all secrets (API keys, SSH keys, OAuth tokens) are injected via a single volume. No individual env var passing required.
5. **MCP tools auto-discovered from library.json** — tool configuration is data-driven. Adding a new MCP tool means adding an entry to `config/mcp-library.json`, not editing scripts.
6. **Control API in bash** — the lightweight HTTP API uses socat/netcat + bash. No extra runtime needed inside the container.

---

## Ports

| Port | Service | Dockerfile |
|------|---------|------------|
| 22   | SSH     | all |
| 5900 | VNC     | ubuntu, kali |
| 6080 | noVNC (web) | ubuntu, kali |
| 8080 | Control API | all |

---

## Credential Mounting

Mount a directory to `/credentials` with any of these files:

```
/credentials/
├── anthropic_api_key       # Plain text Anthropic key
├── openai_api_key          # Plain text OpenAI key
├── proxy_api_key           # Plain text proxy auth key
├── github_token            # Plain text GitHub token
├── authorized_keys         # SSH public keys (appended to ~/.ssh/authorized_keys)
└── claude/                 # Claude OAuth credential files
    ├── .credentials.json
    └── .claude.json
```

The `20-credentials.sh` module reads each file and exports the corresponding environment variable at startup.

---

## Adding a New Agent Type

1. Create `base/install-<agent>.sh` with installation logic
2. Call it in the relevant `Dockerfile`
3. Add a case branch in `entrypoint/60-agent.sh` for the new `AGENT_TYPE` value

## Adding a New MCP Tool

1. Add an entry to `config/mcp-library.json`:
   ```json
   {
     "tool_name": {
       "enable_env": "ENABLE_TOOL_NAME",
       "command": "npx -y @scope/mcp-tool",
       "args": [],
       "env": {}
     }
   }
   ```
2. The `50-mcp.sh` module will auto-discover and configure it based on the `ENABLE_TOOL_NAME` env var

## Adding a New Dockerfile

1. Copy the closest existing Dockerfile as a base
2. Install image-specific packages
3. Source `base/install-common.sh` and relevant agent installers
4. Set `ENTRYPOINT ["/entrypoint/entrypoint.sh"]`

---

## Testing

Tests are shell scripts in `tests/`. They build the image, start a container, run checks, and clean up.

```bash
# From project root
bash tests/test-minimal.sh
bash tests/test-ubuntu.sh
bash tests/test-api.sh
```

Tests check: image builds, container starts, health endpoint responds, SSH port is open, VNC/noVNC ports reachable (ubuntu), processes running inside container.
