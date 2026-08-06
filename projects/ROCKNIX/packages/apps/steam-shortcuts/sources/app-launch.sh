#!/bin/sh
# DUCKTALE steam-shortcuts: run a native ES launcher script (.sh from a roms
# section, e.g. geforcenow) from inside the Steam session.
#
# The Steam session spawns us natively (verified with the PS3 wrapper), but
# with a PATH missing the native binaries and an x86 Steam runtime env. Fix
# both, and point WAYLAND_DISPLAY at gamescope's own wayland socket so
# launchers that hardcode --ozone-platform=wayland (start_gfn-electron.sh)
# connect to gamescope instead of looking for the ES-session sway socket.

LOG=/storage/.cache/steam-app-launch.log
[ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ] && : > "$LOG"
TARGET="$1"
{
  echo "=== $(date) pid=$$ target=$TARGET"
  echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  echo "SteamDeck=$SteamDeck"
  echo "runtime sockets: $(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -e wayland -e gamescope | tr "\n" " ")"
} >> "$LOG" 2>&1

[ -e "$TARGET" ] || { echo "TARGET MISSING" >> "$LOG"; exit 1; }

# gfn-electron gates its fullscreen mode on process.env.SteamDeck. Do NOT
# set it for OpenNOW: its Steam Deck mode forces a 1280x800 Deck-sized
# window (small centered rectangle on this 1080p panel) while its default
# path already fills the screen.
case "$(basename "$TARGET")" in
  GeForce*) export GFN_WINDOW_W=1920 GFN_WINDOW_H=1080 ;;
esac
# Private fontconfig/XDG cache: the shared /storage/.cache/fontconfig was
# written by a NEWER fontconfig than the one on the current image, which
# then refuses both the caches and their regeneration - Chromium renders
# with NO fonts at all (empty buttons/labels). A per-context cache dir is
# rebuilt at the running library version and stays consistent.
export XDG_CACHE_HOME=/storage/.cache/steam-shortcuts-cache
mkdir -p "$XDG_CACHE_HOME"

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD STEAM_RUNTIME STEAM_RUNTIME_LIBRARY_PATH \
      PRESSURE_VESSEL_RUNTIME SDL_DYNAMIC_API PYTHONHOME PYTHONPATH

if [ -z "$WAYLAND_DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
  for s in gamescope-0 gamescope-1 gamescope-2; do
    if [ -S "$XDG_RUNTIME_DIR/$s" ]; then
      export WAYLAND_DISPLAY="$s"
      echo "using WAYLAND_DISPLAY=$s" >> "$LOG"
      break
    fi
  done
fi

exec /bin/bash "$TARGET" >> "$LOG" 2>&1
