#!/bin/bash
# Module: 55-plugins
# Plugin marketplace sync and installation.

PLUGIN_SOURCES_DIR=/opt/plugin-sources
PLUGINS_BUILTIN_DIR=/opt/plugins
PLUGINS_CUSTOM_DIR=/opt/plugins-custom
PLUGINS_TARGET_DIR=/home/agent/.claude/plugins
INSTALLED_PLUGINS_JSON=/home/agent/.claude/installed_plugins.json
SETTINGS_JSON=/home/agent/.claude/settings.json

log_info "Setting up plugins..."

mkdir -p "$PLUGINS_TARGET_DIR"

installed_names=()

# --- Clone remote plugin repos ---
if [ -n "$PLUGIN_REPOS" ]; then
    log_info "Syncing plugin repos from PLUGIN_REPOS..."
    mkdir -p "$PLUGIN_SOURCES_DIR"

    while IFS= read -r repo_url; do
        # Strip leading/trailing whitespace and skip empty lines
        repo_url="$(echo "$repo_url" | xargs)"
        [ -z "$repo_url" ] && continue

        repo_name="$(basename "$repo_url" .git)"
        clone_dest="$PLUGIN_SOURCES_DIR/$repo_name"

        if [ -d "$clone_dest/.git" ]; then
            log_info "  Updating plugin repo: $repo_name"
            git -C "$clone_dest" pull --quiet 2>/dev/null || log_warn "  Failed to update $repo_name"
        else
            log_info "  Cloning plugin repo: $repo_url -> $clone_dest"
            git clone --quiet "$repo_url" "$clone_dest" 2>/dev/null || {
                log_warn "  Failed to clone $repo_url"
                continue
            }
        fi

        # Scan for plugin directories (contain package.json or manifest.json)
        while IFS= read -r -d '' manifest; do
            plugin_dir="$(dirname "$manifest")"
            plugin_name="$(basename "$plugin_dir")"
            link_target="$PLUGINS_TARGET_DIR/$plugin_name"

            if [ ! -e "$link_target" ]; then
                ln -s "$plugin_dir" "$link_target"
                log_debug "  Symlinked plugin: $plugin_name"
            fi
            installed_names+=("$plugin_name")
        done < <(find "$clone_dest" -maxdepth 3 \( -name "package.json" -o -name "manifest.json" \) -print0)

    done <<< "$PLUGIN_REPOS"
fi

# --- Built-in plugins (/opt/plugins/) ---
if [ -d "$PLUGINS_BUILTIN_DIR" ]; then
    log_info "Linking built-in plugins from $PLUGINS_BUILTIN_DIR..."
    for plugin_dir in "$PLUGINS_BUILTIN_DIR"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name="$(basename "$plugin_dir")"
        link_target="$PLUGINS_TARGET_DIR/$plugin_name"
        if [ ! -e "$link_target" ]; then
            ln -s "$plugin_dir" "$link_target"
            log_debug "  Symlinked built-in plugin: $plugin_name"
        fi
        installed_names+=("$plugin_name")
    done
fi

# --- Custom / mounted plugins (/opt/plugins-custom/) ---
if [ -d "$PLUGINS_CUSTOM_DIR" ]; then
    log_info "Linking custom plugins from $PLUGINS_CUSTOM_DIR..."
    for plugin_dir in "$PLUGINS_CUSTOM_DIR"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name="$(basename "$plugin_dir")"
        link_target="$PLUGINS_TARGET_DIR/$plugin_name"
        if [ ! -e "$link_target" ]; then
            ln -s "$plugin_dir" "$link_target"
            log_debug "  Symlinked custom plugin: $plugin_name"
        fi
        installed_names+=("$plugin_name")
    done
fi

# --- Write installed_plugins.json ---
if [ ${#installed_names[@]} -gt 0 ]; then
    log_info "Writing installed_plugins.json (${#installed_names[@]} plugins)..."

    python3 - <<PYEOF
import json

names = $(python3 -c "import sys,json; names=${#installed_names[@]}; print(json.dumps(['${installed_names[@]}']))" 2>/dev/null || echo "[]")

# Build from bash array passed via heredoc substitution
import os

raw = """${installed_names[*]}"""
plugins = [n.strip() for n in raw.split() if n.strip()] if raw.strip() else []

with open("$INSTALLED_PLUGINS_JSON", "w") as f:
    json.dump({"installedPlugins": plugins, "count": len(plugins)}, f, indent=2)
print(f"[INFO]  [55-plugins] Wrote {len(plugins)} plugin entries.")
PYEOF

    # Update settings.json with enabledPlugins list
    python3 - <<PYEOF
import json, os

settings_path = "$SETTINGS_JSON"
plugins_dir   = "$PLUGINS_TARGET_DIR"

try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

# Discover all symlinked/installed plugin names
plugins = []
if os.path.isdir(plugins_dir):
    plugins = [
        name for name in os.listdir(plugins_dir)
        if os.path.isdir(os.path.join(plugins_dir, name))
    ]

settings["enabledPlugins"] = plugins

# Add placeholder marketplace entries if any custom repos were specified
plugin_repos_raw = os.environ.get("PLUGIN_REPOS", "").strip()
if plugin_repos_raw:
    marketplaces = [
        url.strip()
        for url in plugin_repos_raw.splitlines()
        if url.strip()
    ]
    settings.setdefault("extraKnownMarketplaces", [])
    for m in marketplaces:
        if m not in settings["extraKnownMarketplaces"]:
            settings["extraKnownMarketplaces"].append(m)

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print(f"[INFO]  [55-plugins] Updated settings.json with {len(plugins)} enabled plugin(s).")
PYEOF

else
    log_info "No plugins found. Skipping settings.json update."
fi

chown -R agent:agent "$PLUGINS_TARGET_DIR" 2>/dev/null || true
chown agent:agent "$INSTALLED_PLUGINS_JSON" 2>/dev/null || true

log_info "Plugin setup complete."
