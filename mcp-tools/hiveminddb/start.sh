#!/bin/bash
# HiveMindDB MCP server wrapper
# Ensures node_modules are resolved correctly by running from the package directory
cd /opt/mcp-tools/hiveminddb
exec node index.js "$@"
