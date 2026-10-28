#!/bin/sh
# Installs (or updates) the Folio Suite from the repository next to this script.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/var/lib/folio-suite/repo
KEY=/usr/share/keyrings/folio-suite-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/folio-suite.list
if [ "$1" = "--remove" ]; then
  for p in folio-suite folio-writer folio-sheets folio-deliver folio-post folio-draw folio-gable; do
    dpkg -s "$p" >/dev/null 2>&1 && apt-get -y purge "$p" || true
  done
  rm -f "$LIST" "$KEY"
  rm -rf /var/lib/folio-suite
  apt-get update -qq || true
  echo "Folio Suite removed."
  exit 0
fi
echo "Setting up the Folio Suite repository..."
mkdir -p /var/lib/folio-suite
rm -rf "$REPO.new"
cp -r "$HERE/repo" "$REPO.new"
rm -rf "$REPO"
mv "$REPO.new" "$REPO"
chmod -R a+rX /var/lib/folio-suite
install -m 644 "$HERE/folio-suite-archive-keyring.gpg" "$KEY"
echo "deb [signed-by=$KEY] file:$REPO ./" > "$LIST"
if ! command -v gpgv >/dev/null 2>&1 && ! command -v gpgv2 >/dev/null 2>&1; then
  echo "The package signature checker (gpgv) is missing: sudo apt install gpgv, then run this again." >&2
  exit 1
fi
apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -qq
if [ "$1" = "--repo-only" ]; then
  echo "Repository updated; the Software Updater will offer the new versions."
  exit 0
fi
echo "Installing..."
# X2-03: no LibreOffice unless asked for. The apps read and write their own formats natively;
# --old-formats adds LibreOffice's converter (no window of its own) for .doc, .xls, .ppt and
# OpenDocument files the apps don't read themselves.
EXTRA=""
for a in "$@"; do
  [ "$a" = "--old-formats" ] && EXTRA="libreoffice-writer-nogui libreoffice-calc-nogui libreoffice-impress-nogui"
done
DEBIAN_FRONTEND=noninteractive apt-get install -y -o APT::Install-Suggests=0 folio-suite $EXTRA
echo "Folio Suite installed: Writer, Sheets, Deliver, Post, Draw and Gable are in the app menu."
