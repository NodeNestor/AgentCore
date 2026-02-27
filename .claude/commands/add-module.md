Add a new entrypoint module to AgentCore.

Ask the user for:
1. Module name (e.g. "healthcheck", "network-config")
2. Module number — must fit between existing modules (00 through 99). Show the current modules and their numbers so the user can pick.
3. What the module should do
4. Whether it should be conditional on an env var (like ENABLE_DESKTOP gates 20-desktop.sh)

Then:

1. Create `entrypoint/modules/NN-name.sh` with:
   ```bash
   #!/bin/bash
   # Module: NN-name
   # Description of what this module does.

   # If conditional:
   if [ "${ENABLE_FEATURE:-false}" != "true" ]; then
       log_info "Feature disabled. Skipping."
       return 0
   fi

   log_info "Starting feature setup..."
   # Module logic here
   log_info "Feature setup complete."
   ```

2. If the module needs a new env var:
   - Add it to `entrypoint/lib/env.sh` with a default value
   - Add it to the export list
   - Add it to the Environment Variables table in README.md
   - Add it to `examples/.env.example`

3. Update the module list in CLAUDE.md under "Project Structure"

4. Important rules for modules:
   - Use `return 0` to skip (NOT `exit 0` — modules are sourced)
   - Use `log_info`, `log_warn`, `log_error`, `log_debug` from lib/log.sh
   - `$CURRENT_MODULE` is set automatically from the filename
   - The module runs as root — use `su - agent -c` for agent-user commands
   - Background processes should be launched with `&` and should not block startup
