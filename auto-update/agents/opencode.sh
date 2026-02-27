#!/bin/bash
set -e

# OpenCode Auto-Update Script
#
# Checks GitHub releases API for the latest OpenCode version and downloads
# it if a newer version is available.
#
# Environment variables:
#   GITHUB_TOKEN      Optional GitHub token for higher API rate limits
#   OPENCODE_INSTALL  Install directory (default: /usr/local/bin)

INSTALL_DIR="${OPENCODE_INSTALL:-/usr/local/bin}"
GITHUB_REPO="sst/opencode"
BINARY_NAME="opencode"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [opencode-update] $*"
}

get_installed_version() {
    if command -v opencode >/dev/null 2>&1; then
        opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

get_latest_version() {
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local auth_header=""
    if [ -n "${GITHUB_TOKEN}" ]; then
        auth_header="-H 'Authorization: Bearer ${GITHUB_TOKEN}'"
    fi

    curl -fsSL ${auth_header:+${auth_header}} "${api_url}" 2>/dev/null \
        | grep '"tag_name"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 || echo ""
}

version_gt() {
    # Returns 0 (true) if $1 > $2
    [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]
}

log "Checking OpenCode version..."
INSTALLED="$(get_installed_version)"
log "Installed version: ${INSTALLED}"

log "Checking GitHub for latest release..."
LATEST="$(get_latest_version)"

if [ -z "${LATEST}" ]; then
    log "WARNING: Could not determine latest version from GitHub API. Skipping."
    exit 0
fi

log "Latest available version: ${LATEST}"

if ! version_gt "${LATEST}" "${INSTALLED}"; then
    log "OpenCode is already up to date (${INSTALLED})."
    exit 0
fi

log "New version available: ${INSTALLED} -> ${LATEST}. Installing..."

# Detect OS and architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    arm64)   ARCH="aarch64" ;;
    *)       log "WARNING: Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

# TODO: Adjust asset naming pattern to match actual OpenCode release assets
# This is a placeholder — check https://github.com/sst/opencode/releases for actual filenames
ASSET_NAME="opencode-${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${LATEST}/${ASSET_NAME}"

log "Downloading from: ${DOWNLOAD_URL}"
TMP_FILE="$(mktemp)"

if curl -fsSL -o "${TMP_FILE}" "${DOWNLOAD_URL}"; then
    chmod +x "${TMP_FILE}"
    mv "${TMP_FILE}" "${INSTALL_DIR}/${BINARY_NAME}"
    log "OpenCode updated to ${LATEST} at ${INSTALL_DIR}/${BINARY_NAME}"
else
    log "WARNING: Download failed. OpenCode was not updated."
    rm -f "${TMP_FILE}"
    exit 1
fi
