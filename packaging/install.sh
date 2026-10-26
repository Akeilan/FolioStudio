#!/bin/sh
# Installs (or updates) the Folio Suite from the repository next to this script.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/var/lib/folio-suite/repo
KEY=/usr/share/keyrings/folio-suite-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/folio-suite.list
if [ "$1" = "--remove" ]; then
  apt-get -y purge folio-suite folio-sheets folio-draw folio-gable folio-writer 2>/dev/null || \
    apt-get -y purge folio-suite folio-sheets folio-draw folio-gable
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
apt-get update -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -qq
if [ "$1" = "--repo-only" ]; then
  echo "Repository updated; the Software Updater will offer the new versions."
  exit 0
fi
echo "Installing..."
DEBIAN_FRONTEND=noninteractive apt-get install -y folio-suite folio-sheets folio-draw folio-gable
echo "Folio Suite installed: Sheets, Draw and Gable are in the app menu."
