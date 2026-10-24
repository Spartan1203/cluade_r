#!/data/data/com.termux/files/usr/bin/bash
# Starts (or restarts) the R Pocket listener. Called by the app.
# Usage: start.sh <token> [port]
TOKEN="$1"
PORT="${2:-8790}"
DIR="$HOME/.rpocket"

pkill -f "$DIR/rserver.R" 2>/dev/null
sleep 0.5

# Work in shared storage when it's set up, so your phone's files are visible
if [ -d "$HOME/storage/shared" ]; then
  WD="$HOME/storage/shared/R"
  mkdir -p "$WD"
else
  WD="$HOME"
fi

cd "$WD" || cd "$HOME"
setsid nohup Rscript "$DIR/rserver.R" "$PORT" "$TOKEN" > "$DIR/log.txt" 2>&1 < /dev/null &
exit 0
