#!/bin/bash
# Module: 65-repos
# Clone git repositories at startup based on REPOS env var.
#
# REPOS format (multi-line, each line pipe-separated):
#   url|path|branch|mode
#
#   url    - git repository URL (required)
#   path   - destination path  (default: $PROJECTS_DIR/<repo-name>)
#   branch - branch to checkout (default: repository default)
#   mode   - "pull" (read-only clone) or "push" (writable, sync daemon)

SYNC_DAEMON_NEEDED=false

_setup_git_auth() {
    if [ -n "$GITHUB_TOKEN" ]; then
        log_info "Configuring git credential helper for GitHub token..."
        git config --global credential.helper store
        # Write the credentials store file
        echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > /home/agent/.git-credentials
        chown agent:agent /home/agent/.git-credentials
        chmod 600 /home/agent/.git-credentials
    fi
}

if [ -z "$REPOS" ]; then
    log_info "REPOS is not set. Skipping repo clone."
    return 0
fi

log_info "Cloning repositories..."
_setup_git_auth

while IFS= read -r repo_line; do
    # Skip blank lines and comments
    repo_line="$(echo "$repo_line" | xargs)"
    [ -z "$repo_line" ] || [[ "$repo_line" == \#* ]] && continue

    # Parse pipe-separated fields
    IFS='|' read -r repo_url repo_path repo_branch repo_mode <<< "$repo_line"

    repo_url="$(echo "$repo_url" | xargs)"
    repo_path="$(echo "$repo_path" | xargs)"
    repo_branch="$(echo "$repo_branch" | xargs)"
    repo_mode="$(echo "$repo_mode" | xargs)"

    [ -z "$repo_url" ] && continue

    # Default path
    if [ -z "$repo_path" ]; then
        repo_name="$(basename "$repo_url" .git)"
        repo_path="${PROJECTS_DIR}/${repo_name}"
    fi

    # Default mode
    : "${repo_mode:=pull}"

    log_info "  Repo: $repo_url -> $repo_path (branch: ${repo_branch:-default}, mode: $repo_mode)"

    if [ -d "$repo_path/.git" ]; then
        log_info "  Already cloned, pulling latest..."
        git -C "$repo_path" pull --quiet 2>/dev/null || log_warn "  Pull failed for $repo_path"
    else
        mkdir -p "$(dirname "$repo_path")"
        if [ -n "$repo_branch" ]; then
            git clone --quiet --branch "$repo_branch" "$repo_url" "$repo_path" 2>/dev/null || {
                log_warn "  Clone failed for $repo_url"
                continue
            }
        else
            git clone --quiet "$repo_url" "$repo_path" 2>/dev/null || {
                log_warn "  Clone failed for $repo_url"
                continue
            }
        fi
    fi

    # Checkout specific branch if given and not used in clone
    if [ -n "$repo_branch" ] && [ -d "$repo_path/.git" ]; then
        git -C "$repo_path" checkout --quiet "$repo_branch" 2>/dev/null || \
            log_warn "  Could not checkout branch $repo_branch in $repo_path"
    fi

    chown -R agent:agent "$repo_path" 2>/dev/null || true

    if [ "$repo_mode" = "push" ]; then
        SYNC_DAEMON_NEEDED=true
    fi

done <<< "$REPOS"

# --- Start repo-sync daemon for push-mode repos ---
if [ "$SYNC_DAEMON_NEEDED" = "true" ]; then
    log_info "Starting repo-sync daemon (interval: ${REPO_SYNC_INTERVAL}s)..."

    (
        while true; do
            sleep "$REPO_SYNC_INTERVAL"

            while IFS= read -r repo_line; do
                repo_line="$(echo "$repo_line" | xargs)"
                [ -z "$repo_line" ] || [[ "$repo_line" == \#* ]] && continue

                IFS='|' read -r repo_url repo_path _ repo_mode <<< "$repo_line"
                repo_path="$(echo "$repo_path" | xargs)"
                repo_mode="$(echo "$repo_mode" | xargs)"

                [ "$repo_mode" != "push" ] && continue
                [ -z "$repo_path" ] && repo_path="${PROJECTS_DIR}/$(basename "$repo_url" .git)"
                [ -d "$repo_path/.git" ] || continue

                git -C "$repo_path" add -A 2>/dev/null
                if git -C "$repo_path" diff --cached --quiet 2>/dev/null; then
                    continue
                fi
                git -C "$repo_path" commit -m "auto-sync: $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet 2>/dev/null
                git -C "$repo_path" push --quiet 2>/dev/null || true
            done <<< "$REPOS"
        done
    ) &

    log_info "Repo-sync daemon started (pid $!)."
fi

log_info "Repository setup complete."
