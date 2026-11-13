#!/bin/bash
# X4-05: hold a candidate .deb up against the app it replaces, and refuse a release that would show
# a person less than the version it is replacing.
#
#   tools/compare-release.sh <package> <the source tree of the app> <candidate.deb> [<the deb it replaces>]
#
# With no fourth argument the currently published package is used: that is what "the app it
# replaces" means, since it is what an upgrade overwrites.
#
# Each is installed in turn on 22.04 and asked to write down everything it shows. tests/surface.py
# walks the real widget tree, so a ribbon, a menu bar, a toolbar and a side pane all count alike,
# and it adds the ribbon tabs and groups (built before they are ever shown) and every command
# the window answers to. Anything the published app showed and the candidate does not is a failure.
# packaging/surface-allow/<package>.txt is where a deliberate removal is written down, with a reason.
#
# This is the check that was missing when Studio 1.13.0 promoted a Chord with no menu bar at all
# past fourteen green suites: every one of those suites was written for the rewrite.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${1:?package name, e.g. folio-reel}"
SRC="${2:?the source tree of the app}"
NEW="${3:?the candidate .deb}"
OLD="${4:-}"
M=${MACHINE:-/srv/jammy}
XD=${XD:-96}
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC/tests/run_installed.sh" ] || {
  echo "X4-05: $PKG has no tests/run_installed.sh, so it cannot be driven; skipped." >&2; exit 0; }

if [ -z "$OLD" ]; then
  PUB="${FOLIO_PUBLISHED:-}"
  if [ -z "$PUB" ]; then
    PUB="$WORK/published"
    git clone -q --depth 1 --branch gh-pages \
      "${FOLIO_STUDIO_PAGES_REMOTE:-https://github.com/Akeilan/FolioStudio}" "$PUB" >/dev/null 2>&1 || true
  fi
  OLD="$(ls "$PUB"/${PKG}_*.deb 2>/dev/null | head -1)"
fi
[ -n "$OLD" ] && [ -f "$OLD" ] || {
  echo "X4-05: nothing published to compare $PKG with yet, so this is its first release."; exit 0; }
echo "X4-05: $(basename "$NEW") against $(basename "$OLD")"

pgrep -x Xvfb -a | grep -q ":$XD " || {
  rm -f /tmp/.X$XD-lock /tmp/.X11-unix/X$XD
  setsid -f Xvfb :$XD -screen 0 1600x1000x24 -nolisten tcp </dev/null >/dev/null 2>&1; sleep 1; }

dump() {   # dump <deb> <out.json> <source tree to drive it with>
  local deb="$1" out="$2" src="$3"
  local want
  want="$(dpkg-deb -f "$deb" Version 2>/dev/null)"
  [ -n "$want" ] || { echo "X4-05: $deb is not a package" >&2; return 2; }
  rm -rf "$M/tmp/surface"; mkdir -p "$M/tmp/surface/t"
  cp -r "$src"/tests/* "$M/tmp/surface/t/" 2>/dev/null
  cp "$HERE/tests/surface.py" "$M/tmp/surface/t/surface.py"
  cp "$deb" "$M/tmp/surface/pkg.deb" || return 2
  if ! flock /home/claude/.dpkg.lock chroot "$M" bash -c \
      "DEBIAN_FRONTEND=noninteractive apt-get install -y -q --allow-downgrades /tmp/surface/pkg.deb \
       >/tmp/surface/install.log 2>&1"; then
    echo "X4-05: $(basename "$deb") would not install:" >&2
    tail -4 "$M/tmp/surface/install.log" >&2
    return 2
  fi
  # the surface must come from the package being tested: a failed install leaves the one before it
  # in place, and comparing an app with itself passes every time (which is the whole fault this
  # check exists to catch)
  local got
  got="$(chroot "$M" dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null)"
  [ "$got" = "$want" ] || {
    echo "X4-05: wanted $PKG $want installed, found '${got:-nothing}'" >&2; return 2; }
  rm -f "$M/tmp/surface/out.json"
  chroot "$M" bash -c "cd /tmp/surface/t && SURFACE_APP='$PKG $want' SURFACE_OUT=/tmp/surface/out.json \
     DISPLAY=:$XD UI_TIMEOUT=${SURFACE_TIMEOUT:-240} sh run_installed.sh /tmp/surface/t/surface.py" \
     2>&1 | grep -E "^surface:|Traceback" | head -3
  [ -s "$M/tmp/surface/out.json" ] || { echo "X4-05: $PKG $want wrote down no surface" >&2; return 2; }
  cp "$M/tmp/surface/out.json" "$out"
}

OLD_SRC="${OLD_SRC:-$SRC}"
dump "$OLD" "$WORK/before.json" "$OLD_SRC" || { echo "X4-05: could not read the surface of the published app"; exit 2; }
dump "$NEW" "$WORK/after.json" "$SRC"      || { echo "X4-05: could not read the surface of the candidate"; exit 2; }
ALLOW="$HERE/packaging/surface-allow/$PKG.txt"
if [ -f "$ALLOW" ]; then
  python3 "$HERE/tools/compare-surface.py" "$WORK/before.json" "$WORK/after.json" --allow "$ALLOW"
else
  python3 "$HERE/tools/compare-surface.py" "$WORK/before.json" "$WORK/after.json"
fi
