#!/bin/bash
# install-agents.sh — Install AI coding agents and MCP Python dependencies.
# Installs:
#   - Claude Code   (native installer, run as 'agent' user)
#   - OpenCode      (placeholder; requires Go toolchain — see comment below)
#   - Aider         (pip3, system-wide)
#   - MCP Python libs: mcp, pydantic
# Run as root; Claude Code installation is delegated to the 'agent' user.
set -e

AGENT_USER="${AGENT_USER:-agent}"

echo "[install-agents] Installing coding agents and MCP dependencies..."

# ---------------------------------------------------------------------------
# Claude Code — native installer (must run as the agent user)
# ---------------------------------------------------------------------------
echo "[install-agents] Installing Claude Code as user '${AGENT_USER}'..."

# The installer modifies ~/.bashrc / ~/.local so it must run under the target user.
su - "${AGENT_USER}" -c \
    'curl -fsSL https://claude.ai/install.sh | bash'

echo "[install-agents] Claude Code installed."

# ---------------------------------------------------------------------------
# OpenCode — placeholder (requires Go toolchain)
# ---------------------------------------------------------------------------
# OpenCode is a Go-based coding agent. Installation options:
#
# Option A (go install — requires Go in PATH):
#   go install github.com/opencode-ai/opencode@latest
#
# Option B (binary download from GitHub releases):
#   OPENCODE_VERSION="$(curl -fsSL https://api.github.com/repos/opencode-ai/opencode/releases/latest \
#       | grep -oP '"tag_name": "\K[^"]+')"
#   curl -fsSL "https://github.com/opencode-ai/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-amd64" \
#       -o /usr/local/bin/opencode
#   chmod +x /usr/local/bin/opencode
#
# Uncomment the appropriate block once the Go toolchain is available or the
# release URL is confirmed for your target architecture.
echo "[install-agents] OpenCode: skipped (placeholder — see install-agents.sh for instructions)."

# ---------------------------------------------------------------------------
# Aider — Python-based coding agent
# ---------------------------------------------------------------------------
echo "[install-agents] Installing Aider via pip3..."

pip3 install --no-cache-dir --break-system-packages aider-chat

echo "[install-agents] Aider installed: $(aider --version 2>/dev/null || echo 'not found in PATH')"

# ---------------------------------------------------------------------------
# MCP Python dependencies
# ---------------------------------------------------------------------------
echo "[install-agents] Installing MCP Python dependencies (mcp, pydantic)..."

pip3 install --no-cache-dir --break-system-packages mcp pydantic

echo "[install-agents] MCP Python dependencies installed."

echo "[install-agents] Done."
