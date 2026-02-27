#!/bin/bash
# packages-dev.sh — Optional developer toolchain installation for AgentCore containers.
# Controlled by build args: INSTALL_DOTNET, INSTALL_RUST, INSTALL_DOCKER.
# Set each to "true" to install the corresponding toolchain. Detects distro
# via /etc/os-release. Run as root.
set -e

# Read build-arg environment variables (defaulting to "false")
INSTALL_DOTNET="${INSTALL_DOTNET:-false}"
INSTALL_RUST="${INSTALL_RUST:-false}"
INSTALL_DOCKER="${INSTALL_DOCKER:-false}"

# Detect distro ID and version
. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_VERSION_ID="${VERSION_ID:-}"

echo "[packages-dev] DISTRO=${DISTRO_ID} VERSION=${DISTRO_VERSION_ID}"
echo "[packages-dev] INSTALL_DOTNET=${INSTALL_DOTNET} INSTALL_RUST=${INSTALL_RUST} INSTALL_DOCKER=${INSTALL_DOCKER}"

# ---------------------------------------------------------------------------
# .NET (supports 8, 9, 10 — defaults to 8 LTS if no version specified)
# ---------------------------------------------------------------------------
if [ "${INSTALL_DOTNET}" = "true" ]; then
    DOTNET_VERSION="${DOTNET_VERSION:-8}"
    echo "[packages-dev] Installing .NET ${DOTNET_VERSION}..."

    case "${DISTRO_ID}" in
        ubuntu)
            # Microsoft feed is available for Ubuntu
            apt-get update
            apt-get install -y --no-install-recommends wget ca-certificates

            wget -q "https://packages.microsoft.com/config/ubuntu/${DISTRO_VERSION_ID}/packages-microsoft-prod.deb" \
                -O /tmp/packages-microsoft-prod.deb
            dpkg -i /tmp/packages-microsoft-prod.deb
            rm /tmp/packages-microsoft-prod.deb

            apt-get update
            apt-get install -y --no-install-recommends \
                "dotnet-sdk-${DOTNET_VERSION}.0"
            rm -rf /var/lib/apt/lists/*
            ;;
        kali)
            # Kali: use the dotnet-install script (Microsoft feed may not have Kali packages)
            apt-get update
            apt-get install -y --no-install-recommends wget ca-certificates libicu-dev
            rm -rf /var/lib/apt/lists/*

            wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
            chmod +x /tmp/dotnet-install.sh
            /tmp/dotnet-install.sh --channel "${DOTNET_VERSION}.0" --install-dir /usr/local/dotnet
            rm /tmp/dotnet-install.sh

            ln -sf /usr/local/dotnet/dotnet /usr/local/bin/dotnet
            ;;
        *)
            echo "[packages-dev] WARNING: Unsupported distro '${DISTRO_ID}' for .NET install; skipping."
            ;;
    esac

    echo "[packages-dev] .NET installed: $(dotnet --version 2>/dev/null || echo 'not found in PATH')"
fi

# ---------------------------------------------------------------------------
# Rust toolchain (rustup, installs stable by default)
# ---------------------------------------------------------------------------
if [ "${INSTALL_RUST}" = "true" ]; then
    echo "[packages-dev] Installing Rust toolchain via rustup..."

    # Ensure curl is available
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
    rm -rf /var/lib/apt/lists/*

    # Install rustup non-interactively into /usr/local so all users can access it
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable

    # Make cargo/rustc available system-wide
    ln -sf /usr/local/cargo/bin/rustup  /usr/local/bin/rustup
    ln -sf /usr/local/cargo/bin/cargo   /usr/local/bin/cargo
    ln -sf /usr/local/cargo/bin/rustc   /usr/local/bin/rustc
    ln -sf /usr/local/cargo/bin/rust-analyzer /usr/local/bin/rust-analyzer 2>/dev/null || true

    # Persist env vars for subsequent RUN layers and login shells
    echo "export RUSTUP_HOME=/usr/local/rustup" >> /etc/environment
    echo "export CARGO_HOME=/usr/local/cargo"   >> /etc/environment
    echo "export PATH=/usr/local/cargo/bin:\$PATH" >> /etc/profile.d/rust.sh
    chmod +x /etc/profile.d/rust.sh

    echo "[packages-dev] Rust installed: $(rustc --version 2>/dev/null || echo 'not found in PATH')"
fi

# ---------------------------------------------------------------------------
# Docker CE (client + daemon — useful for DinD scenarios)
# ---------------------------------------------------------------------------
if [ "${INSTALL_DOCKER}" = "true" ]; then
    echo "[packages-dev] Installing Docker CE..."

    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg

    install -m 0755 -d /etc/apt/keyrings

    case "${DISTRO_ID}" in
        ubuntu)
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")} stable" \
                > /etc/apt/sources.list.d/docker.list
            ;;
        kali)
            curl -fsSL https://download.docker.com/linux/debian/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            # Kali is Debian-based; use the Debian feed with bookworm
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian bookworm stable" \
                > /etc/apt/sources.list.d/docker.list
            ;;
        *)
            echo "[packages-dev] WARNING: Unsupported distro '${DISTRO_ID}' for Docker CE install; skipping."
            rm -rf /var/lib/apt/lists/*
            exit 0
            ;;
    esac

    apt-get update
    apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    rm -rf /var/lib/apt/lists/*

    echo "[packages-dev] Docker installed: $(docker --version 2>/dev/null || echo 'not found in PATH')"
fi

echo "[packages-dev] Done."
