#!/usr/bin/env bats
# Tests for repo-sync/sync.sh
#
# Strategy: source only the function definitions (everything before "# Main")
# by reading the file up to that sentinel line. This avoids executing the
# startup log calls, setup_git_auth invocation, and the infinite loop.

SYNC_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/repo-sync/sync.sh"

# Number of lines up to (but not including) "# Main"
_FUNC_LINES="$(grep -n '^# Main$' "${SYNC_SH}" | head -1 | cut -d: -f1)"

# Source only the function definitions into the current shell.
# We skip set -e so tests can probe failure paths without aborting bats.
_source_functions() {
    local n=$(( _FUNC_LINES - 1 ))
    eval "$(head -n "${n}" "${SYNC_SH}" | grep -v '^set -e')"
}

setup() {
    unset REPOS
    unset GITHUB_TOKEN
    unset GIT_USER_NAME
    unset GIT_USER_EMAIL
    unset REPO_SYNC_INTERVAL
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    _source_functions
}

# ---------------------------------------------------------------------------
# Helper: capture stdout+stderr of a function call
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# sync_all: empty REPOS
# ---------------------------------------------------------------------------

@test "sync_all logs 'No REPOS configured' when REPOS is empty" {
    unset REPOS
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No REPOS configured"* ]]
}

@test "sync_all returns 0 when REPOS is empty" {
    unset REPOS
    run sync_all
    [ "$status" -eq 0 ]
}

@test "sync_all logs 'No REPOS configured' when REPOS is blank string" {
    REPOS=""
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"No REPOS configured"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: REPOS parsing — all 4 fields
# ---------------------------------------------------------------------------

@test "sync_all parses all 4 fields from a REPOS line" {
    # Mock sync_pull to capture what it receives
    sync_pull() {
        echo "CALLED_PULL url=$1 path=$2 branch=$3"
        return 0
    }
    export -f sync_pull

    REPOS="https://github.com/org/repo.git|/workspace/repo|develop|pull"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"url=https://github.com/org/repo.git"* ]]
    [[ "$output" == *"path=/workspace/repo"* ]]
    [[ "$output" == *"branch=develop"* ]]
}

@test "sync_all routes to sync_push when mode=push" {
    sync_push() {
        echo "CALLED_PUSH url=$1 path=$2 branch=$3"
        return 0
    }
    export -f sync_push

    REPOS="https://github.com/org/repo.git|/workspace/repo|main|push"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED_PUSH"* ]]
}

@test "sync_all routes to sync_pull when mode=pull" {
    sync_pull() {
        echo "CALLED_PULL url=$1 path=$2 branch=$3"
        return 0
    }
    export -f sync_pull

    REPOS="https://github.com/org/repo.git|/workspace/repo|main|pull"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED_PULL"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: default branch is "main" when field is empty
# ---------------------------------------------------------------------------

@test "default branch is main when branch field is empty" {
    sync_pull() {
        echo "branch_received=$3"
        return 0
    }
    export -f sync_pull

    # url|path||mode  (empty branch field)
    REPOS="https://github.com/org/repo.git|/workspace/repo||pull"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch_received=main"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: default mode is "pull" when field is empty
# ---------------------------------------------------------------------------

@test "default mode is pull when mode field is empty" {
    _pull_called=0
    sync_pull() {
        echo "PULL_CALLED"
        return 0
    }
    export -f sync_pull

    # url|path|branch|  (empty mode field)
    REPOS="https://github.com/org/repo.git|/workspace/repo|main|"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL_CALLED"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: skip comment lines
# ---------------------------------------------------------------------------

@test "comment lines (# prefix) are skipped" {
    sync_pull() {
        echo "PULL_CALLED for $1"
        return 0
    }
    export -f sync_pull

    REPOS="$(printf '# this is a comment\nhttps://github.com/org/repo.git|/workspace/repo|main|pull')"
    run sync_all
    [ "$status" -eq 0 ]
    # Comment line should not trigger a pull with "#" as the URL
    [[ "$output" != *"PULL_CALLED for #"* ]]
    # The real line should still be processed
    [[ "$output" == *"PULL_CALLED for https://github.com/org/repo.git"* ]]
}

@test "only comment lines results in no sync calls" {
    sync_pull() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
    export -f sync_pull

    REPOS="# just a comment"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: skip blank lines
# ---------------------------------------------------------------------------

@test "blank lines are skipped and do not cause errors" {
    sync_pull() {
        echo "PULL url=$1"
        return 0
    }
    export -f sync_pull

    # Two blank lines then a real entry
    REPOS="$(printf '\n\nhttps://github.com/org/repo.git|/workspace/repo|main|pull')"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL url=https://github.com/org/repo.git"* ]]
}

@test "fully-blank lines (only newlines) are skipped" {
    # Lines that are empty strings (zero length) are caught by the
    # [ -z "${url}" ] guard in sync_all and never reach sync functions.
    sync_pull() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
    export -f sync_pull

    # Two completely empty lines (no spaces)
    REPOS="$(printf '\n\n')"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: unknown mode logs warning
# ---------------------------------------------------------------------------

@test "unknown mode logs a WARNING and skips the repo" {
    sync_pull() { echo "PULL_CALLED"; return 0; }
    sync_push() { echo "PUSH_CALLED"; return 0; }
    export -f sync_pull sync_push

    REPOS="https://github.com/org/repo.git|/workspace/repo|main|rsync"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"rsync"* ]]
    [[ "$output" != *"PULL_CALLED"* ]]
    [[ "$output" != *"PUSH_CALLED"* ]]
}

@test "unknown mode does not abort remaining repos" {
    _pull_count=0
    sync_pull() {
        echo "PULL_CALLED"
        return 0
    }
    export -f sync_pull

    REPOS="$(printf 'https://github.com/a/a.git|/workspace/a|main|badmode\nhttps://github.com/b/b.git|/workspace/b|main|pull')"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PULL_CALLED"* ]]
}

# ---------------------------------------------------------------------------
# sync_all: multiple repos are all processed
# ---------------------------------------------------------------------------

@test "multiple repos are each synced" {
    sync_pull() {
        echo "PULL url=$1"
        return 0
    }
    export -f sync_pull

    REPOS="$(printf 'https://github.com/org/repo1.git|/workspace/repo1|main|pull\nhttps://github.com/org/repo2.git|/workspace/repo2|main|pull')"
    run sync_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo1"* ]]
    [[ "$output" == *"repo2"* ]]
}

# ---------------------------------------------------------------------------
# setup_git_auth: with GITHUB_TOKEN
# ---------------------------------------------------------------------------

@test "setup_git_auth with GITHUB_TOKEN writes .git-credentials" {
    # Mock git to be a no-op
    git() { return 0; }
    export -f git

    export GITHUB_TOKEN="ghp_testtoken123"
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    run setup_git_auth
    [ "$status" -eq 0 ]
    [ -f "${HOME}/.git-credentials" ]
}

@test "setup_git_auth with GITHUB_TOKEN includes token in .git-credentials" {
    git() { return 0; }
    export -f git

    export GITHUB_TOKEN="ghp_testtoken123"
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    setup_git_auth

    grep -q "ghp_testtoken123" "${HOME}/.git-credentials"
}

@test "setup_git_auth with GITHUB_TOKEN sets .git-credentials permissions to 600" {
    # Skip on filesystems that don't honour Unix permission bits (e.g. NTFS on Windows).
    local probe
    probe="$(mktemp "${BATS_TEST_TMPDIR}/permcheck.XXXXXX")"
    chmod 600 "${probe}"
    local probe_perms
    probe_perms="$(stat -c '%a' "${probe}" 2>/dev/null || echo "unknown")"
    rm -f "${probe}"
    if [ "${probe_perms}" != "600" ]; then
        skip "Filesystem does not support Unix permission bits (got ${probe_perms})"
    fi

    git() { return 0; }
    export -f git

    export GITHUB_TOKEN="ghp_testtoken123"
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    setup_git_auth

    perms="$(stat -c '%a' "${HOME}/.git-credentials")"
    [ "$perms" = "600" ]
}

@test "setup_git_auth with GITHUB_TOKEN logs credential configuration" {
    git() { return 0; }
    export -f git

    export GITHUB_TOKEN="ghp_testtoken123"
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    run setup_git_auth
    [ "$status" -eq 0 ]
    [[ "$output" == *"GITHUB_TOKEN"* ]]
}

@test "setup_git_auth writes both x-token and oauth2 credential lines" {
    git() { return 0; }
    export -f git

    export GITHUB_TOKEN="ghp_abc"
    export GIT_USER_NAME="A"
    export GIT_USER_EMAIL="a@b.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    setup_git_auth

    grep -q "x-token" "${HOME}/.git-credentials"
    grep -q "oauth2" "${HOME}/.git-credentials"
}

# ---------------------------------------------------------------------------
# setup_git_auth: without GITHUB_TOKEN
# ---------------------------------------------------------------------------

@test "setup_git_auth without GITHUB_TOKEN does not create .git-credentials" {
    git() { return 0; }
    export -f git

    unset GITHUB_TOKEN
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    run setup_git_auth
    [ "$status" -eq 0 ]
    [ ! -f "${HOME}/.git-credentials" ]
}

@test "setup_git_auth without GITHUB_TOKEN still returns 0" {
    git() { return 0; }
    export -f git

    unset GITHUB_TOKEN
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    run setup_git_auth
    [ "$status" -eq 0 ]
}

@test "setup_git_auth without GITHUB_TOKEN does not log credential lines" {
    git() { return 0; }
    export -f git

    unset GITHUB_TOKEN
    export GIT_USER_NAME="Test User"
    export GIT_USER_EMAIL="test@example.com"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    run setup_git_auth
    [ "$status" -eq 0 ]
    [[ "$output" != *"credential helper"* ]]
}

# ---------------------------------------------------------------------------
# INTERVAL default (read from sourced globals)
# ---------------------------------------------------------------------------

@test "INTERVAL variable defaults to 60 when REPO_SYNC_INTERVAL is unset" {
    unset REPO_SYNC_INTERVAL
    # Re-source to pick up the default assignment at the top of the script
    local n=$(( _FUNC_LINES - 1 ))
    eval "$(head -n "${n}" "${SYNC_SH}" | grep -v '^set -e')"
    [ "${INTERVAL}" = "60" ]
}

@test "INTERVAL uses REPO_SYNC_INTERVAL when set" {
    export REPO_SYNC_INTERVAL=120
    local n=$(( _FUNC_LINES - 1 ))
    eval "$(head -n "${n}" "${SYNC_SH}" | grep -v '^set -e')"
    [ "${INTERVAL}" = "120" ]
}
