#!/bin/bash
# install-node.sh — Install Node.js 22.x and essential global npm packages.
# Uses NodeSource on Ubuntu; falls back to the official binary tarball on other
# distros (e.g. Kali). After Node is installed, installs global npm packages:
#   @modelcontextprotocol/server-filesystem, @playwright/mcp, tsx
# Run as root.
set -e

NODE_MAJOR="${NODE_MAJOR:-22}"

# Detect distro
. /etc/os-release
DISTRO_ID="${ID:-unknown}"

echo "[install-node] Detected distro: ${DISTRO_ID}"
echo "[install-node] Target Node.js major version: ${NODE_MAJOR}"

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------
case "${DISTRO_ID}" in
    ubuntu)
        echo "[install-node] Using NodeSource for Ubuntu..."

        apt-get update
        apt-get install -y --no-install-recommends curl ca-certificates gnupg

        # Add NodeSource signing key and repository
        curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
            | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
            > /etc/apt/sources.list.d/nodesource.list

        apt-get update
        apt-get install -y --no-install-recommends nodejs
        rm -rf /var/lib/apt/lists/*
        ;;

    *)
        echo "[install-node] Using official binary tarball (non-Ubuntu distro: ${DISTRO_ID})..."

        apt-get update
        apt-get install -y --no-install-recommends curl ca-certificates xz-utils
        rm -rf /var/lib/apt/lists/*

        ARCH="$(uname -m)"
        case "${ARCH}" in
            x86_64)  NODE_ARCH="x64"   ;;
            aarch64) NODE_ARCH="arm64" ;;
            armv7l)  NODE_ARCH="armv7l" ;;
            *)
                echo "[install-node] ERROR: Unsupported architecture: ${ARCH}"
                exit 1
                ;;
        esac

        # Resolve the latest release for the requested major version
        NODE_VERSION="$(curl -fsSL https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt \
            | head -1 \
            | grep -oP "node-v\K[0-9]+\.[0-9]+\.[0-9]+")"

        if [ -z "${NODE_VERSION}" ]; then
            echo "[install-node] ERROR: Could not resolve Node.js v${NODE_MAJOR} version."
            exit 1
        fi

        TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
        URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"

        echo "[install-node] Downloading ${URL}..."
        curl -fsSL "${URL}" -o "/tmp/${TARBALL}"
        tar -xJf "/tmp/${TARBALL}" -C /usr/local --strip-components=1
        rm "/tmp/${TARBALL}"
        ;;
esac

# Verify installation
node --version
npm --version

# ---------------------------------------------------------------------------
# Global npm packages
# ---------------------------------------------------------------------------
echo "[install-node] Installing global npm packages..."

npm install -g --no-fund --no-audit \
    @modelcontextprotocol/server-filesystem \
    "@playwright/mcp@latest" \
    tsx

echo "[install-node] Global packages installed:"
npm list -g --depth=0

echo "[install-node] Done."
