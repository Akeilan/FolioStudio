#!/bin/bash
# X2-02: the code the GTK apps share lives once, in folio-suite/shared (and the theme checker in
# folio-suite/tests). This copies it into each app's tree; --check only reports copies that differ.
#   sync_shared.sh [--check]     app trees default to the folders next to folio-suite
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${FOLIO_SRC:-$(dirname "$HERE")}"
CHECK=0; [ "$1" = "--check" ] && CHECK=1
# shared file -> where it goes in each app
declare -A RIBBON=(
  [folio-writer]=app/folio/ribbon.py
  [folio-sheets]=app/folio_sheets/ribbon.py
  [folio-deliver]=app/folio_deliver/ribbon.py
  [foliopost]=app/folio_post/ribbon.py
  [folio-draw]=folio_draw/suiteribbon.py
)
declare -A PKG=(
  [folio-writer]=app/folio
  [folio-sheets]=app/folio_sheets
  [folio-deliver]=app/folio_deliver
  [foliopost]=app/folio_post
  [folio-draw]=folio_draw
)
bad=0
put() {  # src dst
  if [ $CHECK = 1 ]; then
    if ! cmp -s "$1" "$2"; then echo "differs: $2"; bad=1; fi
  else
    cp "$1" "$2"
  fi
}
for app in "${!RIBBON[@]}"; do
  [ -d "$ROOT/$app" ] && put "$HERE/shared/ribbon.py" "$ROOT/$app/${RIBBON[$app]}"
done
# X3-03: KeyTips, ScreenTips and light/dark detection, one copy for the apps that share the ribbon
for app in folio-writer folio-sheets folio-deliver foliopost; do
  [ -d "$ROOT/$app" ] || continue
  put "$HERE/shared/keytips.py" "$ROOT/$app/${PKG[$app]}/keytips.py"
  put "$HERE/shared/screentips.py" "$ROOT/$app/${PKG[$app]}/screentips.py"
done
for app in folio-sheets folio-deliver foliopost folio-draw; do
  [ -d "$ROOT/$app" ] || continue
  put "$HERE/shared/appearance.py" "$ROOT/$app/${PKG[$app]}/appearance.py"
done
for app in "${!PKG[@]}"; do
  [ -d "$ROOT/$app" ] || continue
  put "$HERE/shared/fontfix.py" "$ROOT/$app/${PKG[$app]}/fontfix.py"
  [ -f "$ROOT/$app/tests/themecheck.py" ] && put "$HERE/tests/themecheck.py" "$ROOT/$app/tests/themecheck.py"
done
if [ $CHECK = 1 ]; then
  [ $bad = 0 ] && echo "shared code: every app has the current copy"
  exit $bad
fi
echo "shared code copied into the apps"
