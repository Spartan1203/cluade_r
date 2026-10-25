#!/data/data/com.termux/files/usr/bin/bash
# Starts (or restarts) the R Pocket listener. Called by the app.
# Usage: start.sh <token> [port]
#
# Uses R inside proot-distro Ubuntu when it's installed (prebuilt packages, Stan),
# otherwise Termux's own R. To force one, put "ubuntu" or "termux" in ~/.rpocket/engine.
TOKEN="$1"
PORT="${2:-8790}"
DIR="$HOME/.rpocket"
UBUNTU_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"

# Stop any running listener (Termux or Ubuntu)
pkill -f "rpocket/rserver.R" 2>/dev/null
sleep 0.5

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
  if [ -x "$UBUNTU_ROOT/usr/bin/Rscript" ]; then ENGINE="ubuntu"; else ENGINE="termux"; fi
fi

if [ "$ENGINE" = "ubuntu" ]; then
  # Same folder appears at the same relative place inside Ubuntu
  WD_REAL="$(realpath "$WD" 2>/dev/null)"
  [ -n "$WD_REAL" ] || WD_REAL="$WD"
  setsid nohup proot-distro login ubuntu \
    --bind "$DIR:/opt/rpocket" \
    --bind "$WD_REAL:/root/storage/shared/R" \
    -- bash -c "cd /root/storage/shared/R && exec Rscript /opt/rpocket/rserver.R $PORT $TOKEN" \
    > "$DIR/log.txt" 2>&1 < /dev/null &
else
  cd "$WD" || cd "$HOME"
  setsid nohup Rscript "$DIR/rserver.R" "$PORT" "$TOKEN" > "$DIR/log.txt" 2>&1 < /dev/null &
fi
exit 0
