#!/data/data/com.termux/files/usr/bin/bash
# Optional: run R inside Ubuntu (proot-distro) for prebuilt CRAN packages and Stan.
# Run in Termux after setup.sh:
#   curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/setup-ubuntu.sh | bash
# Takes 30-60 minutes (mostly building CmdStan). Keep Termux open.
set -e
# Everything runs inside main() so bash reads the whole script before starting;
# otherwise commands run while piping from curl could swallow the rest of it.
main() {
  BASE="https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux"
  in_ubuntu() { proot-distro login ubuntu -- "$@"; }

  termux-wake-lock || true

  echo "==> Installing Ubuntu"
  pkg install -y proot-distro
  if ! in_ubuntu true > /dev/null 2>&1; then
    proot-distro install ubuntu
  fi
  CODENAME="$(in_ubuntu bash -c '. /etc/os-release && echo $VERSION_CODENAME')"
  echo "    Ubuntu release: $CODENAME"

  echo "==> Installing R with prebuilt CRAN packages (r2u)"
  in_ubuntu bash -c "apt update && apt install -y curl && curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash"

  echo "==> Installing compilers, cmdstanr and rethinking"
  in_ubuntu apt install -y build-essential
  in_ubuntu Rscript -e 'install.packages("cmdstanr", repos = c("https://stan-dev.r-universe.dev", getOption("repos")))'
  # rethinking loads digest for ulam() without declaring it, so install it explicitly
  in_ubuntu Rscript -e 'install.packages(c("remotes", "digest", "coda", "mvtnorm", "loo", "shape", "dagitty", "posterior"))'
  in_ubuntu Rscript -e 'remotes::install_github("rmcelreath/rethinking", upgrade = "never")'

  echo "==> Building CmdStan (20-60 minutes)"
  in_ubuntu Rscript -e 'cmdstanr::install_cmdstan(cores = 2)'

  echo "==> Pointing R Pocket at Ubuntu's R"
  mkdir -p "$HOME/.rpocket"
  curl -fsSL "$BASE/start.sh" -o "$HOME/.rpocket/start.sh"
  chmod +x "$HOME/.rpocket/start.sh"

  termux-wake-unlock || true
  echo ""
  echo "Done. In R Pocket, tap the stop button to restart R."
}
main "$@" < /dev/null
