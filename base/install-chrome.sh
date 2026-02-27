#!/bin/bash
# install-chrome.sh — Install Google Chrome Stable from the official Google apt
# repository. Only supports amd64 architecture. Adds the Google signing key and
# apt source, then installs google-chrome-stable. Run as root.
set -e

ARCH="$(dpkg --print-architecture)"

if [ "${ARCH}" != "amd64" ]; then
    echo "[install-chrome] ERROR: Google Chrome is only available for amd64."
    echo "[install-chrome] Detected architecture: ${ARCH}"
    exit 1
fi

echo "[install-chrome] Installing Google Chrome Stable on amd64..."

apt-get update
apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg

# Add Google signing key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
chmod a+r /etc/apt/keyrings/google-chrome.gpg

# Add Chrome apt repository
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] \
https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list

apt-get update
apt-get install -y --no-install-recommends google-chrome-stable
rm -rf /var/lib/apt/lists/*

echo "[install-chrome] Chrome installed: $(google-chrome --version 2>/dev/null || echo 'not found in PATH')"
echo "[install-chrome] Done."
