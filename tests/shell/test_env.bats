#!/usr/bin/env bats
# Tests for entrypoint/lib/env.sh
bats_require_minimum_version 1.5.0

ENV_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/entrypoint/lib/env.sh"

# Resolve the full path to bash so env -i (which strips PATH) can find it.
BASH_BIN="$(command -v bash)"

# Helper: run env.sh in a clean environment (only HOME set) and print one variable.
# Usage: _clean_source [KEY=val ...] VARNAME
#   Extra KEY=val pairs are prepended to env -i so they appear as pre-set variables.
_clean_run() {
    local varname="${@: -1}"      # last argument = variable to print
    local extra=("${@:1:$#-1}")  # all other args = extra env vars
    env -i HOME=/tmp "${extra[@]}" "${BASH_BIN}" -c \
        "source '${ENV_SH}'; printf '%s' \"\${${varname}}\""
}

# Same but spawns a grandchild to verify export
_clean_run_child() {
    local varname="${@: -1}"
    local extra=("${@:1:$#-1}")
    env -i HOME=/tmp "${extra[@]}" "${BASH_BIN}" -c \
        "source '${ENV_SH}'; ${BASH_BIN} -c 'printf \"%s\" \"\${${varname}}\"'"
}

# ---------------------------------------------------------------------------
# AGENT_TYPE
# ---------------------------------------------------------------------------

@test "AGENT_TYPE defaults to claude" {
    result="$(_clean_run AGENT_TYPE)"
    [ "$result" = "claude" ]
}

@test "AGENT_TYPE is NOT overwritten when preset" {
    result="$(_clean_run AGENT_TYPE=openai AGENT_TYPE)"
    [ "$result" = "openai" ]
}

# ---------------------------------------------------------------------------
# ENABLE_DESKTOP
# ---------------------------------------------------------------------------

@test "ENABLE_DESKTOP defaults to false" {
    result="$(_clean_run ENABLE_DESKTOP)"
    [ "$result" = "false" ]
}

@test "ENABLE_DESKTOP is NOT overwritten when preset" {
    result="$(_clean_run ENABLE_DESKTOP=true ENABLE_DESKTOP)"
    [ "$result" = "true" ]
}

# ---------------------------------------------------------------------------
# ENABLE_API
# ---------------------------------------------------------------------------

@test "ENABLE_API defaults to true" {
    result="$(_clean_run ENABLE_API)"
    [ "$result" = "true" ]
}

@test "ENABLE_API is NOT overwritten when preset" {
    result="$(_clean_run ENABLE_API=false ENABLE_API)"
    [ "$result" = "false" ]
}

# ---------------------------------------------------------------------------
# VNC_PASSWORD
# ---------------------------------------------------------------------------

@test "VNC_PASSWORD defaults to agentpwd" {
    result="$(_clean_run VNC_PASSWORD)"
    [ "$result" = "agentpwd" ]
}

@test "VNC_PASSWORD is NOT overwritten when preset" {
    result="$(_clean_run VNC_PASSWORD=mysecret VNC_PASSWORD)"
    [ "$result" = "mysecret" ]
}

# ---------------------------------------------------------------------------
# DISPLAY is always :0
# ---------------------------------------------------------------------------

@test "DISPLAY is always :0 regardless of pre-set value" {
    result="$(_clean_run DISPLAY=:99 DISPLAY)"
    [ "$result" = ":0" ]
}

@test "DISPLAY is :0 even when not pre-set" {
    result="$(_clean_run DISPLAY)"
    [ "$result" = ":0" ]
}

# ---------------------------------------------------------------------------
# HOME is always /home/agent
# ---------------------------------------------------------------------------

@test "HOME is always /home/agent regardless of pre-set value" {
    result="$(env -i HOME=/root "${BASH_BIN}" -c "source '${ENV_SH}'; printf '%s' \"\${HOME}\"")"
    [ "$result" = "/home/agent" ]
}

@test "HOME is /home/agent even when HOME was something else" {
    result="$(env -i HOME=/tmp "${BASH_BIN}" -c "source '${ENV_SH}'; printf '%s' \"\${HOME}\"")"
    [ "$result" = "/home/agent" ]
}

# ---------------------------------------------------------------------------
# LANG
# ---------------------------------------------------------------------------

@test "LANG is en_US.UTF-8" {
    result="$(_clean_run LANG)"
    [ "$result" = "en_US.UTF-8" ]
}

@test "LANG is always en_US.UTF-8 regardless of pre-set value" {
    result="$(_clean_run LANG=C LANG)"
    [ "$result" = "en_US.UTF-8" ]
}

# ---------------------------------------------------------------------------
# All variables are exported (accessible in subshell)
# ---------------------------------------------------------------------------

@test "AGENT_TYPE is exported and accessible in a child process" {
    result="$(_clean_run_child AGENT_TYPE)"
    [ "$result" = "claude" ]
}

@test "ENABLE_DESKTOP is exported and accessible in a child process" {
    result="$(_clean_run_child ENABLE_DESKTOP)"
    [ "$result" = "false" ]
}

@test "ENABLE_API is exported and accessible in a child process" {
    result="$(_clean_run_child ENABLE_API)"
    [ "$result" = "true" ]
}

@test "VNC_PASSWORD is exported and accessible in a child process" {
    result="$(_clean_run_child VNC_PASSWORD)"
    [ "$result" = "agentpwd" ]
}

@test "DISPLAY is exported and accessible in a child process" {
    result="$(_clean_run_child DISPLAY)"
    [ "$result" = ":0" ]
}

@test "HOME is exported and accessible in a child process" {
    result="$(env -i HOME=/tmp "${BASH_BIN}" -c \
        "source '${ENV_SH}'; ${BASH_BIN} -c 'printf \"%s\" \"\${HOME}\"'")"
    [ "$result" = "/home/agent" ]
}

@test "LANG is exported and accessible in a child process" {
    result="$(_clean_run_child LANG)"
    [ "$result" = "en_US.UTF-8" ]
}

# ---------------------------------------------------------------------------
# Other defaults sanity-check
# ---------------------------------------------------------------------------

@test "ENABLE_DIND defaults to false" {
    result="$(_clean_run ENABLE_DIND)"
    [ "$result" = "false" ]
}

@test "ENABLE_AUTO_UPDATE defaults to true" {
    result="$(_clean_run ENABLE_AUTO_UPDATE)"
    [ "$result" = "true" ]
}

@test "WORKSPACE_ROOT defaults to /workspace" {
    result="$(_clean_run WORKSPACE_ROOT)"
    [ "$result" = "/workspace" ]
}

@test "MEMORY_PROVIDER defaults to local" {
    result="$(_clean_run MEMORY_PROVIDER)"
    [ "$result" = "local" ]
}
