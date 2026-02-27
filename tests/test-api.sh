#!/bin/bash
set -e
echo "=== Testing AgentCore Control API ==="

BASE_URL="http://localhost:8080"

# Health
echo "[TEST] GET /health"
curl -s $BASE_URL/health | jq .

# Ready
echo "[TEST] GET /ready"
curl -s $BASE_URL/ready | jq .

# List instances
echo "[TEST] GET /instances"
curl -s $BASE_URL/instances | jq .

# Create instance
echo "[TEST] POST /instances"
curl -s -X POST $BASE_URL/instances -H "Content-Type: application/json" -d '{"name":"test","agent_type":"claude"}' | jq .

# List again
echo "[TEST] GET /instances (after create)"
curl -s $BASE_URL/instances | jq .

# Exec
echo "[TEST] POST /exec"
curl -s -X POST $BASE_URL/exec -H "Content-Type: application/json" -d '{"command":"whoami"}' | jq .

# Logs
echo "[TEST] GET /logs"
curl -s "$BASE_URL/logs?lines=5"

echo "=== API tests complete ==="
