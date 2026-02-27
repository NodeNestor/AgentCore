#!/bin/bash
set -e

# Claude Code Auto-Update Script
#
# Claude Code's native installer handles self-updates via `claude update`.
# This script logs the version before and after to track changes.
#
# Environment variables:
#   CLAUDE_USER  System user to run the update as (default: agent)

CLAUDE_USER="${CLAUDE_USER:-agent}"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [claude-code-update] $*"
}

get_version() {
    if command -v claude >/dev/null 2>&1; then
        claude --version 2>/dev/null || echo "unknown"
    elif su - "${CLAUDE_USER}" -c "command -v claude" >/dev/null 2>&1; then
        su - "${CLAUDE_USER}" -c "claude --version" 2>/dev/null || echo "unknown"
    else
        echo "not-installed"
    fi
}

log "Checking Claude Code version..."
VERSION_BEFORE="$(get_version)"
log "Current version: ${VERSION_BEFORE}"

if [ "${VERSION_BEFORE}" = "not-installed" ]; then
    log "Claude Code not found — skipping update."
    exit 0
fi

log "Running update..."

# Try running as the configured user first, fall back to current user
if id "${CLAUDE_USER}" >/dev/null 2>&1; then
    su - "${CLAUDE_USER}" -c "claude update" || {
        log "WARNING: Update via 'su - ${CLAUDE_USER}' failed, trying directly..."
        claude update || log "WARNING: Direct update also failed."
    }
else
    log "User '${CLAUDE_USER}' not found, running update as current user..."
    claude update || log "WARNING: Update failed."
fi

VERSION_AFTER="$(get_version)"
log "Updated version: ${VERSION_AFTER}"

if [ "${VERSION_BEFORE}" = "${VERSION_AFTER}" ]; then
    log "No version change — Claude Code is already up to date."
else
    log "Claude Code updated: ${VERSION_BEFORE} -> ${VERSION_AFTER}"
fi
