#!/data/data/com.termux/files/usr/bin/bash
# Full R Pocket setup for a new device: R inside Ubuntu with prebuilt packages and Stan.
# Run inside Termux (installed from F-Droid):
#   curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/install.sh | bash
# Takes 30-60 minutes, mostly building CmdStan. Keep Termux open.
set -e
# Everything runs inside main() so bash reads the whole script before starting;
# otherwise commands run while piping from curl could swallow the rest of it.
main() {
  BASE="https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux"
  DIR="$HOME/.rpocket"

  echo "==> Updating Termux"
  yes | pkg upgrade -y
  pkg install -y curl

  echo "==> Installing the R Pocket listener"
  mkdir -p "$DIR"
  curl -fsSL "$BASE/rserver.R" -o "$DIR/rserver.R"
  curl -fsSL "$BASE/start.sh" -o "$DIR/start.sh"
  chmod +x "$DIR/start.sh"

  echo "==> Letting the R Pocket app start R"
  mkdir -p "$HOME/.termux"
  PROPS="$HOME/.termux/termux.properties"
  touch "$PROPS"
  if grep -q "^[[:space:]]*allow-external-apps" "$PROPS"; then
    sed -i 's/^[[:space:]]*allow-external-apps.*/allow-external-apps = true/' "$PROPS"
  else
    echo "allow-external-apps = true" >> "$PROPS"
  fi
  termux-reload-settings || true

  if [ ! -d "$HOME/storage/shared" ]; then
    echo "==> Asking for storage access so R can use your files (tap Allow)"
    termux-setup-storage || true
    sleep 3
  fi

  echo "==> Setting up Ubuntu, R, prebuilt packages and Stan"
  curl -fsSL "$BASE/setup-ubuntu.sh" -o "$DIR/setup-ubuntu.sh"
  bash "$DIR/setup-ubuntu.sh"
}
main "$@" < /dev/null
