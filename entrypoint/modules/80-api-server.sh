#!/bin/bash
# Module: 80-api-server
# Start the AgentCore control API server if ENABLE_API=true.

if [ "$ENABLE_API" != "true" ]; then
    log_info "API server disabled (ENABLE_API=$ENABLE_API). Skipping."
    return 0
fi

API_SCRIPT=/opt/agentcore/api/server.py

if [ ! -f "$API_SCRIPT" ]; then
    log_warn "API server script not found at $API_SCRIPT. Skipping."
    return 0
fi

log_info "Starting control API server..."
python3 "$API_SCRIPT" &
API_PID=$!
log_info "API server started (pid $API_PID) on port 8080."
