# R Pocket

Run real, native R on your Android phone. R itself runs inside [Termux](https://f-droid.org/packages/com.termux/);
R Pocket is the interface: a code editor, a Run button, a console, plots, and saved snippets.

## Install (one time)

1. **Install Termux from F-Droid** (not the Play Store version) and open it once.
2. **Set up R in Termux.** Paste this into Termux and wait for "Done":
   ```
   curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/setup.sh | bash
   ```
   Tap Allow if it asks for storage access.
3. **Install the app.** On your phone, download
   [RPocket.apk](https://github.com/Spartan1203/cluade_r/releases/latest/download/RPocket.apk)
   and open it. Allow installing from your browser if Android asks.
4. **Open R Pocket** and allow it to run commands in Termux when asked.

## Optional: Ubuntu R with prebuilt packages and Stan

Termux's own R compiles every package from source, and Stan won't build there. For prebuilt
CRAN packages (installs take seconds) and full Stan/`cmdstanr` support (e.g. `rethinking::ulam()`),
run R inside Ubuntu instead. In Termux:
```
curl -fsSL https://raw.githubusercontent.com/Spartan1203/cluade_r/main/termux/setup-ubuntu.sh | bash
```
This takes 30-60 minutes (mostly building CmdStan) and about 2-3 GB. Afterwards R Pocket starts
Ubuntu's R automatically; put `termux` in `~/.rpocket/engine` to switch back.

## Using it

- **Run all** runs the whole editor; **Run line** runs the current line (or full multi-line expression,
  or your selection) and moves to the next line.
- One R session stays alive between runs, like the RStudio console. **■** restarts it.
- Plots appear in the **Plots** tab; swipe to go back through them.
- **Files** shows your phone's `Internal storage/R` folder. Tap a CSV to insert `read.csv(...)`.
- **★** saves and loads code snippets.
- `install.packages()` works. Packages that compile code can take several minutes, and the console
  shows the result when it finishes.

## How it works

`termux/rserver.R` is a small HTTP listener written in base R. It only answers requests carrying a
secret token that the app generates, and the app starts it through Termux's official
`RUN_COMMAND` permission. Every push to `main` builds a new APK with GitHub Actions and
publishes it to the `latest` release.

Note: the signing key in `signing/` is committed so builds install over each other. That's fine for
personal use; use a private key before distributing the app.
