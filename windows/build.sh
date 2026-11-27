#!/bin/bash
# Folio Studio for Windows: builds every app and makes one MSI, FolioStudio-<version>-x64.msi.
#
#   In the "MSYS2 UCRT64" shell (Start menu), from this checkout of Folio Studio:
#     bash windows/build.sh
#   or double-click windows\build.cmd, which opens that shell for you.
#
# What it needs: MSYS2 (https://www.msys2.org, installed in C:\msys64) and an internet
# connection. The compilers and the runtime the apps run on (Python, GTK, GStreamer, Qt, ffmpeg)
# come from MSYS2's packages, the Rust crates from crates.io, the apps' code from GitHub.
#
# Settings (all optional):
#   FOLIO_SRC   where the apps' code is kept      (default ~/folio-src)
#   FOLIO_WORK  where the build happens           (default ~/folio-build)
#   FOLIO_OUT   where the MSI is put              (default your Desktop)
#   FOLIO_LOCAL=1  use the code already in FOLIO_SRC as it is (no git pull)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STUDIO="$(dirname "$HERE")"
SRC="${FOLIO_SRC:-$HOME/folio-src}"
WORK="${FOLIO_WORK:-$HOME/folio-build}"
# the Desktop as Explorer shows it (OneDrive keeps it elsewhere than %USERPROFILE%\Desktop)
desktop() {
  local d
  d="$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2>/dev/null | tr -d '\r')"
  if [ -n "$d" ] && [ -d "$(cygpath -u "$d")" ]; then cygpath -u "$d"; else echo "$(cygpath -u "$USERPROFILE")/Desktop"; fi
}
OUT="${FOLIO_OUT:-$(desktop)}"
VERSION="$(tr -d '[:space:]' < "$STUDIO/VERSION")"
TREE="$WORK/Folio Studio"
LOG="$WORK/build.log"
step() { printf '\n== %s\n' "$*"; printf '\n== %s\n' "$*" >> "$LOG"; }
die() { printf '\nThe build stopped: %s\nThe whole log is in %s\n' "$*" "$(cygpath -w "$LOG")" >&2; exit 1; }
quiet() { "$@" >> "$LOG" 2>&1 || die "$* failed (the end of the log says why)"; }

[ "${MSYSTEM:-}" = UCRT64 ] || { echo "Run this in the MSYS2 UCRT64 shell (Start menu > MSYS2 UCRT64), or double-click build.cmd."; exit 1; }
mkdir -p "$WORK" "$SRC" "$OUT"
: > "$LOG"
echo "Folio Studio $VERSION for Windows"

# ---------------------------------------------------------------- packages
P=mingw-w64-ucrt-x86_64
BUILD=(git pacman-contrib "$P-gcc" "$P-rust" "$P-cmake" "$P-ninja" "$P-pkgconf" "$P-msitools" "$P-python-pip")
RUNTIME=("$P-python" "$P-python-gobject" "$P-python-cairo" "$P-python-numpy" "$P-python-pillow"
         "$P-gtk3" "$P-adwaita-icon-theme" "$P-librsvg" "$P-gdk-pixbuf2" "$P-poppler"
         "$P-gstreamer" "$P-gst-plugins-base" "$P-gst-plugins-good" "$P-gst-plugins-bad" "$P-gst-plugins-ugly"
         "$P-gst-libav" "$P-gst-editing-services" "$P-gst-python" "$P-ffmpeg"
         "$P-enchant" "$P-hunspell" "$P-glib-networking" "$P-ca-certificates" "$P-qt6-base" "$P-qt6-svg" "$P-cairo" "$P-pango" "$P-freetype")
# wanted, but the apps manage without them (or pip brings them below)
OPTIONAL=("$P-python-cryptography" "$P-python-mutagen" "$P-python-shapely" "$P-python-pyenchant" "$P-hunspell-en")
step "MSYS2 packages"
# MSYS2's package lists, brought up to date (build.cmd has already updated MSYS2 itself)
quiet pacman -Sy --noconfirm
missing=()
for p in "${BUILD[@]}" "${RUNTIME[@]}"; do
  pacman -S --needed --noconfirm "$p" >> "$LOG" 2>&1 || missing+=("$p")
done
[ ${#missing[@]} -eq 0 ] || die "MSYS2 has no package named: ${missing[*]}"
have_opt=()
for p in "${OPTIONAL[@]}"; do
  if pacman -S --needed --noconfirm "$p" >> "$LOG" 2>&1; then have_opt+=("$p"); else echo "  (no $p in MSYS2: going without it)"; fi
done
# pure-Python modules MSYS2 may not package: from PyPI, into the runtime
for m in enchant:pyenchant mutagen:mutagen; do
  python -c "import ${m%%:*}" 2>/dev/null || quiet python -m pip install --break-system-packages --no-warn-script-location "${m#*:}"
done

# ---------------------------------------------------------------- the apps' code
step "The apps' code"
fetch() {   # repository, branch, folder
  if [ "${FOLIO_LOCAL:-}" = 1 ] && [ -d "$SRC/$3" ]; then return; fi
  if [ -d "$SRC/$3/.git" ]; then
    quiet git -C "$SRC/$3" fetch --depth 1 origin "$2"
    quiet git -C "$SRC/$3" checkout -q -B "$2" FETCH_HEAD
  else
    quiet git clone -q --depth 1 -b "$2" "https://github.com/Akeilan/$1" "$SRC/$3"
  fi
  echo "  $3 $(git -C "$SRC/$3" log -1 --format='%h %cs')"
}
fetch folio-writer master page
fetch folio-sheets master sheet
fetch FolioDeliver master show
fetch folio-cork main draw
fetch folio-gable claude/backup gable
fetch folio-chord main chord
fetch folio-reel main reel

# ---------------------------------------------------------------- the engines (Rust, loaded by Python)
PYO3_PYTHON="$(cygpath -w "$(command -v python)")"
export PYO3_PYTHON
# the engines' PyO3 (0.22) knows Python up to 3.13; with a newer one it builds against the stable
# interface instead, which it has to be told it may do
pyver="$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
echo "  Python $pyver"
if python -c 'import sys; sys.exit(0 if sys.version_info[:2] > (3, 13) else 1)'; then
  export PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1
  echo "  (newer than the engines' PyO3 knows: building them against Python's stable interface)"
fi
engine() {   # name, source folder, cargo features, the module's name
  step "$1's engine"
  local b="$WORK/engines/$1"
  rm -rf "$b"; mkdir -p "$b"
  cp -r "$2/." "$b/"
  # the Linux build links Python's stable interface (abi3); MSYS2's Python is linked by name here
  sed -i 's/"abi3-py310", *//; s/, *"abi3-py310"//' "$b/Cargo.toml"
  (cd "$b" && FOLIO_WIN_LIBDIR="$(cygpath -w "$MINGW_PREFIX/lib")" cargo build --release --features "$3" >> "$LOG" 2>&1) \
    || die "$1's engine didn't build"
  local dll="$b/target/release/$4.dll"
  [ -f "$dll" ] || dll="$b/target/release/lib$4.dll"
  [ -f "$dll" ] || die "$1's engine built, but $4.dll isn't there"
  ENGINE_DLL="$dll"
}
engine Page "$SRC/page/core" python folio_core;            PAGE_PYD="$ENGINE_DLL"
engine Sheet "$SRC/sheet/engine" python folio_sheets_core; SHEET_PYD="$ENGINE_DLL"
# Show's engine uses the copy of Page's engine beside it (vendor/), so the whole tree goes
step "Show's engine"
rm -rf "$WORK/engines/show"; mkdir -p "$WORK/engines/show"
cp -r "$SRC/show/engine" "$SRC/show/vendor" "$WORK/engines/show/"
sed -i 's/"abi3-py310", *//; s/, *"abi3-py310"//' "$WORK/engines/show/engine/Cargo.toml"
(cd "$WORK/engines/show/engine" && cargo build --release --features python >> "$LOG" 2>&1) || die "Show's engine didn't build"
SHOW_PYD="$(ls "$WORK/engines/show/engine/target/release/"*deliver_core.dll | head -1)"

# ---------------------------------------------------------------- Draw and Gable (native programs)
step "Folio Draw"
(cd "$SRC/draw" && CARGO_TARGET_DIR="$WORK/draw-target" cargo build --release -p folio-draw >> "$LOG" 2>&1) || die "Folio Draw didn't build"
step "Folio Gable"
rm -rf "$WORK/gable"
quiet cmake -S "$SRC/gable" -B "$WORK/gable" -G Ninja -DCMAKE_BUILD_TYPE=Release
quiet cmake --build "$WORK/gable"

# ---------------------------------------------------------------- launchers
step "Launchers"
mkdir -p "$WORK/launchers"
launcher() {   # exe, app name, icon, then the defines that say what it starts
  local exe="$1" name="$2" ico="$3"; shift 3
  printf '1 ICON "%s"\n' "$(cygpath -m "$HERE/icons/$ico")" > "$WORK/launchers/$exe.rc"
  quiet windres "$WORK/launchers/$exe.rc" -O coff -o "$WORK/launchers/$exe.res"
  local sub=-mwindows
  case " $* " in *" -DAPP_CONSOLE=1 "*) sub=-mconsole ;; esac
  quiet gcc -O2 -s -municode "$sub" -DAPP_NAME="\"$name\"" "$@" "$HERE/launcher.c" "$WORK/launchers/$exe.res" -o "$WORK/launchers/$exe"
}
py() { echo -DAPP_PYMOD="\"$1\"" -DAPP_PYPATH="\"apps\\\\$2\""; }
# shellcheck disable=SC2046
{
launcher FolioPage.exe "Folio Page" folio-page.ico $(py folio page)
launcher FolioSheet.exe "Folio Sheet" folio-sheet.ico $(py folio_sheets sheet)
launcher FolioShow.exe "Folio Show" folio-show.ico $(py folio_deliver show)
launcher FolioChord.exe "Folio Chord" folio-chord.ico $(py folio_chord chord)
launcher FolioReel.exe "Folio Reel" folio-reel.ico $(py folio_reel reel)
launcher FolioDraw.exe "Folio Draw" folio-draw.ico -DAPP_EXE="\"bin\\\\folio-draw.exe\""
launcher FolioGable.exe "Folio Gable" folio-gable.ico -DAPP_EXE="\"bin\\\\folio-gable.exe\""
# the commands the apps start each other by (Show hands films to folio-reel, and so on)
for a in page:folio:page sheet:folio_sheets:sheet show:folio_deliver:show chord:folio_chord:chord reel:folio_reel:reel; do
  IFS=: read -r n m d <<< "$a"
  launcher "folio-$n.exe" "Folio ${n^}" "folio-$n.ico" $(py "$m" "$d") -DAPP_CONSOLE=1
done
}

# ---------------------------------------------------------------- the installation folder
step "Putting it together"
rm -rf "$TREE"; mkdir -p "$TREE"/{bin,apps,share,lib/python}
FOLIO_POSIX_PREFIX="$MINGW_PREFIX" FOLIO_WIN_PREFIX="$(cygpath -m "$MINGW_PREFIX")" \
  python "$HERE/stage.py" runtime "$TREE/runtime" "${RUNTIME[@]}" "${have_opt[@]}" | tee -a "$LOG"
cp "$WORK"/launchers/*.exe "$TREE/bin/"
cp "$HERE/files/folio-env.txt" "$TREE/bin/"
cp "$HERE/files/sitecustomize.py" "$TREE/lib/python/"
cp "$WORK/draw-target/release/folio-draw.exe" "$TREE/bin/"
cp "$WORK/gable/folio-gable.exe" "$TREE/bin/"
# Python apps: their code, and the engine beside it as a Python module (.pyd)
app() {   # folder, package path, share source, share name
  mkdir -p "$TREE/apps/$1"
  cp -r "$2" "$TREE/apps/$1/"
  find "$TREE/apps/$1" -name __pycache__ -prune -exec rm -rf {} +
  if [ -n "$3" ]; then mkdir -p "$TREE/share/$4"; cp -r "$3/." "$TREE/share/$4/"; fi
}
app page "$SRC/page/app/folio" "$SRC/page/share" folio-page
cp "$PAGE_PYD" "$TREE/apps/page/folio_core.pyd"
app sheet "$SRC/sheet/app/folio_sheets" "$SRC/sheet/packaging/root/usr/share/folio-sheet" folio-sheet
cp "$SHEET_PYD" "$TREE/apps/sheet/folio_sheets_core.pyd"
app show "$SRC/show/app/folio_deliver" "$SRC/show/share" folio-show
cp "$SHOW_PYD" "$TREE/apps/show/deliver_core.pyd"
app chord "$SRC/chord/app/folio_chord" "$SRC/chord/share" folio-chord
app reel "$SRC/reel/app/folio_reel" "$SRC/reel/share" folio-reel
# fonts, dictionaries, icons
mkdir -p "$TREE/share/folio/fonts" "$TREE/share/folio/icons"
cp "$HERE"/fonts/* "$TREE/share/folio/fonts/"
cp "$HERE"/icons/*.ico "$TREE/share/folio/icons/"
for d in hunspell hyphen mythes; do
  mkdir -p "$TREE/share/$d"; cp "$HERE/dicts/$d/"* "$TREE/share/$d/"
done
mkdir -p "$TREE/runtime/share/enchant-2/hunspell" "$TREE/runtime/share/hunspell"
cp "$HERE"/dicts/hunspell/* "$TREE/runtime/share/enchant-2/hunspell/"
cp -n "$HERE"/dicts/hunspell/* "$TREE/runtime/share/hunspell/" 2>/dev/null || true
cp "$HERE"/dicts/COPYING-* "$STUDIO/LICENSE" "$TREE/share/folio/"
# Qt finds its plug-ins beside itself; the runtime keeps them under share\qt6
printf '[Paths]\nPrefix = ../runtime\nPlugins = share/qt6/plugins\n' > "$TREE/bin/qt.conf"

# ---------------------------------------------------------------- the MSI
step "The MSI"
python "$HERE/stage.py" msi "$TREE" "$WORK/FolioStudio-$VERSION-x64.msi" "$VERSION" | tee -a "$LOG"
cp "$WORK/FolioStudio-$VERSION-x64.msi" "$OUT/"
echo
echo "Made $(cygpath -w "$OUT/FolioStudio-$VERSION-x64.msi")"
echo "Install it, then run windows\\test.cmd to check it."
