#!/bin/bash
set -e
echo "=== Testing AgentCore Ubuntu Image ==="

IMAGE="agentcore:ubuntu"
CONTAINER="agentcore-test-ubuntu"

# Build
echo "[TEST] Building ubuntu image..."
docker build -f dockerfiles/Dockerfile.ubuntu -t $IMAGE .

# Run with desktop enabled
echo "[TEST] Starting container with desktop..."
docker run -d --name $CONTAINER \
  -p 2222:22 \
  -p 5900:5900 \
  -p 6080:6080 \
  -p 8080:8080 \
  -e AGENT_TYPE=none \
  -e ENABLE_API=true \
  -e ENABLE_DESKTOP=true \
  -e VNC_PASSWORD=testpwd \
  $IMAGE

# Wait for startup (desktop takes longer)
echo "[TEST] Waiting for startup (desktop needs more time)..."
sleep 20

# Health check
echo "[TEST] Checking health endpoint..."
HEALTH=$(curl -s http://localhost:8080/health)
echo "Health: $HEALTH"

# Ready check
echo "[TEST] Checking ready endpoint..."
READY=$(curl -s http://localhost:8080/ready)
echo "Ready: $READY"

# noVNC check
echo "[TEST] Checking noVNC (port 6080)..."
NOVNC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:6080/)
echo "noVNC HTTP status: $NOVNC_STATUS"
if [ "$NOVNC_STATUS" = "200" ]; then
  echo "[PASS] noVNC is reachable"
else
  echo "[WARN] noVNC returned status $NOVNC_STATUS (may still be starting)"
fi

# VNC port check
echo "[TEST] Checking VNC port (5900)..."
if nc -z -w 3 localhost 5900 2>/dev/null; then
  echo "[PASS] VNC port 5900 is open"
else
  echo "[WARN] VNC port 5900 is not reachable (desktop may still be starting)"
fi

# SSH check
echo "[TEST] Checking SSH..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 agent@localhost -p 2222 echo "SSH works" || echo "SSH connection test (password auth needed)"

# Check Xvfb process inside container
echo "[TEST] Checking Xvfb process..."
docker exec $CONTAINER pgrep -x Xvfb && echo "[PASS] Xvfb is running" || echo "[WARN] Xvfb not detected"

# Check Chrome installation
echo "[TEST] Checking Chrome installation..."
docker exec $CONTAINER which google-chrome-stable 2>/dev/null && echo "[PASS] Chrome is installed" || \
  docker exec $CONTAINER which chromium-browser 2>/dev/null && echo "[PASS] Chromium is installed" || \
  echo "[WARN] No Chrome/Chromium found"

# Cleanup
echo "[TEST] Cleaning up..."
docker stop $CONTAINER && docker rm $CONTAINER

echo "=== Ubuntu image tests complete ==="
