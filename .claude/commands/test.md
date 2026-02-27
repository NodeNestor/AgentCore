Run the AgentCore test suite.

Usage: /test [suite]

Where [suite] is one of: python, shell, docker, all

If no argument is given, run the python tests.

Test commands:
- python: `pip install -r tests/requirements-dev.txt && pytest tests/ -v`
- shell: `bats tests/shell/*.bats` (requires bats-core installed)
- docker: run `bash tests/test-minimal.sh` then `bash tests/test-api.sh` (requires Docker)
- all: run python, then shell, then docker

Report the results: total tests, passed, failed, and any failure details.

If tests fail, read the failing test file and the source code it tests, diagnose the root cause, and fix it. The key source files are:
- api/server.py (tested by tests/test_api_server.py)
- mcp-tools/agent-memory/server.py (tested by tests/test_agent_memory.py)
- mcp-tools/library.json (tested by tests/test_configs.py and tests/test_mcp_filter.py)
- entrypoint/modules/60-llm-config.sh (tested by tests/test_llm_config.py)
- entrypoint/lib/log.sh (tested by tests/shell/test_log.bats)
- entrypoint/lib/env.sh (tested by tests/shell/test_env.bats)
