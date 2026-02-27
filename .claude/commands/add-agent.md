Add a new coding agent type to AgentCore.

Ask the user for:
1. Agent name (lowercase, e.g. "cursor", "cline", "continue")
2. How to install it (npm, pip, binary download, etc.)
3. The command to launch it (e.g. "cursor", "cline --headless")
4. Whether it needs any special setup/config before first run
5. How to update it (for the auto-update daemon)

Then make these changes:

1. **Install script** — Add installation to `base/install-agents.sh` (or create `base/install-<name>.sh` if complex, and call it from the Dockerfiles)

2. **Agent setup** — Add a case branch in `entrypoint/modules/40-agent-setup.sh`:
   ```bash
   <name>)
       log_info "Configuring <Name>..."
       # Any setup needed before first run
       log_info "<Name> setup complete."
       ;;
   ```

3. **Agent start** — Add a case branch in `entrypoint/modules/70-agent-start.sh`:
   ```bash
   <name>)
       su - agent -c "
           export DISPLAY=:0
           cd /workspace/projects
           tmux new-session -d -s agent
           tmux send-keys -t agent '<launch-command>' Enter
       "
       log_info "<Name> session started in tmux session 'agent'."
       (
           sleep 5
           su - agent -c "tmux send-keys -t agent Enter" 2>/dev/null || true
       ) &
       ;;
   ```

4. **Control API** — Add the agent command to the `agent_commands` dict in `api/server.py` `create_tmux_window()`:
   ```python
   "<name>": "<launch-command>",
   ```

5. **Auto-update** — Create `auto-update/agents/<name>.sh`:
   ```bash
   #!/bin/bash
   # Update script for <Name>
   log_info "Checking for <Name> updates..."
   # Update logic here
   ```

6. **All mode** — Add a new tmux window in the `all)` case of `70-agent-start.sh`

7. **Documentation** — Update the agent table in README.md and CLAUDE.md

8. **Tests** — Run `pytest tests/test_api_server.py -v` to verify API changes
