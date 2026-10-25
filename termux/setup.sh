#!/data/data/com.termux/files/usr/bin/bash
# One-time setup for R Pocket. Run inside Termux:
#   curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/setup.sh | bash
set -e
BASE="https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux"
DIR="$HOME/.rpocket"

echo "==> Updating packages"
# A full upgrade matters: R from the TUR repo needs current system libraries (such as libicu)
yes | pkg upgrade -y

echo "==> Installing R (this can take a few minutes)"
pkg install -y tur-repo
yes | pkg upgrade -y
# gcc-15 is the compiler this R was built with; install.packages() needs it for C/C++/Fortran code
pkg install -y r-base libicu which gcc-15 build-essential pkg-config

if ! R --version > /dev/null 2>&1; then
  echo ""
  echo "R is installed but won't start. Its system libraries are out of date."
  echo "Fix: run 'termux-change-repo', pick a different mirror, then run this setup again."
  R --version 2>&1 | head -2
  exit 1
fi

echo "==> Adding a header some R packages (such as cli) need on Termux"
if [ ! -f "$PREFIX/include/bthread.h" ]; then
  curl -fsSL "$BASE/bthread.h" -o "$PREFIX/include/bthread.h"
fi

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
if Rscript -e 'quit(status = !(isTRUE(capabilities("cairo")) || isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE)))'; then
  echo "    Plots: ready"
else
  echo "    Plots: installing the ragg graphics package (15-30 minutes; keep Termux open)"
  set +e
  pkg install -y freetype libpng libjpeg-turbo libtiff libwebp harfbuzz fribidi fontconfig
  Rscript -e 'install.packages("ragg", repos = "https://cloud.r-project.org")'
  if Rscript -e 'quit(status = !requireNamespace("ragg", quietly = TRUE))'; then
    echo "    Plots: ready"
  else
    echo "    Plots: ragg didn't install, so plots won't show in the app yet."
  fi
  set -e
fi

if [ ! -d "$HOME/storage/shared" ]; then
  echo "==> Asking for storage access so R can read your phone's files (tap Allow)"
  termux-setup-storage || true
fi

echo ""
echo "Done. Open the R Pocket app and tap Start R."
R --version | head -1
