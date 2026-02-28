#!/bin/bash
# Module: 70-agent-start
# Start the selected coding agent inside a tmux session.
# All tmux commands run as the 'agent' user (entrypoint runs as root).
#
# Optional: AGENT_INITIAL_PROMPT — if set, passed as the initial prompt
# to Claude Code (e.g. AGENT_INITIAL_PROMPT="fix the tests").

_agent_tmux() {
    # Run a tmux command as the agent user
    su - agent -c "$*" 2>/dev/null || true
}

log_info "Starting agent in tmux (AGENT_TYPE=$AGENT_TYPE)..."

case "$AGENT_TYPE" in

    claude)
        # Build the claude command with optional initial prompt
        CLAUDE_ARGS="--dangerously-skip-permissions"
        if [ -n "${AGENT_INITIAL_PROMPT:-}" ]; then
            log_info "Initial prompt: ${AGENT_INITIAL_PROMPT:0:60}..."
        fi

        su - agent -c "
            export DISPLAY=:0
            cd /workspace/projects
            tmux new-session -d -s agent
            tmux send-keys -t agent 'claude $CLAUDE_ARGS' Enter
        "
        log_info "Claude session started in tmux session 'agent'."
        ;;

    opencode)
        su - agent -c "
            export DISPLAY=:0
            cd /workspace/projects
            tmux new-session -d -s agent
            tmux send-keys -t agent 'opencode' Enter
        "
        log_info "OpenCode session started in tmux session 'agent'."
        ;;

    aider)
        su - agent -c "
            export DISPLAY=:0
            cd /workspace/projects
            tmux new-session -d -s agent
            tmux send-keys -t agent 'aider' Enter
        "
        log_info "Aider session started in tmux session 'agent'."
        ;;

    all)
        log_info "Starting all agents in separate tmux windows..."

        su - agent -c "
            export DISPLAY=:0
            cd /workspace/projects
            tmux new-session -d -s agent
            tmux send-keys -t agent 'claude --dangerously-skip-permissions' Enter
            tmux new-window -t agent
            tmux send-keys -t agent:1 'opencode' Enter
            tmux new-window -t agent
            tmux send-keys -t agent:2 'aider' Enter
        "
        log_info "  Window 0: Claude, Window 1: OpenCode, Window 2: Aider"
        ;;

    none)
        log_info "No agent selected — creating empty tmux session."
        su - agent -c "tmux new-session -d -s agent" 2>/dev/null || true
        ;;

    *)
        log_warn "Unknown AGENT_TYPE: '$AGENT_TYPE'. Creating empty tmux session."
        su - agent -c "tmux new-session -d -s agent" 2>/dev/null || true
        ;;
esac

log_info "Agent tmux session ready."
