#!/data/data/com.termux/files/usr/bin/bash
# One-time setup for R Pocket. Run inside Termux:
#   curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/setup.sh | bash
set -e
BASE="https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux"
DIR="$HOME/.rpocket"

echo "==> Updating packages"
pkg update -y

echo "==> Installing R (this can take a few minutes)"
pkg install -y tur-repo
pkg install -y r-base build-essential

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

echo "==> Checking plot support"
if Rscript -e 'quit(status = !(isTRUE(capabilities("cairo")) || isTRUE(capabilities("png"))))'; then
  echo "    Plots: ready"
else
  echo "    Plots: installing the ragg graphics package"
  set +e
  pkg install -y freetype libpng libjpeg-turbo libtiff harfbuzz fribidi fontconfig
  Rscript -e 'install.packages("ragg", repos = "https://cloud.r-project.org")'
  set -e
fi

if [ ! -d "$HOME/storage/shared" ]; then
  echo "==> Asking for storage access so R can read your phone's files (tap Allow)"
  termux-setup-storage || true
fi

echo ""
echo "Done. Open the R Pocket app and tap Start R."
R --version | head -1
