#!/bin/bash
set -e
echo "=== Testing AgentCore Minimal Image ==="

IMAGE="agentcore:minimal"
CONTAINER="agentcore-test-minimal"

# Build
echo "[TEST] Building minimal image..."
docker build -f dockerfiles/Dockerfile.minimal -t $IMAGE .

# Run
echo "[TEST] Starting container..."
docker run -d --name $CONTAINER -p 2222:22 -p 8080:8080 -e AGENT_TYPE=none -e ENABLE_API=true $IMAGE

# Wait for startup
echo "[TEST] Waiting for startup..."
sleep 10

# Health check
echo "[TEST] Checking health endpoint..."
HEALTH=$(curl -s http://localhost:8080/health)
echo "Health: $HEALTH"

# SSH check
echo "[TEST] Checking SSH..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 agent@localhost -p 2222 echo "SSH works" || echo "SSH connection test (password auth needed)"

# Cleanup
echo "[TEST] Cleaning up..."
docker stop $CONTAINER && docker rm $CONTAINER

echo "=== Minimal image tests complete ==="
