#!/data/data/com.termux/files/usr/bin/bash
# Starts (or restarts) the R Pocket listener. Called by the app.
# Usage: start.sh <token> [port] [start|restart|stop]
#   start   - start R only if it isn't already running (keeps a busy R running)
#   restart - stop any running R, then start a fresh one (default, for older app versions)
#   stop    - stop R and release the wake lock
#
# Uses R inside proot-distro Ubuntu when it's installed (prebuilt packages, Stan),
# otherwise Termux's own R. To force one, put "ubuntu" or "termux" in ~/.rpocket/engine.
TOKEN="$1"
PORT="${2:-8790}"
MODE="${3:-restart}"
DIR="$HOME/.rpocket"
UBUNTU_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"

if [ "$MODE" = "stop" ]; then
  pkill -f "rpocket/rserver.R" 2>/dev/null
  termux-wake-unlock 2>/dev/null
  exit 0
fi

if [ "$MODE" = "start" ] && pgrep -f "rpocket/rserver.R" > /dev/null 2>&1; then
  # Already running, maybe busy with a long job: leave it alone
  exit 0
fi

# Stop any running listener (Termux or Ubuntu)
pkill -f "rpocket/rserver.R" 2>/dev/null
sleep 0.5

# Keep Termux in the foreground with a wake lock, so Android doesn't stop R while you use other apps
termux-wake-lock 2>/dev/null

# Work in shared storage when it's set up, so your phone's files are visible
if [ -d "$HOME/storage/shared" ]; then
  WD="$HOME/storage/shared/R"
  mkdir -p "$WD"
else
  WD="$HOME/R"
  mkdir -p "$WD"
fi

ENGINE="auto"
[ -f "$DIR/engine" ] && ENGINE="$(tr -d '[:space:]' < "$DIR/engine")"
if [ "$ENGINE" = "auto" ]; then
  # Rscript inside the rootfs is a symlink to an absolute path, so check with -L / -e,
  # then ask proot-distro itself in case the rootfs lives somewhere else
  if [ -L "$UBUNTU_ROOT/usr/bin/Rscript" ] || [ -e "$UBUNTU_ROOT/usr/lib/R/bin/Rscript" ] ||
     proot-distro login ubuntu -- test -e /usr/bin/Rscript > /dev/null 2>&1; then
    ENGINE="ubuntu"
  else
    ENGINE="termux"
  fi
fi

echo "R Pocket: starting $ENGINE R in $WD" > "$DIR/log.txt"

if [ "$ENGINE" = "ubuntu" ]; then
  # Same folder appears at the same relative place inside Ubuntu
  WD_REAL="$(realpath "$WD" 2>/dev/null)"
  [ -n "$WD_REAL" ] || WD_REAL="$WD"
  setsid nohup proot-distro login ubuntu \
    --bind "$DIR:/opt/rpocket" \
    --bind "$WD_REAL:/root/storage/shared/R" \
    -- bash -c "cd /root/storage/shared/R && exec Rscript /opt/rpocket/rserver.R $PORT $TOKEN" \
    >> "$DIR/log.txt" 2>&1 < /dev/null &
else
  cd "$WD" || cd "$HOME"
  setsid nohup Rscript "$DIR/rserver.R" "$PORT" "$TOKEN" >> "$DIR/log.txt" 2>&1 < /dev/null &
fi
exit 0
