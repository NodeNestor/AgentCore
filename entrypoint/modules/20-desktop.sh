#!/bin/bash
# Module: 20-desktop
# Start desktop environment (Xvfb, Openbox, VNC, noVNC).
# Only runs if ENABLE_DESKTOP=true.

if [ "$ENABLE_DESKTOP" != "true" ]; then
    log_info "Desktop disabled (ENABLE_DESKTOP=$ENABLE_DESKTOP). Skipping."
    return 0
fi

log_info "Starting desktop environment (resolution: $VNC_RESOLUTION)..."

# Kill any stale Xvfb lock files / processes
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
pkill -f Xvfb 2>/dev/null || true

# Start Xvfb
Xvfb :0 -screen 0 "${VNC_RESOLUTION}" -ac +extension GLX +render -noreset &
XVFB_PID=$!
log_info "Xvfb started (pid $XVFB_PID)."

# Wait briefly for Xvfb to be ready
sleep 1

# Start Openbox window manager
DISPLAY=:0 openbox-session &
log_info "Openbox started."

# Start x11vnc (no password — accessed only via localhost/docker network)
x11vnc \
    -display :0 \
    -nopw \
    -forever \
    -shared \
    -noxdamage \
    -rfbport 5900 \
    -bg \
    -o /var/log/x11vnc.log 2>/dev/null
log_info "x11vnc started on port 5900 (no auth)."

# Start noVNC via websockify
# Debian/Ubuntu novnc package installs to /usr/share/novnc, manual installs go to /opt/noVNC
NOVNC_DIR="/usr/share/novnc"
[ ! -d "$NOVNC_DIR" ] && NOVNC_DIR="/opt/noVNC"
[ ! -d "$NOVNC_DIR" ] && NOVNC_DIR="/usr/share/novnc"

websockify --daemon \
    --web="$NOVNC_DIR" \
    6080 \
    localhost:5900 \
    > /var/log/novnc.log 2>&1
log_info "noVNC started on port 6080 (web: $NOVNC_DIR)."

# --- Chrome first-run configuration ---
log_info "Configuring Chrome defaults..."

CHROME_CONFIG_DIR=/home/agent/.config/google-chrome/Default
mkdir -p "$CHROME_CONFIG_DIR"

# Sentinel file so Chrome skips the "First Run" dialog
touch /home/agent/.config/google-chrome/First\ Run
touch /home/agent/.config/google-chrome/"First Run"

# Write Default/Preferences to suppress first-run dialogs and disable telemetry
cat > "$CHROME_CONFIG_DIR/Preferences" <<'CHROME_PREFS'
{
  "browser": {
    "check_default_browser": false,
    "has_seen_welcome_page": true
  },
  "distribution": {
    "import_bookmarks": false,
    "make_chrome_default": false,
    "make_chrome_default_for_user": false,
    "skip_first_run_ui": true,
    "show_welcome_page": false,
    "suppress_first_run_default_browser_prompt": true
  },
  "first_run_tabs": [],
  "profile": {
    "default_content_setting_values": {
      "notifications": 2
    }
  },
  "signin": {
    "allowed": false
  },
  "sync_promo": {
    "startup_count": 99,
    "user_skipped": true
  },
  "metrics": {
    "reporting_enabled": false
  },
  "safebrowsing": {
    "enabled": false,
    "reporting_enabled": false
  }
}
CHROME_PREFS

chown -R agent:agent /home/agent/.config 2>/dev/null || true
log_info "Chrome defaults configured."

log_info "Desktop environment ready."
