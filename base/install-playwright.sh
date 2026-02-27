#!/bin/bash
# install-playwright.sh — Install Playwright browser binaries (Chromium and Firefox)
# along with their OS-level dependencies. Requires Node.js and npx to be available
# in PATH (install-node.sh should be sourced first). Run as root.
set -e

echo "[install-playwright] Installing Playwright browsers with system dependencies..."

# Verify npx is available before proceeding
if ! command -v npx > /dev/null 2>&1; then
    echo "[install-playwright] ERROR: npx not found. Run install-node.sh first."
    exit 1
fi

npx playwright install --with-deps chromium firefox

echo "[install-playwright] Playwright browsers installed."
echo "[install-playwright] Done."
