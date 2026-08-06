#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launch the GeForce NOW client (gfn-electron, arm64) under sway.
#
# This is a native-arm64 Electron wrapper of the GeForce NOW web app, so its
# Chromium uses the device's VAAPI/V4L2 (qcom-iris) decode path - no box64, no
# Vulkan-Video (which the Adreno/Turnip driver lacks).
#
# Must be started FROM EmulationStation (it appears in the "GeForce NOW" main-menu
# section). Launching it any other way lets ES think it is idle at the menu, which
# triggers the OLED screensaver over the top and tiles the window half-screen.
#
# First login: use your NVIDIA account (e-mail + password) or Discord. Google
# "Sign in with Google" is blocked inside any Electron/webview ("this browser or
# app may not be secure"), regardless of user-agent spoofing. The on-screen
# keyboard is hidden by default - summon/hide it with: hold left-Home + tap screen.
#
# Exit any time with the global combo L1 + START + SELECT.
#
# Optional flag: --stick-mouse (used by the "GeForce NOW (Right Stick Mouse)"
# entry) grafts a virtual mouse onto the InputPlumber composite for this
# session: right stick = mouse cursor, back paddles M1/M2 = left/right click,
# everything else stays gamepad. Real mouse motion unfreezes games whose
# controller cursor is dead over GFN (e.g. the Diablo II: Resurrected
# inventory reticule, frozen mid-screen - a known GFN bug since 2023).

source /etc/profile

STICK_MOUSE=0
[ "${1}" = "--stick-mouse" ] && STICK_MOUSE=1
IP_DEV_YAML=""
IP_RUN_YAML="/run/gfn-stick-mouse-composite.yaml"

APP_DIR="/usr/share/gfn-electron"
APPBIN="${APP_DIR}/geforcenow-electron"
LOG="/storage/.config/gfn-electron/gfn-electron.log"
mkdir -p "$(dirname "${LOG}")"

if [ ! -x "${APPBIN}" ]; then
  echo "gfn-electron is not installed (${APPBIN} missing)." | tee "${LOG}"
  sleep 10
  exit 1
fi

# Global exit combo (L1+START+SELECT): input_sense runs `killall` on these names.
# NOTE: busybox killall matches the FULL exe name, not the 15-char /proc/comm,
# so this must be "geforcenow-electron", not the truncated "geforcenow-elec".
set_kill set "geforcenow-electron wvkbd-mobintl"

# --- On-screen keyboard (hidden; summon with left-Home + tap) -----------------
# Use wvkbd directly with the clean rocknix-browser styling. The system
# touchkeyboard daemon's bigger font spills the cells, so stop it while we run.
TOUCHKB_WAS_ACTIVE=0
if systemctl is-active --quiet touchkeyboard.service; then
  TOUCHKB_WAS_ACTIVE=1
  systemctl stop touchkeyboard.service >/dev/null 2>&1 || true
fi
killall wvkbd-mobintl >/dev/null 2>&1 || true
sleep 0.3
KB_OUT="$(swaymsg -t get_outputs -r 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
KB_ARGS=(--hidden -L 380 -fn "Sans 22" -l simple)
[ -n "${KB_OUT}" ] && KB_ARGS+=(--output "${KB_OUT}")
/usr/bin/wvkbd-mobintl "${KB_ARGS[@]}" >/dev/null 2>&1 &
WVKBD_PID=$!

# Keep GFN fullscreen even when it spawns extra windows (OAuth popups), so it
# never ends up tiled to half the screen next to ES.
swaymsg 'for_window [app_id="GeForce NOW"] fullscreen enable' >/dev/null 2>&1 || true

cleanup() {
  kill "${WVKBD_PID}" 2>/dev/null || true
  [ -n "${TOUCHMOUSE_PID:-}" ] && kill "${TOUCHMOUSE_PID}" 2>/dev/null || true
  [ "${TOUCHKB_WAS_ACTIVE}" = "1" ] && systemctl start touchkeyboard.service >/dev/null 2>&1 || true
  if [ "${STICK_MOUSE}" = "1" ] && [ -n "${IP_DEV_YAML}" ]; then
    # Tear the session mouse graft down: drop the override and regenerate the
    # canonical composite for the persisted gamepad profile (restarts
    # InputPlumber - a ~2 s pad reset right after the app closed).
    umount "${IP_DEV_YAML}" 2>/dev/null || true
    rm -f "${IP_RUN_YAML}"
    gamepad-profile apply >/dev/null 2>&1 || systemctl restart inputplumber
  fi
  set_kill stop
}
trap cleanup EXIT

# --- Right Stick Mouse session graft (see header) -----------------------------
if [ "${STICK_MOUSE}" = "1" ]; then
  MODEL="$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null || \
           cat /sys/class/dmi/id/product_name 2>/dev/null)"
  [ -n "${MODEL}" ] && \
    IP_DEV_YAML="$(grep -rl "value: ${MODEL}" /usr/share/inputplumber/devices/ 2>/dev/null | head -1)"
  if [ -n "${IP_DEV_YAML}" ]; then
    # Rebuild the composite override from whatever is live (the stock ds5-edge
    # config, or the xbox-elite override mounted by gamepad-profile) with a
    # mouse target appended, then reroute right stick + paddles via the
    # session profile. The InputPlumber restart happens pre-stream, so the
    # ~2 s pad reset is invisible.
    cat "${IP_DEV_YAML}" > "${IP_RUN_YAML}"
    grep -q "^  - mouse" "${IP_RUN_YAML}" || \
      sed -i "/^target_devices:/a\\  - mouse" "${IP_RUN_YAML}"
    umount "${IP_DEV_YAML}" 2>/dev/null || true
    mount --bind "${IP_RUN_YAML}" "${IP_DEV_YAML}"
    systemctl restart inputplumber
    for _ in $(seq 1 20); do
      busctl call org.shadowblip.InputPlumber \
        /org/shadowblip/InputPlumber/CompositeDevice0 \
        org.shadowblip.Input.CompositeDevice LoadProfilePath s \
        /usr/share/inputplumber/profiles/right-stick-mouse.yaml \
        >/dev/null 2>&1 && break
      sleep 0.5
    done
    systemctl try-restart input.service >/dev/null 2>&1 || true
  fi
fi

# The NVIDIA OAuth/login opens https, so the clock must be correct or the TLS
# cert looks invalid. Right after a cold boot NTP may not have synced yet.
if command -v timedatectl >/dev/null 2>&1; then
  for _ in $(seq 1 10); do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && break
    systemctl start systemd-timesyncd >/dev/null 2>&1 || true
    sleep 1
  done
fi

# Display backend selection. In the EmulationStation session the inherited
# sway WAYLAND_DISPLAY is alive and wayland is the right backend. Launched
# from inside the Steam gamescope session (steam-shortcuts non-Steam
# entries) that socket is gone; gamescope maps X11 clients reliably while
# its wayland toplevels can sit unmapped forever (observed: app runs,
# Steam spinner never resolves) - so prefer X11 there, with a last-resort
# probe for any live wayland socket when there is no X server either.
OZONE_PLATFORM="wayland"
if [ ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
  if [ -n "${DISPLAY}" ]; then
    OZONE_PLATFORM="x11"
    # main.js appends wayland-targeted GL switches (use-gl=egl, no Vulkan)
    # whenever WAYLAND_DISPLAY is set - even pointing at a dead socket, as
    # /etc/profile always re-exports the ES session value. That broken-GL
    # combo on an X11 window is what painted the window white under Steam.
    unset WAYLAND_DISPLAY
  else
    WL_FOUND=""
    for _s in wayland-1 wayland-0 gamescope-0 gamescope-1; do
      if [ -S "${XDG_RUNTIME_DIR}/${_s}" ]; then
        export WAYLAND_DISPLAY="${_s}"
        WL_FOUND=1
        break
      fi
    done
    [ -z "${WL_FOUND}" ] && OZONE_PLATFORM="x11"
  fi
fi

EXTRA_FLAGS=""
if [ "${OZONE_PLATFORM}" = "x11" ]; then
  # DOM text tiles GPU-rasterize to nothing on this build's X11/EGL path
  # (canvas + images fine, glyphs absent); CPU raster paints them correctly.
  EXTRA_FLAGS="--disable-gpu-rasterization"
  # Touch -> virtual-mouse daemon (the OpenNOW helper): gamescope does not
  # deliver the panel's touch to this X11 client, and the cloud session's
  # Steam popups need a pointer. The uinput mouse reaches the focused app
  # (tap = left click, drag = cursor). Killed with the app via cleanup().
  # ES-session launches keep the app's native wayland touch instead.
  if [ -x /usr/bin/opennow-touchmouse-daemon ]; then
    /usr/bin/opennow-touchmouse-daemon >/dev/null 2>&1 &
    TOUCHMOUSE_PID=$!
  fi
fi
if [ "${OZONE_PLATFORM}" = "x11" ]; then
  # Steam-session specifics: the gamescope WSI Vulkan layer is meant for a
  # game's own fullscreen swapchain - attached to Chromium's GPU process it
  # leaves the window white - and the window must start fullscreen to give
  # gamescope a properly sized surface instead of a small centered box.
  export ENABLE_GAMESCOPE_WSI=0

fi

# Inhibit suspend/idle for the whole streaming session: a stream has long stretches
# with no local input, and an auto-suspend re-enumerates the gamepad and wedges
# input on resume. exec so the inhibitor lives exactly as long as the app.
exec systemd-inhibit \
  --what=sleep:idle:handle-suspend-key:handle-lid-switch \
  --who="gfn-electron" --why="GeForce NOW streaming" \
  "${APPBIN}" --no-sandbox \
    --ozone-platform="${OZONE_PLATFORM}" \
    --enable-features=UseOzonePlatform,VaapiVideoDecoder \
    --enable-wayland-ime \
    ${EXTRA_FLAGS} \
  2>&1 | tee "${LOG}"
