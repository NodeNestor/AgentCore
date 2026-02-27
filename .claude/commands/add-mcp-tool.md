Add a new MCP tool to AgentCore.

Ask the user for:
1. Tool name (lowercase, hyphenated, e.g. "my-tool")
2. npm package or command (e.g. "npx @scope/mcp-server" or "python3 /opt/mcp-tools/my-tool/server.py")
3. Whether it should be default (always enabled) or opt-in (requires env var)
4. If opt-in: which environment variable(s) trigger it (e.g. "MY_TOOL_API_KEY")
5. Whether it requires the desktop environment
6. Category (development, testing, database, memory, system, network, documentation)

Then:

1. Read `mcp-tools/library.json`
2. Add the new entry to the `mcpServers` dict following the existing format:
   ```json
   "tool-name": {
     "name": "Tool Name",
     "description": "What this tool does",
     "command": "npx",
     "args": ["@scope/mcp-server"],
     "builtIn": false,
     "requiresDesktop": false,
     "category": "development",
     "default": false,
     "requiredEnv": ["MY_ENV_VAR"]
   }
   ```
3. If the tool uses a custom server script, create the directory at `mcp-tools/<tool-name>/` with `server.py` and `requirements.txt`
4. Add the env var to `entrypoint/lib/env.sh` with an empty default
5. Add the env var to the export list in `entrypoint/lib/env.sh`
6. Update the MCP Tools table in `README.md`
7. Run the MCP filter tests: `pytest tests/test_mcp_filter.py tests/test_configs.py -v`
