#!/bin/bash
# packages-desktop.sh — Desktop environment packages for AgentCore containers.
# Sourced by Dockerfile.ubuntu and Dockerfile.kali when a desktop/GUI environment
# is required. Installs a minimal X11 stack with VNC and noVNC for browser access.
# Run as root.
set -e

apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    openbox \
    xdotool \
    scrot \
    xclip \
    wmctrl \
    x11-utils \
    xterm \
    websockify

rm -rf /var/lib/apt/lists/*
