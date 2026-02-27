#!/bin/bash
# create-agent-user.sh — Create the 'agent' system user (uid 1000, gid 1000) for
# AgentCore containers. Handles uid/gid collisions by removing any existing user
# or group that owns those IDs before creating the new ones. Grants passwordless
# sudo access. Run as root.
set -e

AGENT_USER="agent"
AGENT_UID=1000
AGENT_GID=1000
AGENT_PASSWORD="agent"

echo "[create-agent-user] Setting up user '${AGENT_USER}' (uid=${AGENT_UID}, gid=${AGENT_GID})..."

# ---------------------------------------------------------------------------
# Resolve uid collision (must happen before gid — can't delete a primary group)
# ---------------------------------------------------------------------------
EXISTING_USER="$(getent passwd "${AGENT_UID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_USER}" ] && [ "${EXISTING_USER}" != "${AGENT_USER}" ]; then
    echo "[create-agent-user] Removing existing user '${EXISTING_USER}' that owns uid ${AGENT_UID}..."
    userdel -r "${EXISTING_USER}" 2>/dev/null || userdel "${EXISTING_USER}" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Resolve gid collision
# ---------------------------------------------------------------------------
EXISTING_GROUP="$(getent group "${AGENT_GID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_GROUP}" ] && [ "${EXISTING_GROUP}" != "${AGENT_USER}" ]; then
    echo "[create-agent-user] Removing existing group '${EXISTING_GROUP}' that owns gid ${AGENT_GID}..."
    groupdel "${EXISTING_GROUP}"
fi

# ---------------------------------------------------------------------------
# Create group (if not already present with correct gid)
# ---------------------------------------------------------------------------
if ! getent group "${AGENT_USER}" > /dev/null 2>&1; then
    groupadd -g "${AGENT_GID}" "${AGENT_USER}"
    echo "[create-agent-user] Created group '${AGENT_USER}' with gid ${AGENT_GID}."
else
    echo "[create-agent-user] Group '${AGENT_USER}' already exists."
fi

# ---------------------------------------------------------------------------
# Create user (if not already present with correct uid)
# ---------------------------------------------------------------------------
if ! getent passwd "${AGENT_USER}" > /dev/null 2>&1; then
    useradd \
        -u "${AGENT_UID}" \
        -g "${AGENT_GID}" \
        -m \
        -s /bin/bash \
        -c "AgentCore agent user" \
        "${AGENT_USER}"
    echo "[create-agent-user] Created user '${AGENT_USER}' with uid ${AGENT_UID}."
else
    echo "[create-agent-user] User '${AGENT_USER}' already exists."
fi

# ---------------------------------------------------------------------------
# Set password
# ---------------------------------------------------------------------------
echo "${AGENT_USER}:${AGENT_PASSWORD}" | chpasswd
echo "[create-agent-user] Password set for '${AGENT_USER}'."

# ---------------------------------------------------------------------------
# Add to sudo group
# ---------------------------------------------------------------------------
usermod -aG sudo "${AGENT_USER}"
echo "[create-agent-user] Added '${AGENT_USER}' to the sudo group."

# ---------------------------------------------------------------------------
# Grant passwordless sudo
# ---------------------------------------------------------------------------
SUDOERS_FILE="/etc/sudoers.d/${AGENT_USER}"
echo "${AGENT_USER} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_FILE}"
chmod 0440 "${SUDOERS_FILE}"
echo "[create-agent-user] Granted NOPASSWD sudo via ${SUDOERS_FILE}."

echo "[create-agent-user] Done."
