#!/bin/bash
# Environment variable defaults and validation for AgentCore.
# All variables are set only if not already defined in the environment.

# --- Agent identity ---
: "${AGENT_TYPE:=claude}"
: "${AGENT_ID:=default}"
: "${AGENT_NAME:=$AGENT_ID}"
: "${AGENT_ROLE:=}"

# --- Feature flags ---
: "${ENABLE_DESKTOP:=false}"
: "${ENABLE_API:=true}"
: "${ENABLE_DIND:=false}"
: "${ENABLE_AUTO_UPDATE:=true}"
: "${ENABLE_ADBLOCK:=false}"

# --- VNC / Desktop ---
: "${VNC_PASSWORD:=agentpwd}"
: "${VNC_RESOLUTION:=1920x1080x24}"

# --- SSH ---
: "${SSH_PASSWORD:=agent}"
: "${SSH_AUTHORIZED_KEYS:=}"

# --- LLM / Proxy ---
: "${CODEGATE_URL:=}"
: "${LLM_PROXY_URL:=}"
: "${PROXY_API_KEY:=}"
: "${ANTHROPIC_API_KEY:=}"
: "${OPENAI_API_KEY:=}"

# --- Repos ---
: "${REPOS:=}"
: "${GITHUB_TOKEN:=}"
: "${REPO_SYNC_INTERVAL:=300}"

# --- Plugins ---
: "${PLUGIN_REPOS:=}"
: "${PLUGIN_SYNC_INTERVAL:=3600}"

# --- Memory ---
: "${MEMORY_PROVIDER:=local}"
: "${MEM0_API_KEY:=}"
: "${QDRANT_URL:=}"
: "${HIVEMINDDB_URL:=}"

# --- Refresh / update intervals ---
: "${CRED_REFRESH_INTERVAL:=300}"
: "${AUTO_UPDATE_INTERVAL:=3600}"

# --- API server ---
: "${API_AUTH_TOKEN:=}"

# --- Workspace ---
: "${WORKSPACE_ROOT:=/workspace}"
: "${PROJECTS_DIR:=/workspace/projects}"

# --- System locale / display ---
export DISPLAY=:0
export HOME=/home/agent
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Re-export all the above so child processes inherit them
export AGENT_TYPE AGENT_ID AGENT_NAME AGENT_ROLE
export ENABLE_DESKTOP ENABLE_API ENABLE_DIND ENABLE_AUTO_UPDATE ENABLE_ADBLOCK
export VNC_PASSWORD VNC_RESOLUTION
export SSH_PASSWORD SSH_AUTHORIZED_KEYS
export CODEGATE_URL LLM_PROXY_URL PROXY_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
export REPOS GITHUB_TOKEN REPO_SYNC_INTERVAL
export PLUGIN_REPOS PLUGIN_SYNC_INTERVAL
export MEMORY_PROVIDER MEM0_API_KEY QDRANT_URL HIVEMINDDB_URL
export CRED_REFRESH_INTERVAL AUTO_UPDATE_INTERVAL API_AUTH_TOKEN
export WORKSPACE_ROOT PROJECTS_DIR
