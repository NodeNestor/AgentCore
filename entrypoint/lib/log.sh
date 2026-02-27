#!/bin/bash
# Structured logging helper for AgentCore entrypoint modules.
# Reads $CURRENT_MODULE for the module name in log output.
# Format: [LEVEL] [module] message

log_info() {
    echo "[INFO]  [${CURRENT_MODULE:-entrypoint}] $*"
}

log_warn() {
    echo "[WARN]  [${CURRENT_MODULE:-entrypoint}] $*" >&2
}

log_error() {
    echo "[ERROR] [${CURRENT_MODULE:-entrypoint}] $*" >&2
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo "[DEBUG] [${CURRENT_MODULE:-entrypoint}] $*"
    fi
}
