Validate AgentCore configuration files and scripts for correctness.

Run these checks in order:

1. **library.json** — Parse `mcp-tools/library.json` and verify:
   - Valid JSON
   - Has `mcpServers` key
   - Every entry has either `command` or `url`
   - Every entry with `requiredEnv` has it as a list of strings
   - Every `default: true` tool does NOT also have `requiredEnv` (redundant)
   - No duplicate tool names

2. **Environment consistency** — Read `entrypoint/lib/env.sh` and check:
   - Every env var referenced in modules/*.sh is defined in env.sh
   - Every env var defined in env.sh is exported
   - Every env var in env.sh appears in `examples/.env.example`

3. **Module ordering** — List all `entrypoint/modules/*.sh` files and verify:
   - No duplicate numbers
   - No gaps that would cause confusion
   - All files are valid bash (syntax check with `bash -n` if available)

4. **Config files** — Verify:
   - `config/sshd_config` has `PermitRootLogin no` and `AllowUsers agent`
   - `config/chrome-policies.json` is valid JSON
   - `config/openbox-rc.xml` is valid XML structure

5. **Dockerfile consistency** — For each Dockerfile in `dockerfiles/`:
   - Verify ENTRYPOINT is set to `/opt/agentcore/entrypoint/entrypoint.sh`
   - Verify all required COPY statements exist (entrypoint/, api/, mcp-tools/, etc.)
   - Verify EXPOSE includes ports 22 and 8080

6. **Line endings** — Verify `.gitattributes` covers all script extensions

7. **Tests** — Run `pytest tests/test_configs.py -v` for automated config validation

Report all issues found. Fix any that are straightforward. For complex issues, describe what needs to change and ask for confirmation.
