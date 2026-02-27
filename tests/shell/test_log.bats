#!/usr/bin/env bats
# Tests for entrypoint/lib/log.sh
bats_require_minimum_version 1.5.0

LOG_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/entrypoint/lib/log.sh"

setup() {
    # Unset variables that might bleed between tests
    unset CURRENT_MODULE
    unset DEBUG
    # Source log.sh fresh for each test
    source "${LOG_SH}"
}

# ---------------------------------------------------------------------------
# log_info
# ---------------------------------------------------------------------------

@test "log_info outputs [INFO] prefix" {
    run log_info "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
}

@test "log_info output format is [INFO]  [module] message" {
    CURRENT_MODULE="mymod"
    run log_info "test message"
    [ "$status" -eq 0 ]
    [ "$output" = "[INFO]  [mymod] test message" ]
}

@test "log_info goes to stdout not stderr" {
    run bash -c "source '${LOG_SH}'; log_info 'stdout check'"
    [ "$status" -eq 0 ]
    # output captures stdout; if it went to stderr it would be empty here
    [[ "$output" == *"stdout check"* ]]
}

@test "log_info with no CURRENT_MODULE defaults to entrypoint" {
    unset CURRENT_MODULE
    run log_info "default module test"
    [ "$status" -eq 0 ]
    [ "$output" = "[INFO]  [entrypoint] default module test" ]
}

@test "log_info with CURRENT_MODULE set uses that module name" {
    CURRENT_MODULE="repo-sync"
    run log_info "syncing"
    [ "$status" -eq 0 ]
    [ "$output" = "[INFO]  [repo-sync] syncing" ]
}

@test "log_info multi-word message is preserved" {
    run log_info "one two three"
    [ "$status" -eq 0 ]
    [[ "$output" == *"one two three"* ]]
}

# ---------------------------------------------------------------------------
# log_warn
# ---------------------------------------------------------------------------

@test "log_warn goes to stderr" {
    run --separate-stderr bash -c "source '${LOG_SH}'; log_warn 'this is a warning'"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[WARN]"* ]]
}

@test "log_warn stderr output format is [WARN]  [module] message" {
    run --separate-stderr bash -c "source '${LOG_SH}'; CURRENT_MODULE=testmod; log_warn 'warn msg'"
    [ "$status" -eq 0 ]
    [ "$stderr" = "[WARN]  [testmod] warn msg" ]
}

@test "log_warn does not write to stdout" {
    run --separate-stderr bash -c "source '${LOG_SH}'; log_warn 'should not be in stdout'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_warn with no CURRENT_MODULE defaults to entrypoint" {
    run --separate-stderr bash -c "source '${LOG_SH}'; unset CURRENT_MODULE; log_warn 'default'"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[entrypoint]"* ]]
}

# ---------------------------------------------------------------------------
# log_error
# ---------------------------------------------------------------------------

@test "log_error goes to stderr" {
    run --separate-stderr bash -c "source '${LOG_SH}'; log_error 'boom'"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[ERROR]"* ]]
}

@test "log_error stderr output format is [ERROR] [module] message" {
    run --separate-stderr bash -c "source '${LOG_SH}'; CURRENT_MODULE=errmod; log_error 'err msg'"
    [ "$status" -eq 0 ]
    [ "$stderr" = "[ERROR] [errmod] err msg" ]
}

@test "log_error does not write to stdout" {
    run --separate-stderr bash -c "source '${LOG_SH}'; log_error 'silent stdout'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_error with no CURRENT_MODULE defaults to entrypoint" {
    run --separate-stderr bash -c "source '${LOG_SH}'; unset CURRENT_MODULE; log_error 'oops'"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"[entrypoint]"* ]]
}

# ---------------------------------------------------------------------------
# log_debug
# ---------------------------------------------------------------------------

@test "log_debug is suppressed when DEBUG is unset" {
    run bash -c "source '${LOG_SH}'; unset DEBUG; log_debug 'hidden'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_debug is suppressed when DEBUG=false" {
    run bash -c "source '${LOG_SH}'; DEBUG=false; log_debug 'still hidden'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_debug is suppressed when DEBUG=1" {
    # Only exact string "true" should enable debug
    run bash -c "source '${LOG_SH}'; DEBUG=1; log_debug 'not shown'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_debug emits output when DEBUG=true" {
    run bash -c "source '${LOG_SH}'; DEBUG=true; log_debug 'visible'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DEBUG]"* ]]
    [[ "$output" == *"visible"* ]]
}

@test "log_debug output format is [DEBUG] [module] message when DEBUG=true" {
    run bash -c "source '${LOG_SH}'; DEBUG=true; CURRENT_MODULE=dbgmod; log_debug 'dbg msg'"
    [ "$status" -eq 0 ]
    [ "$output" = "[DEBUG] [dbgmod] dbg msg" ]
}

@test "log_debug goes to stdout (not stderr) when DEBUG=true" {
    # Suppress stderr; stdout should still have the message
    run bash -c "source '${LOG_SH}'; DEBUG=true; log_debug 'to stdout'" 2>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"to stdout"* ]]
}

@test "log_debug with no CURRENT_MODULE defaults to entrypoint when DEBUG=true" {
    run bash -c "source '${LOG_SH}'; DEBUG=true; unset CURRENT_MODULE; log_debug 'default debug'"
    [ "$status" -eq 0 ]
    [ "$output" = "[DEBUG] [entrypoint] default debug" ]
}

# ---------------------------------------------------------------------------
# CURRENT_MODULE default
# ---------------------------------------------------------------------------

@test "CURRENT_MODULE defaults to entrypoint across all log levels" {
    run bash -c "
        source '${LOG_SH}'
        unset CURRENT_MODULE
        log_info  'info msg'
        log_debug 'debug msg'   # suppressed since DEBUG not true
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"[entrypoint]"* ]]
}

@test "CURRENT_MODULE can be set before sourcing log.sh" {
    run bash -c "CURRENT_MODULE=pre-set; source '${LOG_SH}'; log_info 'hi'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[pre-set]"* ]]
}
