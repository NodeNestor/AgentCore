#!/bin/bash
# Module: 90-auto-update
# Start the auto-update daemon if ENABLE_AUTO_UPDATE=true.

if [ "$ENABLE_AUTO_UPDATE" != "true" ]; then
    log_info "Auto-update disabled (ENABLE_AUTO_UPDATE=$ENABLE_AUTO_UPDATE). Skipping."
    return 0
fi

UPDATER_SCRIPT=/opt/agentcore/auto-update/updater.sh

if [ ! -f "$UPDATER_SCRIPT" ]; then
    log_warn "Auto-updater script not found at $UPDATER_SCRIPT. Skipping."
    return 0
fi

log_info "Starting auto-update daemon (interval: ${AUTO_UPDATE_INTERVAL}s)..."
"$UPDATER_SCRIPT" &
UPDATE_PID=$!
log_info "Auto-update daemon started (pid $UPDATE_PID)."
