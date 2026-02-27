# AgentCore

A universal, reusable Docker container for coding agents. Drop it into any orchestrator or swarm project as a fully equipped building block.

---

## Quick Start

```bash
# 1. Pull and run with Claude Code
docker run -d \
  -e AGENT_TYPE=claude \
  -e ANTHROPIC_API_KEY=your_key_here \
  -p 2222:22 -p 8080:8080 \
  agentcore:minimal

# 2. SSH in
ssh agent@localhost -p 2222

# 3. Check health
curl http://localhost:8080/health
```

Or use Docker Compose:

```bash
cd examples
cp .env.example .env   # edit as needed
docker compose up -d
```

---

## Features

- **Multiple agents** — Claude Code, OpenCode, Aider; select at runtime via `AGENT_TYPE`
- **SSH access** — Always-on OpenSSH server; supports password and key-based auth
- **Optional desktop** — Xvfb + VNC + noVNC + Chrome for browser automation tasks
- **MCP tools** — Auto-discovered and configured from a library; browser, shell, memory, and more
- **Credential management** — Mount `/credentials` once; all keys, tokens, and SSH keys are injected automatically
- **Repo sync** — Clone and keep repositories in sync on a configurable interval
- **Auto-update** — Background loop keeps agents on the latest version
- **Control API** — Lightweight HTTP API on port 8080 for health checks, instance management, exec, and log streaming
- **Plugin support** — Pull extra tooling from git repos at startup
- **CodeGate integration** — Native support for CodeGate proxy (`CODEGATE_URL`)
- **Multi-agent ready** — Designed to run in swarms with shared Qdrant memory and a single LLM proxy

---

## Supported Agents

| Agent | `AGENT_TYPE` value | Notes |
|-------|-------------------|-------|
| Claude Code | `claude` | Anthropic official CLI |
| OpenCode | `opencode` | Open-source Claude Code alternative |
| Aider | `aider` | AI pair programming in the terminal |
| All | `all` | Start all installed agents |
| None | `none` | Container only (useful for testing) |

---

## Images

| Image | Dockerfile | Size | Use case |
|-------|-----------|------|----------|
| `agentcore:minimal` | `Dockerfile.minimal` | Small | CLI-only agents, worker nodes |
| `agentcore:ubuntu` | `Dockerfile.ubuntu` | Medium | Full desktop, browser tasks, lead agent |
| `agentcore:kali` | `Dockerfile.kali` | Large | Security research, penetration testing |

---

## Environment Variables

See [`examples/.env.example`](examples/.env.example) for the full reference with default values and comments.

Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_TYPE` | `claude` | Agent to run: `claude`, `opencode`, `aider`, `all`, `none` |
| `AGENT_ID` | `default` | Unique identifier (used by orchestrators) |
| `ENABLE_DESKTOP` | `false` | Enable Xvfb + VNC + noVNC + Chrome |
| `ENABLE_API` | `true` | Enable control API on port 8080 |
| `CODEGATE_URL` | — | CodeGate proxy URL (e.g. `http://codegate:9212`) |
| `ANTHROPIC_API_KEY` | — | Direct Anthropic API key |
| `OPENAI_API_KEY` | — | Direct OpenAI API key |
| `REPOS` | — | Repos to clone/sync (one per line: `url\|path\|branch\|mode`) |
| `MEMORY_PROVIDER` | `local` | Memory backend: `local`, `mem0`, `qdrant` |
| `SSH_PASSWORD` | `agent` | SSH password (empty to disable) |
| `SSH_AUTHORIZED_KEYS` | — | SSH public keys |

---

## Credential Mounting

Rather than passing every secret as an environment variable, mount a directory to `/credentials`:

```bash
docker run -d \
  -v ./my-credentials:/credentials:ro \
  agentcore:minimal
```

Supported files inside the mounted directory:

```
/credentials/
├── anthropic_api_key       # Anthropic API key (plain text)
├── openai_api_key          # OpenAI API key
├── proxy_api_key           # LLM proxy auth key
├── github_token            # GitHub personal access token
├── authorized_keys         # SSH public keys
└── claude/                 # Claude OAuth credentials
    ├── .credentials.json
    └── .claude.json
```

---

## Control API (port 8080)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness check |
| `/ready` | GET | Readiness check (agent up) |
| `/instances` | GET | List running agent instances |
| `/instances` | POST | Create a new instance |
| `/exec` | POST | Run a command in the container |
| `/logs` | GET | Stream recent log lines |

---

## Architecture

```
Container (agentcore)
  ├── entrypoint.sh
  │     ├── 00-env.sh          validate + default env vars
  │     ├── 10-ssh.sh          OpenSSH server
  │     ├── 20-credentials.sh  inject secrets from /credentials
  │     ├── 30-repos.sh        clone/sync git repos (background)
  │     ├── 40-desktop.sh      Xvfb + VNC + noVNC (optional)
  │     ├── 50-mcp.sh          MCP tool configuration
  │     ├── 60-agent.sh        start selected coding agent
  │     ├── 70-api.sh          control API on :8080
  │     └── 80-auto-update.sh  background update loop (optional)
  │
  ├── /workspace               working directory (volume mount)
  ├── /credentials             secrets (read-only volume mount)
  └── /agent-memory            local memory store
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
               │  + browser         │    │  port 22, 8080       │
               │  port 22,6080,8080 │    └──────────────────────┘
               └────────┬───────────┘
                        │
               ┌────────▼──────────┐
               │      Qdrant       │
               │  (shared memory)  │
               │   port 6333       │
               └───────────────────┘
```

---

## Docker Compose Examples

### Single Agent

```bash
cd examples
docker compose up -d
```

See [`examples/docker-compose.yml`](examples/docker-compose.yml).

### Multi-Agent Swarm

```bash
cd examples
PROXY_API_KEY=your_key docker compose -f docker-compose.swarm.yml up -d
```

See [`examples/docker-compose.swarm.yml`](examples/docker-compose.swarm.yml).

---

## Building Images

```bash
# Minimal (Debian slim base)
docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .

# Ubuntu (full desktop)
docker build -f dockerfiles/Dockerfile.ubuntu -t agentcore:ubuntu .

# Kali (security tools)
docker build -f dockerfiles/Dockerfile.kali -t agentcore:kali .
```

---

## Testing

```bash
bash tests/test-minimal.sh    # build + smoke test minimal image
bash tests/test-ubuntu.sh     # build + smoke test ubuntu image (VNC/noVNC)
bash tests/test-api.sh        # test control API endpoints
```

---

## License

MIT License. Copyright 2025. See [LICENSE](LICENSE).
