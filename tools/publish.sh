#!/bin/bash
# Publishes the signed Folio Studio repository (the "site" folder build-suite.sh makes) to the
# gh-pages branch of the FolioStudio repository, which GitHub Pages serves at
# https://akeilan.github.io/FolioStudio/. Each publish is an ordinary commit on top of the last:
# the branch's files are replaced by the new ones, so it only ever serves the current packages,
# and nothing is force-pushed (git keeps an unchanged .deb once, however many publishes carry it).
#
#   tools/publish.sh <build output folder>      (the folder holding site/)
set -euo pipefail
SITE="$(cd "$1/site" && pwd)"
REMOTE="${FOLIO_STUDIO_PAGES_REMOTE:-https://github.com/Akeilan/FolioStudio}"
[ -f "$SITE/InRelease" ] && [ -f "$SITE/Packages" ] || { echo "no signed repository in $SITE" >&2; exit 1; }
VER="$(awk '/^Version:/ {print $2; exit}' "$SITE/Release")"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
git clone -q --depth 1 --branch gh-pages "$REMOTE" "$W"
# the new site in place of the old: every file but git's own goes, then the new ones come in
find "$W" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$SITE/." "$W/"
touch "$W/.nojekyll"
{
  echo '<!doctype html><meta charset="utf-8"><title>Folio Studio packages</title>'
  echo "<p>Folio Studio $VER package source for Ubuntu and Zorin OS. To add it and install everything:</p><pre>"
  echo "sudo curl -fsSL -o /usr/share/keyrings/folio-studio-archive-keyring.gpg https://akeilan.github.io/FolioStudio/folio-studio-archive-keyring.gpg"
  echo "echo \"deb [signed-by=/usr/share/keyrings/folio-studio-archive-keyring.gpg] https://akeilan.github.io/FolioStudio/ ./\" | sudo tee /etc/apt/sources.list.d/folio-studio.list"
  echo "sudo apt update"
  echo "sudo apt install folio-studio</pre>"
  echo "<p>If you added this source before Folio Studio 1.20.0, the signing key has changed and"
  echo "<code>apt update</code> will report <code>NO_PUBKEY</code>. Run the first command above again"
  echo "to replace the keyring, then <code>sudo apt update</code>.</p><p>Packages:</p><ul>"
  for f in "$W"/*.deb; do b="$(basename "$f")"; echo "<li>$b</li>"; done
  echo "</ul>"
} > "$W/index.html"
cd "$W"
git add -A
git -c user.name=Folio -c user.email=folio@localhost commit -qm "Folio Studio $VER packages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L7oDhePMuTSzKAPokorihB"
timeout 900 git push -q "$REMOTE" HEAD:refs/heads/gh-pages
echo "Published Folio Studio $VER: $(git ls-remote "$REMOTE" gh-pages | cut -c1-12)"
