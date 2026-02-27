#!/bin/bash
set -e

# AgentCore Auto-Update Daemon
#
# Loops at a configurable interval and runs per-agent update scripts.
# Install agents to update by listing them in ENABLED_AGENTS (space-separated).
#
# Environment variables:
#   AUTO_UPDATE_INTERVAL  Seconds between update runs (default: 3600)
#   ENABLED_AGENTS        Space-separated list of agent names to update
#                         (default: "claude-code aider")
#   UPDATE_AGENTS_DIR     Directory containing agent update scripts
#                         (default: same directory as this script)/agents

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="${UPDATE_AGENTS_DIR:-${SCRIPT_DIR}/agents}"
INTERVAL="${AUTO_UPDATE_INTERVAL:-3600}"
ENABLED_AGENTS="${ENABLED_AGENTS:-claude-code aider}"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [auto-update] $*"
}

log "Auto-update daemon starting."
log "Update interval: ${INTERVAL}s"
log "Enabled agents: ${ENABLED_AGENTS}"
log "Agents script dir: ${AGENTS_DIR}"

if [ ! -d "${AGENTS_DIR}" ]; then
    log "ERROR: Agents directory not found: ${AGENTS_DIR}"
    exit 1
fi

run_agent_update() {
    local agent_name="$1"
    local script="${AGENTS_DIR}/${agent_name}.sh"

    if [ ! -f "${script}" ]; then
        log "WARNING: No update script found for agent '${agent_name}' (expected: ${script})"
        return 0
    fi

    if [ ! -x "${script}" ]; then
        log "WARNING: Update script for '${agent_name}' is not executable: ${script}"
        chmod +x "${script}" || true
    fi

    log "Updating agent: ${agent_name}"
    if bash "${script}"; then
        log "Update complete: ${agent_name}"
    else
        local exit_code=$?
        log "WARNING: Update script for '${agent_name}' exited with code ${exit_code}"
    fi
}

run_all_updates() {
    log "--- Starting update cycle ---"
    for agent in ${ENABLED_AGENTS}; do
        run_agent_update "${agent}"
    done
    log "--- Update cycle complete ---"
}

# Run an initial update on startup
run_all_updates

# Then loop at the configured interval
while true; do
    log "Sleeping for ${INTERVAL}s until next update cycle..."
    sleep "${INTERVAL}"
    run_all_updates
done
