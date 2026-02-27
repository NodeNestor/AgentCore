#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/log.sh"

echo "=========================================="
echo "AgentCore — Starting..."
echo "Agent: $AGENT_TYPE | ID: $AGENT_ID | Desktop: $ENABLE_DESKTOP"
echo "=========================================="

for module in "$SCRIPT_DIR/modules/"*.sh; do
    CURRENT_MODULE=$(basename "$module" .sh)
    log_info "Running module: $CURRENT_MODULE"
    source "$module"
done

echo "=========================================="
echo "AgentCore ready!"
echo "  SSH:    port 22"
[ "$ENABLE_DESKTOP" = "true" ] && echo "  VNC:    port 5900" && echo "  noVNC:  port 6080"
[ "$ENABLE_API" = "true" ] && echo "  API:    port 8080"
echo "=========================================="

exec tail -f /dev/null
