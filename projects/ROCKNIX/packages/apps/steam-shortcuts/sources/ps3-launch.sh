#!/bin/sh
# DUCKTALE ps3-in-steam launcher (instrumented)
LOG=/storage/.cache/ps3-launch.log
[ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ] && : > "$LOG"
{
  echo "=== $(date) pid=$$"
  echo "args($#): $*"
  echo "arch: $(uname -m 2>/dev/null)"
  echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR HOME=$HOME"
  echo "PATH=$PATH"
} >> "$LOG" 2>&1
GAME="$1"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if [ ! -e "$GAME" ]; then
  echo "GAME MISSING: $GAME" >> "$LOG"
  exit 1
fi
unset LD_LIBRARY_PATH LD_PRELOAD STEAM_RUNTIME STEAM_RUNTIME_LIBRARY_PATH \
      PRESSURE_VESSEL_RUNTIME SDL_DYNAMIC_API PYTHONHOME PYTHONPATH
export QT_QPA_PLATFORM=xcb
RPCS3_BIN="/usr/bin/rpcs3-sa"
for c in /storage/.local/share/rpcs3-sa/current.AppImage \
         /storage/.local/share/rpcs3-sa/previous.AppImage \
         /usr/bin/rpcs3-sa; do
  if [ -x "$c" ]; then RPCS3_BIN="$c"; break; fi
done
echo "exec: $RPCS3_BIN --no-gui $GAME" >> "$LOG"
exec "$RPCS3_BIN" --no-gui "$GAME" >> "$LOG" 2>&1
echo "EXEC FAILED code=$?" >> "$LOG"
exit 1
