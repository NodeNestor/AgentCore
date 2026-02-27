#!/bin/bash
# Module: 00-init
# Create required directories and fix permissions.

log_info "Creating required directories..."

mkdir -p \
    "${WORKSPACE_ROOT}/projects" \
    "${WORKSPACE_ROOT}/.state" \
    "${WORKSPACE_ROOT}/.agent-memory" \
    /tmp/.X11-unix \
    /var/run/sshd \
    /home/agent/.claude \
    /home/agent/.vnc \
    /home/agent/.ssh

log_info "Fixing directory permissions..."

# Workspace owned by agent user
chown -R agent:agent "${WORKSPACE_ROOT}" 2>/dev/null || true
chown -R agent:agent /home/agent 2>/dev/null || true

# SSH directory must be strict
chmod 700 /home/agent/.ssh

# X11 unix socket directory must have sticky bit set
chmod 1777 /tmp/.X11-unix

log_info "Init complete."
