#!/bin/bash
# Publishes the signed Folio Studio repository (the "site" folder build-suite.sh makes) to the
# gh-pages branch of the FolioStudio repository, which GitHub Pages serves at
# https://akeilan.github.io/FolioStudio/. The branch is replaced each time, so it only ever holds
# the current packages.
#
#   tools/publish.sh <build output folder>      (the folder holding site/)
set -euo pipefail
SITE="$(cd "$1/site" && pwd)"
REMOTE="${FOLIO_STUDIO_PAGES_REMOTE:-https://github.com/Akeilan/FolioStudio}"
[ -f "$SITE/InRelease" ] && [ -f "$SITE/Packages" ] || { echo "no signed repository in $SITE" >&2; exit 1; }
VER="$(awk '/^Version:/ {print $2; exit}' "$SITE/Release")"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cp -r "$SITE/." "$W/"
touch "$W/.nojekyll"
{
  echo '<!doctype html><meta charset="utf-8"><title>Folio Studio packages</title>'
  echo "<p>Folio Studio $VER package source. Run the Folio Studio installer to add it.</p><ul>"
  for f in "$W"/*.deb; do b="$(basename "$f")"; echo "<li>$b</li>"; done
  echo "</ul>"
} > "$W/index.html"
cd "$W"
git init -q -b gh-pages
git add -A
git -c user.name=Folio -c user.email=folio@localhost commit -qm "Folio Studio $VER packages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L7oDhePMuTSzKAPokorihB"
timeout 900 git push -q -f "$REMOTE" gh-pages:refs/heads/gh-pages
echo "Published Folio Studio $VER: $(git ls-remote "$REMOTE" gh-pages | cut -c1-12)"
