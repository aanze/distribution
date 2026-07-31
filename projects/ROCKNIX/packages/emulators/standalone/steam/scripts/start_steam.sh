#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

steam_ensure_fex_config_template() {
  if [ ! -d "/storage/.config/fex-emu" ]; then
    cp -r "/usr/config/fex-emu" "/storage/.config/"
  fi
}

steam_prepare_storage_and_vdf() {
  mkdir -p /storage/roms/steam/steamapps
  local vdf="/storage/.local/share/Steam/steamapps/libraryfolders.vdf"
  if [ -f "$vdf" ]; then
    grep -q '"/storage/roms/steam"' "$vdf" || sed -i '$ s/}/\t"1" {"path" "\/storage\/roms\/steam"}\n}/' "$vdf"
  fi
}

steam_load_es_thunk_settings() {
  GAME=$(echo "${1}" | sed "s#^/.*/##")
  PLATFORM=$(echo "${2}" | sed "s#^/.*/##")
  ASOUND_LIB=$(get_setting asound_host_library "${PLATFORM}" "${GAME}")
  ASOUND_LIB=${ASOUND_LIB:-0}
  DRM_LIB=$(get_setting drm_host_library "${PLATFORM}" "${GAME}")
  DRM_LIB=${DRM_LIB:-0}
  VULKAN_LIB=$(get_setting vulkan_host_library "${PLATFORM}" "${GAME}")
  VULKAN_LIB=${VULKAN_LIB:-0}
  WAYLAND_LIB=$(get_setting wayland_client_host_library "${PLATFORM}" "${GAME}")
  WAYLAND_LIB=${WAYLAND_LIB:-0}
  GL_LIB=$(get_setting gl_host_library "${PLATFORM}" "${GAME}")
  GL_LIB=${GL_LIB:-0}
  GAMESCOPE=$(get_setting gamescope "${PLATFORM}" "${GAME}")
}

steam_write_fex_config_json() {
  local tmp
  tmp=$(mktemp)
  jq \
    --arg asound "$ASOUND_LIB" \
    --arg drm "$DRM_LIB" \
    --arg vulkan "$VULKAN_LIB" \
    --arg wayland "$WAYLAND_LIB" \
    --arg gl "$GL_LIB" \
    '.ThunksDB |= {
      asound: ($asound | tonumber),
      drm: ($drm | tonumber),
      Vulkan: ($vulkan | tonumber),
      WaylandClient: ($wayland | tonumber),
      GL: ($gl | tonumber)
    }' \
    /storage/.config/fex-emu/Config.json >"$tmp" &&
    mv "$tmp" /storage/.config/fex-emu/Config.json
}

steam_set_cpu_affinity() {
  local cores
  cores=$(get_setting "cores" "${PLATFORM}" "${GAME}")
  if [ "${cores}" = "little" ]; then
    EMUPERF="${SLOW_CORES}"
  elif [ "${cores}" = "big" ]; then
    EMUPERF="${FAST_CORES}"
  else
    unset EMUPERF
  fi
}

steam_debug_print() {
  echo "GAME set to: ${GAME}"
  echo "PLATFORM set to: ${PLATFORM}"
  echo "CPU CORES set to: ${EMUPERF}"
  echo "ASOUND HOST LIB set to: ${ASOUND_LIB}"
  echo "DRM HOST LIB set to: ${DRM_LIB}"
  echo "VULKAN HOST LIB set to: ${VULKAN_LIB}"
  echo "WAYLAND HOST LIB set to: ${WAYLAND_LIB}"
  echo "GL HOST LIB set to: ${GL_LIB}"
  echo "GAMESCOPE set to: ${GAMESCOPE}"
  echo "VSYNC set to: ${VSYNC}"
}

steam_read_sway_geometry() {
  eval "$(swaymsg -t get_outputs | jq -r '
    .[] | select(.focused == true) |
    "W=\(.current_mode.width) H=\(.current_mode.height) TRANSFORM=\(.transform) REFRESH=\(.current_mode.refresh // 60000)"
  ')"
  REFRESH_HZ=$((REFRESH / 1000))
}

steam_setup_environment() {
  TZ=$(timedatectl status | grep 'Time zone' | awk '{print $3}')
  [ -n "${TZ}" ] && export TZ
}

steam_scope_reexec_if_needed() {
  if [ -z "$_STEAM_SCOPE" ]; then
    systemctl stop steam-bigpicture.scope 2>/dev/null || true
    exec systemd-run \
      --scope \
      --slice=system.slice \
      --unit=steam-bigpicture \
      --collect \
      -E _STEAM_SCOPE=1 \
      -E HOME="$HOME" \
      -E USER="$USER" \
      -E TZ="$TZ" \
      -- "${STEAM_MAIN_SCRIPT}" "$@"
  fi
}

steam_dual_screen_begin() {
  if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
    swaymsg 'seat seat1 fallback true'
    PREFER_OUTPUT=(--prefer-output "$SDL_VIDEO_DISPLAY_PRIORITY")
  fi
  # With no priority list at all, gamescope treats every connected connector
  # as equal and takes whichever an unordered map iterates first - docked, it
  # would sometimes pick the external and sometimes the internal panel, run to
  # run. Prefer any external and fall back to the panel, like SteamOS's
  # session does with "*,eDP-1". Array, not string: "*" must reach gamescope
  # unexpanded, and an unquoted string would glob against the cwd.
  if [ ${#PREFER_OUTPUT[@]} -eq 0 ]; then
    PREFER_OUTPUT=(--prefer-output "*,${WLR_CON:-DSI-1}")
  fi
}

steam_dual_screen_end() {
  if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
    swaymsg 'seat seat1 fallback false'
  fi
}

steam_arm64_binfmt_and_proton_prep() {
  echo 0 >/proc/sys/fs/binfmt_misc/x86_64
  echo 0 >/proc/sys/fs/binfmt_misc/x86
  mkdir -p "/storage/.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)/"
  cp -f "/usr/share/steam/toolmanifest.vdf" "/storage/.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)/"
}

# gamescope only ever consults --force-orientation for an internal screen:
#
#   if ( GetScreenType() == GAMESCOPE_SCREEN_TYPE_INTERNAL &&
#        g_DesiredInternalOrientation != GAMESCOPE_PANEL_ORIENTATION_AUTO )
#
# so the value has to describe the built-in panel, not whichever output happens
# to be focused when Steam is launched. Taking it from the focused output meant
# that starting Steam while docked passed the external's "normal"; unplugging
# mid-session dropped gamescope back onto a portrait panel it had been told was
# upright, and the picture came back rotated 90 degrees until the next reboot.
# Passing the panel's own orientation is a no-op while docked and is already
# correct if the external goes away.
#
# fbcon/rotate is the same source 111-sway-init reads to derive the panel's
# sway transform, and unlike the sway output it stays readable while the panel
# is disabled - which is exactly the docked case.
steam_internal_panel_orientation() {
  case "$(cat /sys/class/graphics/fbcon/rotate 2>/dev/null)" in
    1) echo "right" ;;
    2) echo "upsidedown" ;;
    3) echo "left" ;;
    *) echo "normal" ;;
  esac
}

steam_launch_bigpicture() {
  local game_uri=""
  local force_orientation
  local gamescope_mode_file="/storage/.config/gamescope/modes.cfg"
  force_orientation=$(steam_internal_panel_orientation)

  if [[ "$1" == *.desktop && -f "$1" && "$(basename "$1")" != "Steam.desktop" ]]; then
    local exec_line
    exec_line=$(grep -m1 '^Exec=' "$1" | cut -d'=' -f2-)
    game_uri="${exec_line#steam } -silent"
  fi

  if [ "${GAMESCOPE}" != "0" ]; then
    mkdir -p "$(dirname "$gamescope_mode_file")"
    touch "$gamescope_mode_file"
  fi
  unset MESA_LOADER_DRIVER_OVERRIDE

  # Swappable Mesa Turnip driver for the Steam session (Steam + Proton games),
  # but NOT gamescope: GPU_DRV is injected AFTER the gamescope `--`, so the
  # compositor keeps running on the rock-solid stock driver. A broken
  # experimental driver then crashes only the game session, never the display.
  # See packages/tools/gpu-driver.
  local GPU_DRV=""
  if [ -x /usr/bin/gpu-driver ]; then
    local _vkdf
    _vkdf="$(/usr/bin/gpu-driver vkdf "${PLATFORM}" "${GAME}" 2>/dev/null)"
    [ -n "${_vkdf}" ] && GPU_DRV="env VK_DRIVER_FILES=${_vkdf}"
  fi
  if [ "${STEAM_FLAVOR}" = "arm64" ]; then
    SDL_VIDEODRIVER=x11 LD_LIBRARY_PATH=/storage/.local/share/Steam/lib/aarch64-linux-gnu/ ${EMUPERF} /storage/.local/share/Steam/steamrtarm64/steam -steamdeck -exitsteam
    if [ "${GAMESCOPE}" = "0" ]; then
      SDL_VIDEODRIVER=x11 LD_LIBRARY_PATH=/storage/.local/share/Steam/lib/aarch64-linux-gnu/ ${EMUPERF} ${GPU_DRV} /storage/.local/share/Steam/steamrtarm64/steam -nofriendsui -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders ${game_uri:+"$game_uri"}
      exit 0
    else
      systemctl stop sway
      GAMESCOPE_MODE_SAVE_FILE="${gamescope_mode_file}" GAMESCOPE_FAKE_OUTPUT_MM=508x286 env -u WAYLAND_DISPLAY LD_LIBRARY_PATH=/storage/.local/share/Steam/lib/aarch64-linux-gnu/ ${EMUPERF} \
        gamescope "${PREFER_OUTPUT[@]}" -W "$W" -H "$H" -r "$REFRESH_HZ" --xwayland-count 2 --mangoapp --backend drm --force-orientation "${force_orientation}" --use-rotation-shader -e -- \
        ${GPU_DRV} /storage/.local/share/Steam/steamrtarm64/steam -steamdeck -steamos3 -gamepadui -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders ${game_uri:+"$game_uri"}
      systemctl start essway
      # screen-capture: capture was drained+paused by steamos-session-select
      # before gamescope was killed. Do NOT touch it here -- resuming now arms
      # into the still-restarting compositor (wedge) and stopping frees buffers
      # on a hung WB (hard hang). The resume watcher (rocknix-screenrecord
      # __resumewatch) re-arms once sway+essway are solidly back, so one clip
      # continues ES -> gameplay -> ES.
      exit 0
    fi
  else
    FEX /usr/bin/steam -steamdeck -exitsteam
    if [ "${GAMESCOPE}" = "0" ]; then
      ${EMUPERF} ${GPU_DRV} FEX /usr/bin/steam -nofriendsui -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders ${game_uri:+"$game_uri"}
      exit 0
    else
      systemctl stop sway
      GAMESCOPE_MODE_SAVE_FILE="${gamescope_mode_file}" GAMESCOPE_FAKE_OUTPUT_MM=508x286 env -u WAYLAND_DISPLAY ${EMUPERF} \
        gamescope "${PREFER_OUTPUT[@]}" -W "$W" -H "$H" -r "$REFRESH_HZ" --xwayland-count 2 --mangoapp --backend drm --force-orientation "${force_orientation}" --use-rotation-shader -e -- \
        ${GPU_DRV} FEX /usr/bin/steam -steamdeck -steamos3 -gamepadui -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -noshaders ${game_uri:+"$game_uri"}
      systemctl start essway
      # screen-capture: capture was drained+paused by steamos-session-select
      # before gamescope was killed. Do NOT touch it here -- resuming now arms
      # into the still-restarting compositor (wedge) and stopping frees buffers
      # on a hung WB (hard hang). The resume watcher (rocknix-screenrecord
      # __resumewatch) re-arms once sway+essway are solidly back, so one clip
      # continues ES -> gameplay -> ES.
      exit 0
    fi
  fi
}

# Entry point from EmulationStation (not used when this file is sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source /etc/profile
  GAME=$(echo "${1}" | sed "s#^/.*/##")
  PLATFORM=$(echo "${2}" | sed "s#^/.*/##")
  STEAM_VERSION=$(get_setting steam_version "${PLATFORM}" "${GAME}")
  STEAM_VERSION=${STEAM_VERSION:-"arm64"}
  echo "STEAM_VERSION set to: ${STEAM_VERSION}"
  if [ "${STEAM_VERSION}" = "arm64" ]; then
    exec /usr/bin/start_steam_arm64.sh "$@"
  else
    exec /usr/bin/start_steam_x86.sh "$@"
  fi
fi
