#!/bin/bash
# Copy and paste between the apps, each a separate program as a person would use them:
# Gable's view -> Draw -> Sheets, then a Sheets range out as an HTML table.
# Uses the installed apps unless GABLE_BIN / DRAW_PYTHONPATH / SHEETS_PYTHONPATH say otherwise.
HERE="$(cd "$(dirname "$0")" && pwd)"
EX="$(mktemp -d)"
trap 'rm -rf "$EX"' EXIT
GABLE_BIN="${GABLE_BIN:-folio-gable}"
SHEETS_PP="${SHEETS_PYTHONPATH:-/usr/lib/folio-sheet}"; [ -d "$SHEETS_PP" ] || SHEETS_PP=/usr/lib/folio-sheets
GABLE_CLIP_SERVE="$EX" AUDIT_ONLY=copyview timeout 180 "$GABLE_BIN" --audit > "$EX/gable.log" 2>&1 &
G=$!
PYTHONPATH="${DRAW_PYTHONPATH:-}" timeout 180 python3 "$HERE/clip_draw.py" "$EX" > "$EX/draw.log" 2>&1 &
D=$!
CLIP_EXCHANGE="$EX" FOLIO_TEST_SCRIPT="$HERE/clip_sheets.py" PYTHONPATH="$SHEETS_PP" timeout 180 python3 -m folio_sheets > "$EX/sheets.log" 2>&1
S=$?
wait $D; DR=$?
wait $G; GR=$?
grep -hE "^(PASS|FAIL)" "$EX/gable.log" "$EX/draw.log" "$EX/sheets.log" | sed 's/^/  /'
grep -h "passed, " "$EX/gable.log" | sed 's/^/  gable: /'
[ $GR -eq 0 ] && [ $DR -eq 0 ] && [ $S -eq 0 ]
