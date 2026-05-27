#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Installs or updates the OpenNOW (GeForce NOW) arm64 AppImage from the upstream
# GitHub releases and creates the launchers that make the OpenNOW main-menu
# section appear (EmulationStation hides systems whose ROM folder is empty).
#
# Re-running this tool on an already-current install is a no-op (just re-checks
# the latest tag against the installed one). From SSH, pass --force to bypass
# the check and redownload unconditionally.

source /etc/profile

FORCE=0
[ "$1" = "--force" ] && FORCE=1

OPENNOW_DIR="/storage/roms/opennow"
APPIMAGE="${OPENNOW_DIR}/OpenNOW.AppImage"
LAUNCHER="${OPENNOW_DIR}/OpenNOW.sh"
LAUNCHER_MOUSE="${OPENNOW_DIR}/OpenNOW (Mouse).sh"
INSTALLED_TAG_FILE="${OPENNOW_DIR}/.installed_tag"
RELEASES_API="https://api.github.com/repos/OpenCloudGaming/OpenNOW/releases/latest"

write_launchers() {
  cat > "${LAUNCHER}" <<'EOF'
#!/bin/bash
exec /usr/bin/start_opennow.sh
EOF
  chmod +x "${LAUNCHER}"

  # Second launcher that runs opennow-touchmouse-daemon alongside OpenNOW, so
  # the touchscreen acts as a mouse (tap = left click, drag = pointer move).
  # Useful when GeForce NOW boots a "good" game into the desktop Steam UI
  # instead of Big Picture - the controller doesn't navigate that screen, but
  # tap-to-click does. The daemon is killed when OpenNOW exits.
  cat > "${LAUNCHER_MOUSE}" <<'EOF'
#!/bin/bash
/usr/bin/opennow-touchmouse-daemon &
DAEMON_PID=$!
trap 'kill ${DAEMON_PID} 2>/dev/null' EXIT
/usr/bin/start_opennow.sh
EOF
  chmod +x "${LAUNCHER_MOUSE}"
}

echo "Installing/updating OpenNOW (GeForce NOW client)..."
mkdir -p "${OPENNOW_DIR}"

echo "Looking up the latest arm64 release..."
API_JSON="$(curl -fsSL "${RELEASES_API}")"
LATEST_TAG="$(printf '%s' "${API_JSON}" \
  | grep -oE '"tag_name": *"[^"]+"' \
  | head -n1 \
  | sed -E 's/.*"([^"]+)".*/\1/')"
ASSET_URL="$(printf '%s' "${API_JSON}" \
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

# No-op short-circuit: if the AppImage is already at LATEST_TAG, skip the
# ~150 MB download. We still rewrite the launchers (idempotent) so the menu
# section stays consistent even if a launcher was deleted by the user.
if [ "${FORCE}" != "1" ] && [ -x "${APPIMAGE}" ] && [ -n "${LATEST_TAG}" ] \
   && [ -f "${INSTALLED_TAG_FILE}" ] \
   && [ "$(cat "${INSTALLED_TAG_FILE}")" = "${LATEST_TAG}" ]; then
  echo "OpenNOW is already up to date (${LATEST_TAG})."
  echo "Re-run from SSH with --force to redownload."
  write_launchers
  /usr/bin/rocknix-browser --ensure >/dev/null 2>&1 || true
  sleep 5
  exit 0
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
[ -n "${LATEST_TAG}" ] && printf '%s\n' "${LATEST_TAG}" > "${INSTALLED_TAG_FILE}"

# Pre-fetch the on-device login browser now so the first NVIDIA OAuth login
# (which has a short timeout) doesn't have to download it on the fly.
echo "Preparing the on-device login browser..."
/usr/bin/rocknix-browser --ensure || \
  echo "WARNING: browser pre-fetch failed; it will retry at first login."

write_launchers

echo ""
echo "OpenNOW ${LATEST_TAG:-installed} successfully."
echo "Restart EmulationStation to see the OpenNOW section in the main menu."
echo "Two launchers are available: 'OpenNOW' (normal) and 'OpenNOW (Mouse)'"
echo "(turns the touchscreen into a mouse - use it for games whose Steam shell"
echo " doesn't accept the controller)."
echo "On first launch, the NVIDIA login opens in an on-device browser - no SSH needed."
sleep 10
