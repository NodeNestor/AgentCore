#!/bin/bash
set -e

# Aider Auto-Update Script
#
# Upgrades aider-chat via pip3. Uses --break-system-packages for
# system Python environments (common in Docker/container setups).

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [aider-update] $*"
}

get_version() {
    if command -v aider >/dev/null 2>&1; then
        aider --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
    elif pip3 show aider-chat >/dev/null 2>&1; then
        pip3 show aider-chat 2>/dev/null | grep '^Version:' | awk '{print $2}' || echo "unknown"
    else
        echo "not-installed"
    fi
}

log "Checking Aider version..."
VERSION_BEFORE="$(get_version)"
log "Current version: ${VERSION_BEFORE}"

log "Running: pip3 install --upgrade --break-system-packages aider-chat"
if pip3 install --upgrade --break-system-packages aider-chat; then
    VERSION_AFTER="$(get_version)"
    log "Updated version: ${VERSION_AFTER}"
    if [ "${VERSION_BEFORE}" = "${VERSION_AFTER}" ]; then
        log "Aider is already up to date (${VERSION_AFTER})."
    else
        log "Aider updated: ${VERSION_BEFORE} -> ${VERSION_AFTER}"
    fi
else
    log "WARNING: pip3 upgrade failed with --break-system-packages. Trying without..."
    if pip3 install --upgrade aider-chat; then
        VERSION_AFTER="$(get_version)"
        log "Updated version: ${VERSION_AFTER}"
        if [ "${VERSION_BEFORE}" = "${VERSION_AFTER}" ]; then
            log "Aider is already up to date (${VERSION_AFTER})."
        else
            log "Aider updated: ${VERSION_BEFORE} -> ${VERSION_AFTER}"
        fi
    else
        log "ERROR: Aider update failed."
        exit 1
    fi
fi
