#!/bin/bash
# Module: 30-credentials
# Copy credentials from /credentials mount into the agent home directory.

CREDS_ROOT=/credentials

if [ ! -d "$CREDS_ROOT" ]; then
    log_info "No /credentials mount found. Skipping credential copy."
    return 0
fi

log_info "Copying credentials from $CREDS_ROOT..."

# --- Claude credentials ---
CREDS_CLAUDE="$CREDS_ROOT/claude"
if [ -d "$CREDS_CLAUDE" ]; then
    log_info "Copying Claude credentials..."
    mkdir -p /home/agent/.claude

    for file in .credentials.json settings.json settings.local.json; do
        if [ -f "$CREDS_CLAUDE/$file" ]; then
            cp "$CREDS_CLAUDE/$file" /home/agent/.claude/"$file"
            log_debug "  Copied $file"
        fi
    done

    # Copy statsig directory if present
    if [ -d "$CREDS_CLAUDE/statsig" ]; then
        cp -r "$CREDS_CLAUDE/statsig" /home/agent/.claude/statsig
        log_debug "  Copied statsig/"
    fi

    chown -R agent:agent /home/agent/.claude
fi

# --- SSH credentials ---
CREDS_SSH="$CREDS_ROOT/ssh"
if [ -d "$CREDS_SSH" ]; then
    log_info "Copying SSH credentials..."
    mkdir -p /home/agent/.ssh

    cp -r "$CREDS_SSH/." /home/agent/.ssh/

    # Fix permissions: all SSH files must be 600, directory 700
    chmod 700 /home/agent/.ssh
    find /home/agent/.ssh -type f -exec chmod 600 {} \;
    chown -R agent:agent /home/agent/.ssh
    log_debug "  SSH credentials copied and permissions fixed."
fi

# --- Git credentials ---
CREDS_GIT="$CREDS_ROOT/git"
if [ -d "$CREDS_GIT" ]; then
    log_info "Copying Git credentials..."
    if [ -f "$CREDS_GIT/.gitconfig" ]; then
        cp "$CREDS_GIT/.gitconfig" /home/agent/.gitconfig
        chown agent:agent /home/agent/.gitconfig
        log_debug "  Copied .gitconfig"
    fi
fi

# --- API keys (.env files) ---
CREDS_API="$CREDS_ROOT/api-keys"
if [ -d "$CREDS_API" ]; then
    log_info "Sourcing API key .env files..."
    while IFS= read -r -d '' envfile; do
        log_debug "  Sourcing $envfile"
        # shellcheck disable=SC1090
        source "$envfile"
    done < <(find "$CREDS_API" -name "*.env" -print0)
fi

log_info "Credential copy complete."
