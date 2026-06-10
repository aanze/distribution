#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Installs Steam Deck's Decky Loader (SteamFork/ROCKNIX build, by seilent) plus a
# small boot-time watcher that re-injects Decky's UI into Steam when Steam is
# launched.
#
# Why the watcher: Decky's plugin_loader.service lives in /storage and already
# survives OS updates, but it starts at boot (before Steam). When it has been
# running since boot its frontend injection into Steam's CEF UI often silently
# fails (the Decky Quick Access tab never appears) until plugin_loader is
# restarted with Steam running. The watcher automates exactly that, and because
# it is written to /storage it persists across nightly updates.
#
# This tool is intentionally re-runnable with NO "already installed" guard: it
# always performs a full (re)install, which is also the quickest repair.

set -e
set -o pipefail

source /etc/profile

DECKY_INSTALL_URL="https://decky.seilent.net"
AUTOSTART_DIR="/storage/.config/autostart"
WATCHER="${AUTOSTART_DIR}/decky-steam-fix.sh"

log_info()    { echo -e "[\033[1;34mINFO\033[0m] $1"; }
log_success() { echo -e "[\033[1;32mSUCCESS\033[0m] $1"; sleep 10; exit 0; }
die()         { echo -e "[\033[1;31mERROR\033[0m] $1" >&2; sleep 10; exit 1; }

install_decky() {
  log_info "Downloading and running the Decky Loader installer..."
  command -v jq >/dev/null 2>&1 || die "jq is required but was not found."
  curl -L "${DECKY_INSTALL_URL}" | sh || die "The Decky Loader installer failed."
}

install_watcher() {
  log_info "Installing the Steam-launch re-inject watcher (persists across updates)..."
  mkdir -p "${AUTOSTART_DIR}"
  cat > "${WATCHER}" <<'WATCHER_EOF'
#!/bin/bash
# Decky frontend re-inject on Steam launch — minimal-intrusion edition.
#
# Decky's PluginLoader starts at boot (before Steam). When Steam's CEF UI comes
# up the loader tries to inject its frontend; that attempt sometimes fails (the
# Decky Quick Access tab never appears), reliably logging:
#   [helpers][WARNING]: Failed to execute get_loader_version(): ... 'NoneType'
# A restart of plugin_loader while Steam is up makes the injection take.
#
# This watcher waits for Steam's CEF debug port, gives Decky time to inject on
# its own, and ONLY restarts plugin_loader if that injection failed. When Decky
# injects fine by itself it does nothing (no overlay reload). It never touches
# Steam or gamescope.
#
# Installed by "Install Decky Loader" into /storage/.config/autostart so it is
# launched at every boot and survives OS updates.

SERVICE="plugin_loader.service"
CEF_PORT="8080"
CEF_URL="http://127.0.0.1:${CEF_PORT}/json/version"
SETTLE=10     # let Decky attempt its own injection after the UI is up
POLL=3

cef_up() { curl -sf --max-time 2 "${CEF_URL}" >/dev/null 2>&1; }

# 0 = the latest frontend-load attempt since $1 did NOT take.
inject_failed_since() {
  local log
  log="$(journalctl -u "${SERVICE}" --since "${1}" --no-pager 2>/dev/null)"
  echo "${log}" | grep -q "Loading Decky frontend"               || return 1
  echo "${log}" | grep -q "Failed to execute get_loader_version" && return 0
  return 1
}

watch_loop() {
  local seen=0 mark edge
  while true; do
    mark="$(date '+%Y-%m-%d %H:%M:%S')"
    if cef_up; then
      if [ "${seen}" = "0" ]; then
        seen=1
        if systemctl is-active --quiet "${SERVICE}"; then
          edge="${mark}"
          sleep "${SETTLE}"
          if cef_up && inject_failed_since "${edge}"; then
            logger -t decky-steam-fix "injection failed -> restarting ${SERVICE}"
            systemctl restart "${SERVICE}"
          fi
        fi
      fi
    else
      seen=0
    fi
    sleep "${POLL}"
  done
}

# Detach so the boot autostart's `wait` does not block on us.
if [ "${1}" != "--daemon" ]; then
  setsid "${0}" --daemon >/dev/null 2>&1 &
  exit 0
fi
watch_loop
WATCHER_EOF
  chmod 0755 "${WATCHER}"

  # (Re)start it now so the fix is active without a reboot.
  pkill -f "decky-steam-fix.sh --daemon" 2>/dev/null || true
  setsid "${WATCHER}" </dev/null >/dev/null 2>&1 || true
}

log_info "Starting Decky Loader installation..."
install_decky
install_watcher

echo ""
log_success "Decky Loader installed. Launch Steam (Big Picture) and open the Quick Access menu to find Decky. The plugin now survives nightly updates."
