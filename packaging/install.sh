#!/bin/sh
# Installs (or updates) Folio Studio — formerly Folio Suite — from the repository next to this
# script. An existing Folio Suite install is moved over: its repository, source list and key are
# replaced by Folio Studio's, and the apps' old package names become transitional packages.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/var/lib/folio-studio
KEY=/usr/share/keyrings/folio-studio-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/folio-studio.list
OLD_REPO=/var/lib/folio-suite
OLD_KEY=/usr/share/keyrings/folio-suite-archive-keyring.gpg
OLD_LIST=/etc/apt/sources.list.d/folio-suite.list
if [ "$1" = "--remove" ]; then
  for p in folio-studio folio-suite folio-page folio-writer folio-sheet folio-sheets folio-show folio-deliver \
           folio-post folio-draw folio-gable folio-chord; do
    dpkg -s "$p" >/dev/null 2>&1 && apt-get -y purge "$p" || true
  done
  rm -f "$LIST" "$KEY" "$OLD_LIST" "$OLD_KEY"
  rm -rf /var/lib/folio-studio "$OLD_REPO"
  apt-get update -qq || true
  echo "Folio Studio removed."
  exit 0
fi
# Where updates come from: the online package source (published with each release), so the
# Software Updater offers new versions without another installer. The installer's own copy
# installs this version, so installing works offline too. FOLIO_STUDIO_SOURCE overrides the
# address (tests); "local" keeps the old on-disk repository only.
SOURCE="${FOLIO_STUDIO_SOURCE:-$(cat "$HERE/source-url" 2>/dev/null || echo local)}"
echo "Setting up the Folio Studio repository..."
if ! command -v gpgv >/dev/null 2>&1 && ! command -v gpgv2 >/dev/null 2>&1; then
  echo "The package signature checker (gpgv) is missing: sudo apt install gpgv, then run this again." >&2
  exit 1
fi
mkdir -p /var/lib/folio-studio
rm -rf "$REPO.new"
cp -r "$HERE/repo" "$REPO.new"
rm -rf "$REPO"
mv "$REPO.new" "$REPO"
chmod -R a+rX /var/lib/folio-studio
install -m 644 "$HERE/folio-studio-archive-keyring.gpg" "$KEY"
# the Folio Suite repository this replaces
if [ -f "$OLD_LIST" ] || [ -d "$OLD_REPO" ]; then
  rm -f "$OLD_LIST" "$OLD_KEY"
  rm -rf "$OLD_REPO"
fi
# first this installer's own copy, then (below) the online source
echo "deb [signed-by=$KEY] file:$REPO ./" > "$LIST"
apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -qq
online() {
  [ "$SOURCE" = local ] && return 0
  echo "deb [signed-by=$KEY] $SOURCE ./" > "$LIST"
  if apt-get update --error-on=any -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -qq; then
    rm -rf "$REPO"
    echo "Updates now come from $SOURCE through the Software Updater."
  else
    # offline: keep the local copy as well, so apt still finds what is installed
    { echo "deb [signed-by=$KEY] $SOURCE ./"; echo "deb [signed-by=$KEY] file:$REPO ./"; } > "$LIST"
    echo "Couldn't reach $SOURCE now; the Software Updater will use it once you're online." >&2
  fi
}
if [ "$1" = "--repo-only" ]; then
  online
  echo "Repository updated; the Software Updater will offer the new versions."
  exit 0
fi
echo "Installing..."
# X2-03: no LibreOffice unless asked for. The apps read and write their own formats natively;
# --old-formats adds LibreOffice's converter (no window of its own) for files the apps don't
# read themselves.
EXTRA=""
for a in "$@"; do
  [ "$a" = "--old-formats" ] && EXTRA="libreoffice-writer-nogui libreoffice-calc-nogui libreoffice-impress-nogui"
done
# an upgrade from Folio Suite: the transitional packages for the old names come along
UPGRADE=""
for p in folio-suite folio-writer folio-sheets folio-deliver; do
  dpkg -s "$p" >/dev/null 2>&1 && UPGRADE="$UPGRADE $p"
done
DEBIAN_FRONTEND=noninteractive apt-get install -y -o APT::Install-Suggests=0 folio-studio $UPGRADE $EXTRA
online
echo "Folio Studio installed: Page, Sheet, Show, Post, Draw, Gable and Chord are in the app menu."
