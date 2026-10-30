#!/bin/bash
# One command for every Folio app's tests.
#
#   ./run-tests.sh            test the installed apps (Page, Sheet, Show, Post, Draw, Gable, Chord) with the test
#                             scripts from their source trees, then copy and paste between them
#   ./run-tests.sh --source   test the source trees instead (built engines needed), including
#                             the engines' own unit tests
#   --quick                   Gable's audit without the click-everything pass
#   --only writer,sheets,deliver,post,draw,gable,chord,suite   a subset
#
# Source trees: $WRITER_SRC, $SHEETS_SRC, $DELIVER_SRC, $POST_SRC, $DRAW_SRC, $GABLE_SRC, $CHORD_SRC (default
# ~/src/folio-writer, ~/src/folio-sheets, ~/src/folio-deliver, ~/src/foliopost, ~/src/folio-draw, ~/src/gable, ~/src/folio-chord). Needs a display; without one an Xvfb is started (sudo apt install xvfb).
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE=0; QUICK=0; ONLY="writer,sheets,deliver,post,draw,gable,chord,suite"
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE=1 ;;
    --quick) QUICK=1 ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
WRITER_SRC="${WRITER_SRC:-$HOME/src/folio-writer}"
SHEETS_SRC="${SHEETS_SRC:-$HOME/src/folio-sheets}"
DELIVER_SRC="${DELIVER_SRC:-$HOME/src/folio-deliver}"
POST_SRC="${POST_SRC:-$HOME/src/foliopost}"
DRAW_SRC="${DRAW_SRC:-$HOME/src/folio-draw}"
GABLE_SRC="${GABLE_SRC:-$HOME/src/gable}"
CHORD_SRC="${CHORD_SRC:-$HOME/src/folio-chord}"
want() { [[ ",$ONLY," == *",$1,"* ]]; }

if [ -z "$DISPLAY" ]; then
  if command -v Xvfb >/dev/null; then
    export DISPLAY=:91
    Xvfb :91 -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 &
    XPID=$!
    trap 'kill $XPID 2>/dev/null' EXIT
    sleep 1
  else
    echo "No display and no Xvfb: run under a desktop session or install xvfb." >&2
    exit 2
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ -n "$XPID" ] && kill $XPID 2>/dev/null' EXIT
ROWS=()
FAILED=0
row() {   # name checks failed
  ROWS+=("$(printf '%-34s %8s %8s' "$1" "$2" "$3")")
  if [ "$3" != "0" ]; then FAILED=1; fi
}
# "N checks, M failed" / "N passed, M failed" / cargo "test result: ok. N passed; M failed"
counts() {
  local out="$1" n f
  n=$(echo "$out" | grep -oE '([0-9]+) checks, ([0-9]+) failed' | tail -1 | awk '{print $1}')
  f=$(echo "$out" | grep -oE '([0-9]+) checks, ([0-9]+) failed' | tail -1 | awk '{print $3}')
  if [ -z "$n" ]; then
    n=$(echo "$out" | grep -oE '^([0-9]+) passed, ([0-9]+) failed' | tail -1 | awk '{print $1}')
    f=$(echo "$out" | grep -oE '^([0-9]+) passed, ([0-9]+) failed' | tail -1 | awk '{print $3}')
  fi
  if [ -z "$n" ]; then
    n=$(echo "$out" | grep -oE 'test result: [a-zA-Z]+\. [0-9]+ passed; [0-9]+ failed' | awk '{s+=$4; t+=$6} END {if (NR) print s, t}')
    f=${n#* }; n=${n% *}
  fi
  echo "${n:-?} ${f:-?}"
}
run() {   # name, then the command
  local name="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  set -- $(counts "$out")
  local n=$1 f=$2
  if [ "$f" = "?" ] || { [ $rc -ne 0 ] && [ "$f" = "0" ]; }; then f="error"; fi
  row "$name" "$n" "$f"
  if [ "$f" != "0" ]; then echo "$out" | grep -E '^(FAIL|  FAIL)|Traceback|Error' | head -8 | sed "s/^/  [$name] /" >&2; fi
}

echo "Folio suite tests ($([ $SOURCE = 1 ] && echo "source trees" || echo "installed apps")), display $DISPLAY"

# ---------------------------------------------------------------- Page (formerly Writer)
if want writer; then
  if [ $SOURCE = 1 ]; then
    run "Page engine (Rust)" bash -c "cd '$WRITER_SRC/core' && cargo test --release --lib"
    WCMD="env FOLIO_SHARE=$WRITER_SRC/share PYTHONPATH=$WRITER_SRC/app python3 -m folio"
  else
    WCMD="$(command -v folio-page || command -v folio-writer)"
  fi
  for t in "$WRITER_SRC"/tests/native/n*.py; do
    [ -f "$t" ] || continue
    rm -f /tmp/ftest.log
    (cd "$WORK" && FOLIO_ENGINE=native FOLIO_WRITER_TESTS="$WRITER_SRC/tests" FOLIO_TEST_SCRIPT="$t" timeout 300 $WCMD >/dev/null 2>&1); rc=$?
    n=$(grep -cE '^(PASS|FAIL)' /tmp/ftest.log 2>/dev/null); f=$(grep -cE '^(FAIL|ERROR)' /tmp/ftest.log 2>/dev/null)
    [ $rc -ne 0 ] && [ "${f:-0}" = "0" ] && f="error"
    row "Page $(basename "$t" .py)" "${n:-0}" "${f:-error}"
    [ "$f" != "0" ] && grep -E '^(FAIL|ERROR)' /tmp/ftest.log 2>/dev/null | head -5 | sed "s/^/  [Page $(basename "$t" .py)] /" >&2
  done
fi

# ---------------------------------------------------------------- Show (formerly Deliver) and Post (UI scripts print ok / FAIL lines)
ui_app() {  # label, runner script, test dir, scripts...
  local label="$1" runner="$2" dir="$3"; shift 3
  for u in "$@"; do
    [ -f "$dir/$u" ] || continue
    out=$(cd "$WORK" && UI_TIMEOUT=600 sh "$runner" "$dir/$u" 2>&1); rc=$?
    n=$(echo "$out" | grep -cE '^(ok|FAIL) '); f=$(echo "$out" | grep -cE '^FAIL ')
    echo "$out" | grep -q "Traceback" && [ "$f" = "0" ] && f="error"
    [ $rc -ne 0 ] && [ "$f" = "0" ] && f="error"
    row "$label ${u%.py}" "$n" "$f"
    [ "$f" != "0" ] && echo "$out" | grep -E '^FAIL|Traceback' | head -5 | sed "s/^/  [$label ${u%.py}] /" >&2
  done
}
if want deliver; then
  if [ $SOURCE = 1 ]; then R="$DELIVER_SRC/tests/run_ui.sh"; else R="$DELIVER_SRC/tests/run_installed.sh"; fi
  ui_app Show "$R" "$DELIVER_SRC/tests" ui_basic.py ui_more.py ui_anim.py ui_review.py ui_master.py ui_show2.py ui_objects.py ui_media.py ui_theme.py
fi
if want post; then
  if [ $SOURCE = 1 ]; then R="$POST_SRC/tests/run_ui.sh"; else R="$POST_SRC/tests/run_installed.sh"; fi
  ui_app Post "$R" "$POST_SRC/tests" ui_mail.py ui_editor.py ui_writered.py ui_attach.py ui_calendar.py ui_people.py ui_tasks.py ui_folders.py ui_pgp.py ui_smime.py
fi

if want chord; then
  if [ $SOURCE = 1 ]; then R="$CHORD_SRC/tests/run_ui.sh"; CP="$CHORD_SRC/app"; else R="$CHORD_SRC/tests/run_installed.sh"; CP=/usr/lib/folio-chord; fi
  for t in test_engine.py test_net.py; do
    [ -f "$CHORD_SRC/tests/$t" ] && run "Chord ${t%.py}" env PYTHONPATH="$CP" FOLIO_CHORD_AUDIOSINK=fakesink python3 "$CHORD_SRC/tests/$t"
  done
  ui_app Chord "$R" "$CHORD_SRC/tests" ui_library.py ui_play.py ui_net.py ui_cd.py command_walk.py
fi

# ---------------------------------------------------------------- Sheet (formerly Sheets)
if want sheets; then
  if [ $SOURCE = 1 ]; then
    PP="$SHEETS_SRC/app"
    run "Sheet engine (Rust)" bash -c "cd '$SHEETS_SRC/engine' && cargo test --no-default-features --lib"
  else
    PP=/usr/lib/folio-sheet; [ -d "$PP" ] || PP=/usr/lib/folio-sheets
  fi
  for t in "$SHEETS_SRC"/tests/*_audit.py "$SHEETS_SRC"/tests/command_walk.py; do
    [ -f "$t" ] || continue
    if [ "$(basename "$t")" = command_walk.py ]; then
      # the walk reports only callback errors
      out=$(cd "$WORK" && FOLIO_TEST_SCRIPT="$t" PYTHONPATH="$PP" timeout 600 python3 -m folio_sheets 2>&1)
      e=$(echo "$out" | grep -oE 'ERRORS IN CALLBACKS: [0-9]+' | awk '{print $4}')
      row "Sheet command_walk" "-" "${e:-error}"
      continue
    fi
    run "Sheet $(basename "$t" .py)" bash -c "cd '$WORK' && FOLIO_TEST_SCRIPT='$t' PYTHONPATH='$PP' timeout 600 python3 -m folio_sheets"
  done
fi

# ---------------------------------------------------------------- Draw
if want draw; then
  if [ $SOURCE = 1 ]; then
    run "Draw engine (Rust)" bash -c "cd '$DRAW_SRC/engine' && cargo test --release"
    DT="$DRAW_SRC"
  else
    # a copy of the tests alone, so they import the installed app
    mkdir -p "$WORK/draw"; cp -r "$DRAW_SRC/tests" "$WORK/draw/"; DT="$WORK/draw"
  fi
  for t in ui_audit deep_audit dialog_audit tools_audit theme_audit; do
    run "Draw $t" bash -c "cd '$DT' && AUDIT_OUT='$WORK/draw-out' timeout 900 python3 -u tests/$t.py"
  done
fi

# ---------------------------------------------------------------- Gable
if want gable; then
  if [ $SOURCE = 1 ]; then
    GB="$GABLE_SRC/build/folio-gable"; [ -x "$GB" ] || GB="$GABLE_SRC/build-release/folio-gable"
    GT="$(dirname "$GB")/gable_tests"
    run "Gable geometry tests" "$GT"
  else
    GB=folio-gable
  fi
  if [ $QUICK = 1 ]; then Q="AUDIT_QUICK=1"; else Q=""; fi
  run "Gable audit$([ $QUICK = 1 ] && echo ' (quick)')" env $Q timeout 2400 "$GB" --audit
fi

# ---------------------------------------------------------------- between the apps
if want suite; then
  if [ $SOURCE = 1 ]; then
    export GABLE_BIN="$GB" DRAW_PYTHONPATH="$DRAW_SRC" SHEETS_PYTHONPATH="$SHEETS_SRC/app"
  fi
  out=$(bash "$HERE/tests/clipboard_chain.sh" 2>&1); rc=$?
  n=$(echo "$out" | grep -cE '^  (PASS|FAIL)'); f=$(echo "$out" | grep -cE '^  FAIL')
  [ $rc -ne 0 ] && [ "$f" = "0" ] && f="error"
  row "Copy and paste between apps" "$n" "$f"
  [ "$f" != "0" ] && echo "$out" | grep FAIL | sed 's/^/  [clipboard] /' >&2
fi

echo
printf '%-34s %8s %8s\n' "Test" "Checks" "Failed"
printf '%s\n' "${ROWS[@]}"
echo
if [ $FAILED = 0 ]; then echo "All passed."; else echo "Some tests failed."; fi
exit $FAILED
