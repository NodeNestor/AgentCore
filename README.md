# AgentCore

**One container. Every coding agent. Zero setup.**

AgentCore is a universal Docker container for coding agents. It ships with SSH access, a modular entrypoint, MCP tool auto-discovery, credential injection, git repo sync, an optional full desktop, and a lightweight HTTP control API. Pick your agent at runtime. Drop it into any orchestrator.

```
                             AgentCore Container
  ┌──────────────────────────────────────────────────────────────────────┐
  │                                                                      │
  │  entrypoint.sh                                                       │
  │    00-init        validate env, set defaults                         │
  │    10-ssh         OpenSSH server on :22                              │
  │    20-desktop     Xvfb + VNC + noVNC + Chrome  (optional)           │
  │    30-credentials inject secrets from /credentials mount             │
  │    40-agent-setup install / configure selected agent                 │
  │    50-mcp-tools   auto-discover + configure MCP servers              │
  │    55-plugins     clone plugin repos, symlink into agent             │
  │    60-llm-config  wire CodeGate / proxy / direct API keys            │
  │    65-repos       clone + sync git repos (background)                │
  │    70-agent-start launch agent in tmux session                       │
  │    80-api-server  control API on :8080                               │
  │    90-auto-update background agent update loop  (optional)           │
  │    99-cred-refresh re-inject credentials every 5 min                 │
  │                                                                      │
  │  Volumes                                                             │
  │    /workspace     working directory                                  │
  │    /credentials   secrets (read-only mount)                          │
  │    /agent-memory  local memory store                                 │
  │                                                                      │
  └──────────────────────────────────────────────────────────────────────┘
          │                       │                        │
   SSH :22                  noVNC :6080              Control API :8080
```

---

## Why AgentCore?

I have built eight or so agent container projects — PersistentEngineer V1 through V3, AgentCompany, CoderAgentz, AgentNetwork, MDAAS, and a few unnamed experiments. Every single one started the same way: write a Dockerfile, wire up an entrypoint script, figure out credential injection again, copy-paste the desktop setup from the last project, configure MCP tools from scratch, and add a control API because the orchestrator always needs one.

After the fourth or fifth time I found myself writing the same 60-line credential injection module, I pulled all of the best patterns out into one place. AgentCore is that place. It is not tied to any specific orchestration system. It works standalone, in Docker Compose, or as a swarm worker. You pick the agent at runtime with an environment variable, mount your credentials once, and it handles the rest.

---

## Features

### Multi-Agent Support

Select the coding agent at runtime with the `AGENT_TYPE` environment variable. No rebuild required.

| Agent | `AGENT_TYPE` | Notes |
|-------|-------------|-------|
| Claude Code | `claude` | Anthropic official CLI |
| OpenCode | `opencode` | Open-source Claude Code alternative |
| Aider | `aider` | AI pair programming in the terminal |
| All | `all` | Start all installed agents |
| None | `none` | Container only, useful for testing modules |

### Three Image Tiers

| Image | Size | Desktop | Chrome | Playwright | Use case |
|-------|------|---------|--------|------------|----------|
| `agentcore:minimal` | ~500 MB | No | No | No | CLI agents, swarm workers |
| `agentcore:ubuntu` | ~3.5 GB | Optional | Yes | Yes | Full dev environment, browser tasks |
| `agentcore:kali` | ~5 GB | Yes | Yes | Yes | Security testing, penetration research |

### Modular Entrypoint

The entrypoint is 13 numbered shell modules. Each module is independently sourceable and testable. Any module can be skipped by setting its skip flag. The sequence is deterministic: credentials are available before agent setup, agent setup completes before agent start, repos sync in the background without blocking startup.

```
modules/
  00-init.sh          validate + default all env vars
  10-ssh.sh           start OpenSSH server
  20-desktop.sh       start Xvfb + VNC + noVNC (ENABLE_DESKTOP=true)
  30-credentials.sh   inject secrets from /credentials
  40-agent-setup.sh   configure selected agent
  50-mcp-tools.sh     auto-discover and write MCP config
  55-plugins.sh       clone plugin repos, symlink into agent
  60-llm-config.sh    configure CodeGate / proxy / direct keys
  65-repos.sh         clone and sync REPOS in background
  70-agent-start.sh   launch agent in tmux session
  80-api-server.sh    start control API on :8080
  90-auto-update.sh   background agent update loop
  99-cred-refresh.sh  refresh credentials every 5 minutes
```

### MCP Tool Auto-Discovery

MCP servers are defined in `mcp-tools/library.json`. At startup, `50-mcp-tools.sh` reads the registry, gates each tool against required environment variables, and writes the final MCP configuration for the selected agent. No manual config editing required.

Custom tools can be mounted at `/opt/mcp-tools/custom/` and they will be picked up automatically.

### Control API

A lightweight HTTP API on port 8080 manages agent sessions and exposes runtime state to orchestrators. Authentication is optional via Bearer token (`API_AUTH_TOKEN`).

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Agent status and tmux session health |
| `/ready` | GET | No | Readiness check |
| `/instances` | GET | Yes | List running tmux windows |
| `/instances` | POST | Yes | Create a new agent session |
| `/instances/:id` | DELETE | Yes | Kill a tmux window by index |
| `/exec` | POST | Yes | Run a shell command, return stdout/stderr |
| `/logs` | GET | Yes | Return last N lines of tmux pane output |

### LLM Proxy Integration

`60-llm-config.sh` wires the agent to its LLM endpoint in priority order: CodeGate proxy, generic LLM proxy, then direct API keys. It handles the `apiKeyHelper` pattern for Claude Code OAuth credential files. When `CODEGATE_URL` is set, all LLM traffic routes through CodeGate for multi-account routing, failover, and guardrails.

### Git Repo Auto-Sync

Repos are defined in `REPOS` as newline-separated entries with format `url|path|branch|mode`. Two sync modes:

- `pull` -- clone and keep up to date on `REPO_SYNC_INTERVAL`
- `push` -- bidirectional sync with auto-commit and `GITHUB_TOKEN` auth

Sync runs in the background. Startup is not blocked waiting for large clones.

### Plugin Marketplace

`PLUGIN_REPOS` accepts newline-separated git URLs. At startup, each repo is cloned or updated, and any Claude Code plugins found are auto-symlinked into the agent's plugin directory. Plugins refresh on `PLUGIN_SYNC_INTERVAL`.

### Credential Management

Mount a directory to `/credentials` (read-only). The `30-credentials.sh` module reads known filenames and injects them as environment variables and config files. The `99-cred-refresh.sh` module repeats this every `CRED_REFRESH_INTERVAL` seconds so rotated tokens are picked up without restarting the container.

Supported credential files:

```
/credentials/
  anthropic_api_key       Anthropic API key
  openai_api_key          OpenAI API key
  proxy_api_key           LLM proxy auth key
  github_token            GitHub personal access token
  authorized_keys         SSH public keys
  claude/
    .credentials.json     Claude OAuth credentials
    .claude.json          Claude config
```

### Optional Desktop

Set `ENABLE_DESKTOP=true` to start Xvfb, a VNC server, and noVNC on port 6080. Chrome is pre-installed in the ubuntu and kali images and uses the virtual display automatically. Playwright tests run headlessly on the virtual display without any additional configuration.

---

## Quick Start

```bash
# Build the minimal image
docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .

# Run with Claude Code and a direct API key
docker run -d \
  -e AGENT_TYPE=claude \
  -e ANTHROPIC_API_KEY=your_key \
  -p 2222:22 -p 8080:8080 \
  agentcore:minimal

# SSH into the container
ssh agent@localhost -p 2222

# Check health
curl http://localhost:8080/health
```

Using Docker Compose:

```bash
cd examples
cp .env.example .env
# edit .env as needed
docker compose up -d
```

Multi-agent swarm with CodeGate:

```bash
cd examples
PROXY_API_KEY=your_key docker compose -f docker-compose.swarm.yml up -d
```

---

## Images

| Image | Dockerfile | Base | Size | Use case |
|-------|-----------|------|------|----------|
| `agentcore:minimal` | `Dockerfile.minimal` | Debian slim | ~500 MB | CLI agents, swarm workers |
| `agentcore:ubuntu` | `Dockerfile.ubuntu` | Ubuntu LTS | ~3.5 GB | Full desktop, browser automation |
| `agentcore:kali` | `Dockerfile.kali` | Kali Linux | ~5 GB | Security research, penetration testing |

Build all images:

```bash
docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .
docker build -f dockerfiles/Dockerfile.ubuntu  -t agentcore:ubuntu  .
docker build -f dockerfiles/Dockerfile.kali    -t agentcore:kali    .
```

---

## Environment Variables

Key variables are listed below. See [`examples/.env.example`](examples/.env.example) for the full reference with defaults and comments.

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_TYPE` | `claude` | Agent to run: `claude`, `opencode`, `aider`, `all`, `none` |
| `AGENT_ID` | `default` | Unique identifier used by orchestrators |
| `AGENT_ROLE` | -- | Role hint passed to the agent (e.g. `backend`, `reviewer`) |
| `ENABLE_DESKTOP` | `false` | Start Xvfb + VNC + noVNC + Chrome |
| `ENABLE_API` | `true` | Start control API on port 8080 |
| `ENABLE_AUTO_UPDATE` | `true` | Background agent update loop |
| `CODEGATE_URL` | -- | CodeGate proxy URL (e.g. `http://codegate:9212`) |
| `LLM_PROXY_URL` | -- | Generic LLM proxy URL |
| `PROXY_API_KEY` | -- | Auth key for the LLM proxy |
| `ANTHROPIC_API_KEY` | -- | Direct Anthropic API key |
| `OPENAI_API_KEY` | -- | Direct OpenAI API key |
| `REPOS` | -- | Repos to sync (`url\|path\|branch\|mode`, one per line) |
| `GITHUB_TOKEN` | -- | GitHub token for authenticated git operations |
| `REPO_SYNC_INTERVAL` | `300` | Repo sync interval in seconds |
| `PLUGIN_REPOS` | -- | Plugin git URLs (newline-separated) |
| `MEMORY_PROVIDER` | `local` | Memory backend: `local`, `mem0`, `qdrant` |
| `MEM0_API_KEY` | -- | Mem0 API key |
| `QDRANT_URL` | -- | Qdrant server URL |
| `SSH_PASSWORD` | `agent` | SSH password (empty to disable password auth) |
| `SSH_AUTHORIZED_KEYS` | -- | SSH public keys (newline-separated) |
| `API_AUTH_TOKEN` | -- | Bearer token for control API (disabled if unset) |
| `VNC_PASSWORD` | `agentpwd` | VNC server password |
| `VNC_RESOLUTION` | `1920x1080x24` | Virtual display resolution |
| `CRED_REFRESH_INTERVAL` | `300` | Credential refresh interval in seconds |

---

## Architecture

### Single Container

```
AgentCore
  ├── entrypoint.sh             sequential module loader
  │     ├── 00-init.sh          validate + default env vars
  │     ├── 10-ssh.sh           OpenSSH server on :22
  │     ├── 20-desktop.sh       Xvfb + VNC + noVNC (optional)
  │     ├── 30-credentials.sh   inject secrets from /credentials
  │     ├── 40-agent-setup.sh   configure selected agent
  │     ├── 50-mcp-tools.sh     write MCP config from library.json
  │     ├── 55-plugins.sh       clone + symlink plugin repos
  │     ├── 60-llm-config.sh    wire LLM proxy or direct key
  │     ├── 65-repos.sh         clone + sync REPOS (background)
  │     ├── 70-agent-start.sh   launch agent in tmux session
  │     ├── 80-api-server.sh    control API on :8080
  │     ├── 90-auto-update.sh   update loop (background)
  │     └── 99-cred-refresh.sh  re-inject credentials every 5 min
  │
  ├── /workspace                working directory (volume)
  ├── /credentials              secrets (read-only volume)
  └── /agent-memory             local memory store (volume)
```

### Multi-Agent Swarm

```
                    ┌─────────────────────────────────────────┐
                    │            CodeGate Proxy               │
                    │         (LLM routing + privacy)         │
                    │           localhost:9212                 │
                    └────────────┬──────────────┬─────────────┘
                                 │              │
               ┌─────────────────▼──┐    ┌──────▼──────────────┐
               │   agent-lead       │    │   agent-worker-N     │
               │  (ubuntu image)    │    │  (minimal image)     │
               │  + desktop         │    │  CLI only            │
               │  port 22, 6080,    │    │  port 22, 8080       │
               │       8080         │    └──────────────────────┘
               └────────┬───────────┘
                        │
               ┌────────▼──────────┐
               │      Qdrant       │
               │  (shared memory)  │
               │   port 6333       │
               └───────────────────┘
```

---

## MCP Tools

MCP servers are defined in `mcp-tools/library.json`. Tools marked `default: true` are always enabled when their required environment variables are present. Others must be explicitly enabled or will be skipped.

| Tool | Category | Default | Trigger |
|------|----------|---------|---------|
| Filesystem | development | Yes | Always |
| Playwright | testing | Yes | Always |
| Context7 | documentation | Yes | Always |
| Agent Memory | memory | Yes | Always |
| Desktop Control | system | No | `ENABLE_DESKTOP=true` |
| GitHub | development | No | `GITHUB_TOKEN` set |
| PostgreSQL | database | No | `POSTGRES_CONNECTION_STRING` set |
| SQLite | database | No | Manually enabled |
| Memory (MCP) | system | No | Manually enabled |
| Fetch | network | No | Manually enabled |
| Mem0 | memory | No | `MEM0_API_KEY` set |
| Qdrant | memory | No | `QDRANT_URL` set |

Custom tools can be mounted at `/opt/mcp-tools/custom/` and added to a local `library.json` override.

---

## Control API

The control API runs on port 8080. Authentication is via Bearer token. Set `API_AUTH_TOKEN` to require it. If unset, `/health` and `/ready` are always public; all other endpoints are unauthenticated.

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Returns agent type, ID, and tmux session status |
| `/ready` | GET | No | Readiness check |
| `/instances` | GET | Yes | List all tmux windows with name and current command |
| `/instances` | POST | Yes | Create a new tmux window and start an agent in it |
| `/instances/:id` | DELETE | Yes | Kill a tmux window by index |
| `/exec` | POST | Yes | Run a shell command, returns stdout, stderr, exit code |
| `/logs` | GET | Yes | Return last N lines of the active tmux pane |

Example:

```bash
# Health check (no auth)
curl http://localhost:8080/health

# Create a new worker instance
curl -X POST http://localhost:8080/instances \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{"name": "worker-2", "agent_type": "claude"}'

# Run a command
curl -X POST http://localhost:8080/exec \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{"command": "ls /workspace", "timeout": 10}'
```

---

## Development

```bash
# Run the entrypoint in test mode (no agent start)
AGENT_TYPE=none bash entrypoint/entrypoint.sh

# Test the control API
bash tests/test-api.sh

# Smoke test minimal image (builds + runs + checks health)
bash tests/test-minimal.sh

# Smoke test ubuntu image (includes VNC/noVNC checks)
bash tests/test-ubuntu.sh

# Run a single module in isolation
source entrypoint/lib/env.sh
source entrypoint/lib/log.sh
source entrypoint/modules/50-mcp-tools.sh
```

---

## Contributing

Contributions are welcome. Open an issue first to discuss what you would like to change.

---

## License

[MIT](LICENSE)

---

Built by [NodeNestor](https://github.com/NodeNestor).
