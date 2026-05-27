#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Installs the OpenNOW (GeForce NOW) arm64 AppImage from the upstream GitHub
# releases and creates the launcher that makes the OpenNOW main-menu section
# appear (EmulationStation hides systems whose ROM folder is empty).

source /etc/profile

OPENNOW_DIR="/storage/roms/opennow"
APPIMAGE="${OPENNOW_DIR}/OpenNOW.AppImage"
LAUNCHER="${OPENNOW_DIR}/OpenNOW.sh"
LAUNCHER_MOUSE="${OPENNOW_DIR}/OpenNOW (Mouse).sh"
RELEASES_API="https://api.github.com/repos/OpenCloudGaming/OpenNOW/releases/latest"

echo "Installing OpenNOW (GeForce NOW client)..."
mkdir -p "${OPENNOW_DIR}"

echo "Looking up the latest arm64 release..."
ASSET_URL="$(curl -fsSL "${RELEASES_API}" \
  | grep -oE '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -iE 'arm64|aarch64' \
  | grep -iE '\.AppImage$' \
  | head -n1)"

if [ -z "${ASSET_URL}" ]; then
  echo "ERROR: could not find an arm64 .AppImage in the latest OpenNOW release."
  echo "Check https://github.com/OpenCloudGaming/OpenNOW/releases manually."
  sleep 15
  exit 1
fi

echo "Downloading: ${ASSET_URL}"
if ! wget -c -t 5 -O "${APPIMAGE}.part" "${ASSET_URL}"; then
  echo "ERROR: download failed."
  rm -f "${APPIMAGE}.part"
  sleep 15
  exit 1
fi
mv -f "${APPIMAGE}.part" "${APPIMAGE}"
chmod +x "${APPIMAGE}"

# Pre-fetch the on-device login browser now so the first NVIDIA OAuth login
# (which has a short timeout) doesn't have to download it on the fly.
echo "Preparing the on-device login browser..."
/usr/bin/rocknix-browser --ensure || \
  echo "WARNING: browser pre-fetch failed; it will retry at first login."

# Launcher run from the OpenNOW section. Its presence is what unhides the
# section in EmulationStation.
cat > "${LAUNCHER}" <<'EOF'
#!/bin/bash
exec /usr/bin/start_opennow.sh
EOF
chmod +x "${LAUNCHER}"

# Second launcher that runs opennow-touchmouse-daemon alongside OpenNOW, so the
# touchscreen acts as a mouse (tap = left click, drag = pointer move). Useful
# when GeForce NOW boots a "good" game into the desktop Steam UI instead of
# Big Picture - the controller doesn't navigate that screen, but tap-to-click
# does. The daemon is killed when OpenNOW exits.
cat > "${LAUNCHER_MOUSE}" <<'EOF'
#!/bin/bash
/usr/bin/opennow-touchmouse-daemon &
DAEMON_PID=$!
trap 'kill ${DAEMON_PID} 2>/dev/null' EXIT
/usr/bin/start_opennow.sh
EOF
chmod +x "${LAUNCHER_MOUSE}"

echo ""
echo "OpenNOW installed successfully."
echo "Restart EmulationStation to see the OpenNOW section in the main menu."
echo "Two launchers are available: 'OpenNOW' (normal) and 'OpenNOW (Mouse)'"
echo "(turns the touchscreen into a mouse - use it for games whose Steam shell"
echo " doesn't accept the controller)."
echo "On first launch, the NVIDIA login opens in an on-device browser - no SSH needed."
sleep 10
