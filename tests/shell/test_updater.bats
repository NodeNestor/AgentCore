#!/usr/bin/env bats
# Tests for auto-update/updater.sh
#
# Strategy: updater.sh has startup log calls (lines 25-33) and an agents-dir
# check with exit 1 before the function definitions. We source the variable
# assignments (lines 16-19) and the function definitions separately to avoid
# running the startup code.
#
# For integration tests that need the full startup path we spawn a subprocess
# with a real agents directory so the "AGENTS_DIR not found" guard passes.

UPDATER_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/auto-update/updater.sh"

# Line numbers of the two function definitions
_RUN_AGENT_LINE="$(grep -n '^run_agent_update()' "${UPDATER_SH}" | head -1 | cut -d: -f1)"
_STARTUP_LINE="$(grep -n '^# Run an initial update on startup$' "${UPDATER_SH}" | head -1 | cut -d: -f1)"
# Last line of the file
_TOTAL_LINES="$(wc -l < "${UPDATER_SH}")"

# Source variable assignments AND both function definitions without executing
# startup log calls or the agents-dir guard.
_source_functions() {
    # Variable assignments: lines 16-19
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    # Function definitions: from run_agent_update() to end of run_all_updates()
    local func_end=$(( _STARTUP_LINE - 1 ))
    eval "$(sed -n "${_RUN_AGENT_LINE},${func_end}p" "${UPDATER_SH}")"
    # Also source the log() helper (line 21-23)
    eval "$(sed -n '21,23p' "${UPDATER_SH}")"
}

setup() {
    unset AUTO_UPDATE_INTERVAL
    unset ENABLED_AGENTS
    unset UPDATE_AGENTS_DIR
    _source_functions
}

# ---------------------------------------------------------------------------
# INTERVAL default
# ---------------------------------------------------------------------------

@test "INTERVAL defaults to 3600 when AUTO_UPDATE_INTERVAL is unset" {
    unset AUTO_UPDATE_INTERVAL
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    [ "${INTERVAL}" = "3600" ]
}

@test "INTERVAL respects AUTO_UPDATE_INTERVAL when set" {
    export AUTO_UPDATE_INTERVAL=600
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    [ "${INTERVAL}" = "600" ]
}

# ---------------------------------------------------------------------------
# ENABLED_AGENTS default
# ---------------------------------------------------------------------------

@test "ENABLED_AGENTS defaults to 'claude-code aider'" {
    unset ENABLED_AGENTS
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    [ "${ENABLED_AGENTS}" = "claude-code aider" ]
}

@test "ENABLED_AGENTS is not overwritten when preset" {
    export ENABLED_AGENTS="opencode"
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    [ "${ENABLED_AGENTS}" = "opencode" ]
}

@test "ENABLED_AGENTS can hold multiple agents" {
    export ENABLED_AGENTS="aider opencode my-agent"
    eval "$(sed -n '16,19p' "${UPDATER_SH}")"
    [ "${ENABLED_AGENTS}" = "aider opencode my-agent" ]
}

# ---------------------------------------------------------------------------
# run_agent_update: missing script
# ---------------------------------------------------------------------------

@test "run_agent_update logs WARNING when agent script is missing" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"

    run run_agent_update "nonexistent-agent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"nonexistent-agent"* ]]
}

@test "run_agent_update returns 0 (not fatal) when agent script is missing" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"

    run run_agent_update "ghost-agent"
    [ "$status" -eq 0 ]
}

@test "run_agent_update mentions expected script path in warning" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"

    run run_agent_update "missing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"${AGENTS_DIR}/missing.sh"* ]]
}

# ---------------------------------------------------------------------------
# run_agent_update: non-executable script gets chmod +x
# ---------------------------------------------------------------------------

@test "run_agent_update warns about non-executable script then runs it" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    printf '#!/bin/bash\necho "ran"\n' > "${AGENTS_DIR}/testbot.sh"
    chmod -x "${AGENTS_DIR}/testbot.sh"

    # Skip on filesystems where chmod -x has no effect (e.g. tmpfs on Windows/MSYS2).
    if [ -x "${AGENTS_DIR}/testbot.sh" ]; then
        skip "Filesystem does not honour chmod -x in BATS_TEST_TMPDIR"
    fi

    run run_agent_update "testbot"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# run_agent_update: successful script
# ---------------------------------------------------------------------------

@test "run_agent_update logs 'Update complete' on success" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    printf '#!/bin/bash\nexit 0\n' > "${AGENTS_DIR}/happy.sh"
    chmod +x "${AGENTS_DIR}/happy.sh"

    run run_agent_update "happy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Update complete"* ]]
}

@test "run_agent_update logs 'Updating agent' before running the script" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    printf '#!/bin/bash\nexit 0\n' > "${AGENTS_DIR}/happy.sh"
    chmod +x "${AGENTS_DIR}/happy.sh"

    run run_agent_update "happy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating agent"* ]]
    [[ "$output" == *"happy"* ]]
}

# ---------------------------------------------------------------------------
# run_agent_update: failing script
# ---------------------------------------------------------------------------

@test "run_agent_update logs WARNING when script exits with non-zero code" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    printf '#!/bin/bash\nexit 42\n' > "${AGENTS_DIR}/failing.sh"
    chmod +x "${AGENTS_DIR}/failing.sh"

    run run_agent_update "failing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "run_agent_update returns 0 even when the agent script fails" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    printf '#!/bin/bash\nexit 1\n' > "${AGENTS_DIR}/broken.sh"
    chmod +x "${AGENTS_DIR}/broken.sh"

    run run_agent_update "broken"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# run_all_updates
# ---------------------------------------------------------------------------

@test "run_all_updates logs '--- Starting update cycle ---'" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    ENABLED_AGENTS=""

    run run_all_updates
    [ "$status" -eq 0 ]
    [[ "$output" == *"--- Starting update cycle ---"* ]]
}

@test "run_all_updates logs '--- Update cycle complete ---'" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    ENABLED_AGENTS=""

    run run_all_updates
    [ "$status" -eq 0 ]
    [[ "$output" == *"--- Update cycle complete ---"* ]]
}

@test "run_all_updates processes each agent in ENABLED_AGENTS" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    for a in alpha beta; do
        printf '#!/bin/bash\nexit 0\n' > "${AGENTS_DIR}/${a}.sh"
        chmod +x "${AGENTS_DIR}/${a}.sh"
    done
    ENABLED_AGENTS="alpha beta"

    run run_all_updates
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "run_all_updates calls run_agent_update for each agent" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents"
    mkdir -p "${AGENTS_DIR}"
    for a in x y z; do
        printf '#!/bin/bash\nexit 0\n' > "${AGENTS_DIR}/${a}.sh"
        chmod +x "${AGENTS_DIR}/${a}.sh"
    done
    ENABLED_AGENTS="x y z"

    run run_all_updates
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating agent: x"* ]]
    [[ "$output" == *"Updating agent: y"* ]]
    [[ "$output" == *"Updating agent: z"* ]]
}

# ---------------------------------------------------------------------------
# Full script: missing agents directory causes exit 1
# ---------------------------------------------------------------------------

@test "updater exits 1 when AGENTS_DIR does not exist" {
    run bash "${UPDATER_SH}" 2>&1 <<< ""
    # When UPDATE_AGENTS_DIR is not set, AGENTS_DIR defaults to the real
    # agents dir next to updater.sh. Override it to a nonexistent path.
    run env UPDATE_AGENTS_DIR=/nonexistent/path bash "${UPDATER_SH}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Agents directory not found"* ]]
}

# ---------------------------------------------------------------------------
# Full script: startup log output
# ---------------------------------------------------------------------------

@test "updater full startup logs mention the configured interval" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents_startup"
    mkdir -p "${AGENTS_DIR}"

    # Use a one-shot wrapper: mock sleep + while true so daemon exits after
    # the first run_all_updates call.
    run bash -c "
        export UPDATE_AGENTS_DIR='${AGENTS_DIR}'
        export AUTO_UPDATE_INTERVAL=4242
        export ENABLED_AGENTS='no-such-agent'

        # Intercept the infinite loop by overriding sleep to exit
        sleep() { exit 0; }
        export -f sleep

        # Source everything except set -e, then call startup sequence manually
        n=\$(grep -n '^# Run an initial update on startup\$' '${UPDATER_SH}' | head -1 | cut -d: -f1)
        source <(head -n \"\$n\" '${UPDATER_SH}' | grep -v '^set -e')
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"4242"* ]]
}

@test "updater full startup logs mention enabled agents" {
    AGENTS_DIR="${BATS_TEST_TMPDIR}/agents_startup2"
    mkdir -p "${AGENTS_DIR}"

    run bash -c "
        export UPDATE_AGENTS_DIR='${AGENTS_DIR}'
        export AUTO_UPDATE_INTERVAL=1
        export ENABLED_AGENTS='my-special-agent'

        n=\$(grep -n '^# Run an initial update on startup\$' '${UPDATER_SH}' | head -1 | cut -d: -f1)
        source <(head -n \"\$n\" '${UPDATER_SH}' | grep -v '^set -e')
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"my-special-agent"* ]]
}
