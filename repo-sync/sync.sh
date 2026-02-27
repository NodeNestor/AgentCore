#!/bin/bash
set -e

# AgentCore Repo Sync Daemon
#
# Parses REPOS env var and keeps git repositories synchronized.
# Supports pull (reset to remote) and push (auto-commit and push) modes.
#
# REPOS format (one repo per line, fields separated by |):
#   url|local_path|branch|mode
#
#   url    - Git clone URL (e.g. https://github.com/org/repo.git)
#   path   - Local filesystem path (e.g. /workspace/projects/myrepo)
#   branch - Branch to track (e.g. main)
#   mode   - Either "pull" or "push"
#
# Example REPOS value:
#   https://github.com/org/repo1.git|/workspace/projects/repo1|main|pull
#   https://github.com/org/repo2.git|/workspace/projects/repo2|main|push
#
# Environment variables:
#   REPOS               Newline-separated repo definitions (see above)
#   REPO_SYNC_INTERVAL  Seconds between sync cycles (default: 60)
#   GITHUB_TOKEN        Optional. If set, configures git credential helper.
#   GIT_USER_NAME       Git commit author name (default: AgentCore Sync)
#   GIT_USER_EMAIL      Git commit author email (default: agent@agentcore.local)

INTERVAL="${REPO_SYNC_INTERVAL:-60}"
GIT_USER_NAME="${GIT_USER_NAME:-AgentCore Sync}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-agent@agentcore.local}"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] [repo-sync] $*"
}

setup_git_auth() {
    if [ -n "${GITHUB_TOKEN}" ]; then
        log "Configuring git credential helper for GITHUB_TOKEN..."
        git config --global credential.helper store
        # Write credentials for both https variants
        {
            echo "https://x-token:${GITHUB_TOKEN}@github.com"
            echo "https://oauth2:${GITHUB_TOKEN}@github.com"
        } > "${HOME}/.git-credentials"
        chmod 600 "${HOME}/.git-credentials"

        # Also configure via URL rewriting so token is injected automatically
        git config --global url."https://x-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        log "Git auth configured."
    fi

    git config --global user.name "${GIT_USER_NAME}"
    git config --global user.email "${GIT_USER_EMAIL}"
    # Suppress detached HEAD advice and other noise
    git config --global advice.detachedHead false
    git config --global pull.rebase false
}

clone_if_missing() {
    local url="$1"
    local path="$2"
    local branch="$3"

    if [ ! -d "${path}/.git" ]; then
        log "Cloning ${url} into ${path} (branch: ${branch})..."
        mkdir -p "$(dirname "${path}")"
        git clone --branch "${branch}" --single-branch "${url}" "${path}" || {
            log "ERROR: Failed to clone ${url}"
            return 1
        }
        log "Cloned ${url} -> ${path}"
    fi
}

sync_pull() {
    local url="$1"
    local path="$2"
    local branch="$3"

    clone_if_missing "${url}" "${path}" "${branch}" || return 1

    log "PULL: Fetching ${url} (branch: ${branch}) -> ${path}"
    if git -C "${path}" fetch origin "${branch}" 2>&1; then
        git -C "${path}" reset --hard "origin/${branch}" 2>&1
        log "PULL: ${path} reset to origin/${branch}"
    else
        log "ERROR: Fetch failed for ${path}"
        return 1
    fi
}

sync_push() {
    local url="$1"
    local path="$2"
    local branch="$3"

    clone_if_missing "${url}" "${path}" "${branch}" || return 1

    log "PUSH: Checking for changes in ${path} (branch: ${branch})"

    # Check if there are any changes to commit
    if git -C "${path}" status --porcelain | grep -q .; then
        local commit_msg="Auto-sync $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        log "PUSH: Changes detected — staging all and committing: '${commit_msg}'"
        git -C "${path}" add -A
        git -C "${path}" commit -m "${commit_msg}" || {
            log "WARNING: git commit failed for ${path} (possibly nothing to commit)"
        }
        log "PUSH: Pushing ${path} to origin/${branch}..."
        git -C "${path}" push origin "${branch}" 2>&1 || {
            log "ERROR: Push failed for ${path}"
            return 1
        }
        log "PUSH: ${path} pushed successfully."
    else
        log "PUSH: No changes in ${path} — nothing to commit."
    fi
}

sync_all() {
    if [ -z "${REPOS}" ]; then
        log "No REPOS configured — nothing to sync."
        return 0
    fi

    log "--- Starting sync cycle ---"
    local success=0
    local failed=0

    # Read REPOS line by line
    while IFS='|' read -r url path branch mode; do
        # Skip empty lines and comment lines
        [ -z "${url}" ] && continue
        [[ "${url}" == \#* ]] && continue

        # Trim whitespace
        url="$(echo "${url}" | xargs)"
        path="$(echo "${path}" | xargs)"
        branch="$(echo "${branch}" | xargs)"
        mode="$(echo "${mode}" | xargs)"

        # Default branch and mode
        branch="${branch:-main}"
        mode="${mode:-pull}"

        log "Syncing: ${url} | ${path} | ${branch} | ${mode}"

        case "${mode}" in
            pull)
                if sync_pull "${url}" "${path}" "${branch}"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
                ;;
            push)
                if sync_push "${url}" "${path}" "${branch}"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
                ;;
            *)
                log "WARNING: Unknown mode '${mode}' for ${url} — skipping."
                ;;
        esac
    done <<< "${REPOS}"

    log "--- Sync cycle complete: ${success} succeeded, ${failed} failed ---"
}

# Main
log "Repo sync daemon starting."
log "Sync interval: ${INTERVAL}s"
if [ -n "${REPOS}" ]; then
    log "Repos configured:"
    while IFS= read -r line; do
        [ -n "${line}" ] && [[ "${line}" != \#* ]] && log "  ${line}"
    done <<< "${REPOS}"
else
    log "WARNING: No REPOS environment variable set. Daemon will idle."
fi

setup_git_auth

# Run an initial sync on startup
sync_all

# Then loop at the configured interval
while true; do
    log "Sleeping for ${INTERVAL}s until next sync..."
    sleep "${INTERVAL}"
    sync_all
done
