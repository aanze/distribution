#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Removes Decky Loader: stops/disables the plugin_loader service, removes its
# unit, the boot watcher, and the homebrew tree (PluginLoader + plugins/settings).

source /etc/profile

AUTOSTART_DIR="/storage/.config/autostart"
WATCHER="${AUTOSTART_DIR}/decky-steam-fix.sh"
SYSTEMD_DIR="/storage/.config/system.d"
HOMEBREW="/storage/homebrew"

log_info() { echo -e "[\033[1;34mINFO\033[0m] $1"; }

log_info "Stopping the Steam-launch watcher..."
pkill -f "decky-steam-fix.sh --daemon" 2>/dev/null || true
rm -f "${WATCHER}"

log_info "Stopping and disabling the Decky service..."
systemctl stop plugin_loader.service 2>/dev/null || true
systemctl disable plugin_loader.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/plugin_loader.service"
rm -f "${SYSTEMD_DIR}/multi-user.target.wants/plugin_loader.service"
systemctl daemon-reload 2>/dev/null || true

log_info "Removing the Decky homebrew tree..."
rm -rf "${HOMEBREW}"

echo ""
echo "Decky Loader removed (binary, service, watcher, plugins and settings)."
echo "Run 'Install Decky Loader' again to reinstall."
sleep 5
