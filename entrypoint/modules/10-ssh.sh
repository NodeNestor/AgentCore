#!/bin/bash
# Module: 10-ssh
# Start SSH server and configure authentication.

SSHD_CONFIG=/etc/ssh/sshd_config

log_info "Configuring SSH..."

# Write authorized keys if provided
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    log_info "Writing SSH authorized keys..."
    mkdir -p /home/agent/.ssh
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /home/agent/.ssh/authorized_keys
    chmod 600 /home/agent/.ssh/authorized_keys
    chown -R agent:agent /home/agent/.ssh
fi

# Disable password auth if no SSH_PASSWORD is set
if [ -z "$SSH_PASSWORD" ]; then
    log_info "SSH_PASSWORD is empty — disabling password authentication."
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
else
    log_debug "SSH password authentication is enabled."
    # Ensure password auth is explicitly allowed
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
fi

# Ensure PubkeyAuthentication is on
grep -q '^PubkeyAuthentication' "$SSHD_CONFIG" \
    && sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG" \
    || echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"

log_info "Starting SSH daemon..."
/usr/sbin/sshd

log_info "SSH daemon started."
