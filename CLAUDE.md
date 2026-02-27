# CLAUDE.md — AgentCore Developer Guide

## What is AgentCore?

AgentCore is a universal Docker container for coding agents. One image runs Claude Code, OpenCode, or Aider — selected at runtime via `AGENT_TYPE`. It handles SSH, credential injection, MCP tool auto-discovery, optional desktop (Xvfb/VNC/noVNC/Chrome), git repo sync, plugin loading, and a lightweight HTTP control API. Orchestrators and swarm projects use it as a building block.

**Three image tiers:**
- `Dockerfile.minimal` — CLI-only, ~500 MB (Ubuntu 24.04)
- `Dockerfile.ubuntu` — Full desktop + Chrome + Playwright, ~3.5 GB
- `Dockerfile.kali` — Kali Linux + security tools, ~5 GB

---

## Quick Commands

```bash
# Build images
docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .
docker build -f dockerfiles/Dockerfile.ubuntu  -t agentcore:ubuntu  .
docker build -f dockerfiles/Dockerfile.kali    -t agentcore:kali    .

# Run
docker run -d -e AGENT_TYPE=claude -e ANTHROPIC_API_KEY=xxx -p 2222:22 -p 8080:8080 agentcore:minimal
docker run -d -e AGENT_TYPE=claude -e ENABLE_DESKTOP=true -p 2222:22 -p 6080:6080 -p 8080:8080 agentcore:ubuntu

# SSH in
ssh agent@localhost -p 2222

# Health check
curl http://localhost:8080/health

# Docker Compose (single agent)
cd examples && cp .env.example .env && docker compose up -d

# Docker Compose (multi-agent swarm)
cd examples && docker compose -f docker-compose.swarm.yml up -d

# Run Python tests
pip install -r tests/requirements-dev.txt
pytest tests/ -v

# Run shell tests (requires bats-core)
bats tests/shell/*.bats
```

---

## Project Structure

```
AgentCore/
├── dockerfiles/
│   ├── Dockerfile.minimal          Ubuntu 24.04 CLI-only
│   ├── Dockerfile.ubuntu           Ubuntu + desktop + Chrome + Playwright
│   └── Dockerfile.kali             Kali + security tools
│
├── base/                           Build-time install scripts (COPY'd, then deleted)
│   ├── packages-core.sh            apt: git, curl, python3, tmux, openssh, sudo, jq
│   ├── packages-desktop.sh         apt: xvfb, x11vnc, novnc, openbox, xdotool
│   ├── packages-dev.sh             Optional: .NET, Rust, Docker (via build args)
│   ├── install-node.sh             Node.js 22.x + global npm packages
│   ├── install-chrome.sh           Google Chrome stable
│   ├── install-playwright.sh       Playwright chromium + firefox browsers
│   ├── create-agent-user.sh        agent:agent user (uid 1000, sudo NOPASSWD)
│   └── install-agents.sh           Claude Code + Aider + MCP Python deps
│
├── config/
│   ├── sshd_config                 SSH: PermitRootLogin no, AllowUsers agent
│   ├── openbox-rc.xml              Window manager: Chrome auto-maximize
│   └── chrome-policies.json        Chrome: disable telemetry, signin, autofill
│
├── entrypoint/
│   ├── entrypoint.sh               Main orchestrator: sources lib/ then modules/*
│   ├── lib/
│   │   ├── env.sh                  All env var defaults (: "${VAR:=default}" pattern)
│   │   └── log.sh                  log_info/warn/error/debug with [LEVEL] [module] format
│   └── modules/                    Numbered modules, sourced in order
│       ├── 00-init.sh              Directories, permissions, env validation
│       ├── 10-ssh.sh               Start sshd, configure keys/passwords
│       ├── 20-desktop.sh           Xvfb + VNC + noVNC (if ENABLE_DESKTOP=true)
│       ├── 30-credentials.sh       Copy from /credentials mount into agent home
│       ├── 40-agent-setup.sh       Claude onboarding bypass, settings.json, teams
│       ├── 50-mcp-tools.sh         Auto-discover MCP tools from library.json
│       ├── 55-plugins.sh           Clone PLUGIN_REPOS, symlink into agent
│       ├── 60-llm-config.sh        Wire CodeGate/proxy/direct API keys
│       ├── 65-repos.sh             Clone REPOS, start background sync daemon
│       ├── 70-agent-start.sh       Launch agent in tmux session (as agent user)
│       ├── 80-api-server.sh        Start control API (if ENABLE_API=true)
│       ├── 90-auto-update.sh       Start auto-update daemon (if ENABLE_AUTO_UPDATE=true)
│       └── 99-cred-refresh.sh      Background credential refresh + optional adblock
│
├── api/
│   └── server.py                   Python stdlib HTTP API on port 8080
│
├── mcp-tools/
│   ├── library.json                12-tool registry (mcpServers dict)
│   ├── desktop-control/
│   │   ├── server.py               17-tool MCP: screen, mouse, keyboard, window, clipboard
│   │   └── requirements.txt
│   └── agent-memory/
│       ├── server.py               5-tool MCP: remember, recall, forget, search, list_topics
│       └── requirements.txt
│
├── auto-update/
│   ├── updater.sh                  Main daemon loop
│   └── agents/
│       ├── claude-code.sh          Claude Code update via native installer
│       ├── opencode.sh             OpenCode update via GitHub releases
│       └── aider.sh                Aider update via pip
│
├── repo-sync/
│   └── sync.sh                     Git sync daemon (pull mode + push mode)
│
├── plugins/
│   └── .gitkeep                    Plugin mount point
│
├── examples/
│   ├── .env.example                Complete env var reference
│   ├── docker-compose.yml          Single agent quick start
│   └── docker-compose.swarm.yml    Multi-agent + CodeGate + Qdrant
│
├── tests/
│   ├── requirements-dev.txt        pytest + pytest-mock + pytest-asyncio
│   ├── conftest.py                 Shared fixtures
│   ├── test_api_server.py          52 tests: API handler, auth, routing, shell helpers
│   ├── test_agent_memory.py        32 tests: MCP memory tool operations
│   ├── test_mcp_filter.py          26 tests: MCP library filtering logic
│   ├── test_configs.py             32 tests: library.json, chrome policies, sshd config
│   ├── test_llm_config.py          28 tests: LLM settings merge logic
│   ├── test-minimal.sh             Docker smoke test (minimal image)
│   ├── test-ubuntu.sh              Docker smoke test (ubuntu image)
│   ├── test-api.sh                 Docker smoke test (API endpoints)
│   └── shell/
│       ├── run_tests.sh            bats-core runner
│       ├── test_log.bats           log.sh function tests
│       ├── test_env.bats           env.sh variable defaults
│       ├── test_repo_sync.bats     repo-sync daemon tests
│       └── test_updater.bats       auto-update daemon tests
│
├── .claude/
│   └── commands/                   Claude Code slash commands
│       ├── build.md                /build — build Docker images
│       ├── test.md                 /test — run test suites
│       ├── add-mcp-tool.md        /add-mcp-tool — add a new MCP server
│       ├── add-module.md          /add-module — add a new entrypoint module
│       ├── add-agent.md           /add-agent — add a new agent type
│       └── validate.md            /validate — validate configs and scripts
│
├── .gitattributes                  Force LF line endings for Docker
├── .gitignore
├── .dockerignore
├── CLAUDE.md                       This file
├── README.md
└── LICENSE                         MIT
```

---

## Architecture

### Startup Flow

```
entrypoint.sh runs as root:
  1. source lib/env.sh          set all env var defaults, export
  2. source lib/log.sh          load logging functions
  3. for each modules/*.sh:     source in numeric order
      00-init       → create dirs, fix permissions
      10-ssh        → start sshd on :22
      20-desktop    → [conditional] start Xvfb+VNC+noVNC
      30-credentials→ copy from /credentials mount
      40-agent-setup→ Claude onboarding bypass, settings files
      50-mcp-tools  → filter library.json → write ~/.claude/mcp.json
      55-plugins    → clone PLUGIN_REPOS, symlink plugins
      60-llm-config → write ~/.claude/settings.json with LLM endpoint
      65-repos      → clone REPOS, start sync daemon in background
      70-agent-start→ launch agent in tmux as agent user
      80-api-server → [conditional] start api/server.py on :8080
      90-auto-update→ [conditional] start updater.sh in background
      99-cred-refresh→ start credential refresh loop in background
  4. exec tail -f /dev/null     keep container alive
```

### Container Layout (runtime)

```
/opt/agentcore/
  entrypoint/      entrypoint.sh + lib/ + modules/
  api/             server.py
  auto-update/     updater.sh + agents/
  repo-sync/       sync.sh

/opt/mcp-tools/
  library.json     MCP tool registry
  desktop-control/ built-in MCP server
  agent-memory/    built-in MCP server
  custom/          mount point for user MCP tools

/home/agent/
  .claude/         settings.json, mcp.json, apiKeyHelper.sh, teams/, tasks/
  .ssh/            injected SSH keys

/workspace/
  projects/        working directory (volume mount)
  .state/          runtime state
  .agent-memory/   local memory store

/credentials/      read-only mount: claude/, ssh/, git/, api-keys/
```

---

## Key Systems

### MCP Tool Auto-Discovery (`50-mcp-tools.sh`)

The module runs a Python script that:
1. Reads `mcp-tools/library.json` — a dict of `mcpServers`
2. For each tool, checks: `requiresDesktop` (skip if desktop off), `requiredEnv` (skip if missing)
3. Includes tools that are `default: true` OR have all `requiredEnv` vars set
4. Scans `/opt/mcp-tools/custom/` for additional tools with `manifest.json`
5. Writes final config to `/home/agent/.claude/mcp.json`

**library.json format:**
```json
{
  "mcpServers": {
    "tool-name": {
      "command": "npx",
      "args": ["@scope/mcp-server"],
      "default": true,
      "requiresDesktop": false,
      "requiredEnv": ["SOME_KEY"],
      "category": "development"
    }
  }
}
```

### LLM Config Priority (`60-llm-config.sh`)

1. `CODEGATE_URL` set → proxy mode, writes `apiKeyHelper` + `ANTHROPIC_BASE_URL`
2. `LLM_PROXY_URL` set → same as above
3. `ANTHROPIC_API_KEY` set → direct mode, writes key to `settings.json`
4. Nothing set → warns, still writes `skipDangerousModePermissionPrompt`

### Credential Injection (`30-credentials.sh`)

Reads from `/credentials` mount:
- `claude/` → `.credentials.json`, `settings.json`, `settings.local.json`, `statsig/`
- `ssh/` → copied to `~/.ssh/`, permissions fixed (700/600)
- `git/` → `.gitconfig`
- `api-keys/` → sources all `*.env` files

### Control API (`api/server.py`)

Python stdlib `http.server`, port 8080. Auth via `API_AUTH_TOKEN` Bearer token.

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Agent type, ID, tmux session status |
| `/ready` | GET | No | Readiness probe |
| `/instances` | GET | Yes | List tmux windows |
| `/instances` | POST | Yes | Create tmux window + start agent |
| `/instances/:id` | DELETE | Yes | Kill tmux window |
| `/exec` | POST | Yes | Run shell command (stdout, stderr, code) |
| `/logs` | GET | Yes | Last N lines of tmux pane output |

All tmux commands run as the `agent` user via `su - agent -c`.

### Agent Start (`70-agent-start.sh`)

Creates a tmux session named `agent` as the agent user. The selected agent starts in window 0. `AGENT_TYPE=all` creates three windows (Claude, OpenCode, Aider). Sends fallback Enter keypresses after 5s to dismiss any startup prompts.

### Repo Sync (`repo-sync/sync.sh`)

`REPOS` format: `url|local_path|branch|mode` (newline-separated)
- `pull` mode: `git fetch && git reset --hard origin/branch`
- `push` mode: `git add -A && git commit && git push`
- Auth: `GITHUB_TOKEN` injected into remote URLs
- Interval: `REPO_SYNC_INTERVAL` (default 300s)

---

## Environment Variables

All defaults are in `entrypoint/lib/env.sh`. Full reference with comments in `examples/.env.example`.

### Agent
| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_TYPE` | `claude` | `claude`, `opencode`, `aider`, `all`, `none` |
| `AGENT_ID` | `default` | Unique ID for orchestrators |
| `AGENT_NAME` | `$AGENT_ID` | Human-readable name |
| `AGENT_ROLE` | _(empty)_ | Role hint (e.g. `backend`, `reviewer`) |

### Features
| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_DESKTOP` | `false` | Xvfb + VNC + noVNC + Chrome |
| `ENABLE_API` | `true` | HTTP control API on :8080 |
| `ENABLE_AUTO_UPDATE` | `true` | Background agent updater |
| `ENABLE_DIND` | `false` | Docker-in-Docker |
| `ENABLE_ADBLOCK` | `false` | StevenBlack ad-blocking hosts |

### LLM
| Variable | Default | Description |
|----------|---------|-------------|
| `CODEGATE_URL` | _(empty)_ | CodeGate proxy URL |
| `LLM_PROXY_URL` | _(empty)_ | Generic LLM proxy URL |
| `PROXY_API_KEY` | _(empty)_ | Proxy auth key |
| `ANTHROPIC_API_KEY` | _(empty)_ | Direct Anthropic key |
| `OPENAI_API_KEY` | _(empty)_ | Direct OpenAI key |

### Access
| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PASSWORD` | `agent` | SSH password (empty = disable) |
| `SSH_AUTHORIZED_KEYS` | _(empty)_ | Public keys (newline-separated) |
| `API_AUTH_TOKEN` | _(empty)_ | Bearer token for control API |
| `VNC_PASSWORD` | `agentpwd` | VNC password |
| `VNC_RESOLUTION` | `1920x1080x24` | Virtual display resolution |

### Repos + Plugins
| Variable | Default | Description |
|----------|---------|-------------|
| `REPOS` | _(empty)_ | `url\|path\|branch\|mode` per line |
| `GITHUB_TOKEN` | _(empty)_ | Git auth token |
| `REPO_SYNC_INTERVAL` | `300` | Sync interval (seconds) |
| `PLUGIN_REPOS` | _(empty)_ | Plugin git URLs (newline-separated) |
| `PLUGIN_SYNC_INTERVAL` | `3600` | Plugin sync interval (seconds) |

### Memory
| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_PROVIDER` | `local` | `local`, `mem0`, `qdrant` |
| `MEM0_API_KEY` | _(empty)_ | Enables mem0 MCP |
| `QDRANT_URL` | _(empty)_ | Enables Qdrant MCP |

---

## Common Tasks

### Add a new MCP tool

1. Add entry to `mcp-tools/library.json` under `mcpServers`
2. Set `default: true` for always-on, or `requiredEnv: ["VAR"]` for opt-in
3. The `50-mcp-tools.sh` module auto-discovers it — no script changes needed

### Add a new entrypoint module

1. Create `entrypoint/modules/NN-name.sh` (pick a number between existing ones)
2. Use `log_info`, `log_warn`, `log_error` from `lib/log.sh`
3. `$CURRENT_MODULE` is set automatically from the filename
4. Use `return 0` to skip (not `exit 0` — modules are sourced, not executed)

### Add a new agent type

1. Add install logic in `base/install-agents.sh` (or a new `base/install-<name>.sh`)
2. Add a case branch in `entrypoint/modules/40-agent-setup.sh` for config
3. Add a case branch in `entrypoint/modules/70-agent-start.sh` for launch
4. Add the agent command in `api/server.py` `create_tmux_window()` dict
5. Add an update script in `auto-update/agents/<name>.sh`

### Add a new Dockerfile variant

1. Copy closest existing Dockerfile
2. Add/remove `RUN /tmp/base/*.sh` lines for the packages needed
3. All Dockerfiles must: COPY `base/`, `config/`, `mcp-tools/`, `api/`, `auto-update/`, `repo-sync/`, `entrypoint/`
4. All must set `ENTRYPOINT ["/opt/agentcore/entrypoint/entrypoint.sh"]`

### Add an external service (memory, database, etc.)

1. Add the service to `docker-compose.yml` or `docker-compose.swarm.yml`
2. Pass the env var to the agent container (e.g. `QDRANT_URL=http://qdrant:6333`)
3. Add an MCP entry in `mcp-tools/library.json` with `"requiredEnv": ["QDRANT_URL"]`
4. The filtering module auto-enables it — no code changes needed

---

## Testing

```bash
# Python unit tests (170 tests)
pip install -r tests/requirements-dev.txt
pytest tests/ -v

# Shell unit tests (requires bats-core)
bats tests/shell/*.bats

# Docker smoke tests (build + run + verify)
bash tests/test-minimal.sh    # minimal image
bash tests/test-ubuntu.sh     # ubuntu image + desktop
bash tests/test-api.sh        # API endpoint checks
```

Test files test against real config files (`library.json`, `sshd_config`, `chrome-policies.json`) and replicate the Python logic from shell modules to test in isolation.

---

## Gotchas

- **Line endings:** Windows creates CRLF. `.gitattributes` forces LF. Dockerfiles also run `sed -i 's/\r$//'` as a safety net.
- **tmux must run as agent user:** Entrypoint runs as root, but all tmux commands use `su - agent -c`. The API server also runs tmux commands as agent.
- **Modules are sourced, not executed:** Use `return 0` to skip a module, not `exit 0` (which would kill the entrypoint).
- **MCP library.json is a dict:** `{"mcpServers": {"name": {...}}}`, not a list. The filtering script iterates `.items()`.
- **Claude onboarding bypass:** `40-agent-setup.sh` sets `hasCompletedOnboarding`, `hasCompletedAuthFlow`, and enables experimental teams. Without this, Claude Code prompts interactively on first run.
- **apiKeyHelper pattern:** When using a proxy, Claude Code reads the API key from a helper script (`apiKeyHelper.sh`) instead of an env var. This is how proxy auth works.
- **Shell quote helper:** `api/server.py` has `_shell_quote()` for safe command embedding. All user-provided strings must go through it.
