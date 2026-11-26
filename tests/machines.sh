#!/bin/bash
# The test machines used for releases: run-tests.sh (installed apps) inside each root —
# Ubuntu 22.04 (Zorin 17), 22.04 without LibreOffice, 24.04 (Zorin 18).
#   tests/machines.sh [--only LIST] [--quick]      roots: $MACHINES (default the three below)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${FOLIO_SRC:-$(dirname "$HERE")}"
MACHINES="${MACHINES:-/srv/jammy /srv/nolo /srv/noble}"
D="${TEST_DISPLAY:-:94}"
rc=0
for m in $MACHINES; do
  for x in proc dev tmp/.X11-unix; do mkdir -p $m/$x; mountpoint -q $m/$x || mount --bind /$x $m/$x; done
  rm -rf $m/tmp/folio-src; mkdir -p $m/tmp/folio-src
  # each app's tests, under the name run-tests.sh looks for (the trees' own folder names vary)
  for pair in folio-writer:folio-writer folio-sheets:folio-sheets foliodeliver:folio-deliver folio-gable:gable \
              folio-chord:folio-chord folio-reel:folio-reel; do
    from=${pair%%:*} to=${pair#*:}
    [ -d "$SRC/$from/tests" ] && { mkdir -p $m/tmp/folio-src/$to; cp -r "$SRC/$from/tests" $m/tmp/folio-src/$to/; }
  done
  cp -r "$HERE" $m/tmp/folio-src/folio-suite
  echo "== $m"
  chroot $m env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root DISPLAY=$D \
    WRITER_SRC=/tmp/folio-src/folio-writer SHEETS_SRC=/tmp/folio-src/folio-sheets DELIVER_SRC=/tmp/folio-src/folio-deliver \
    GABLE_SRC=/tmp/folio-src/gable CHORD_SRC=/tmp/folio-src/folio-chord REEL_SRC=/tmp/folio-src/folio-reel \
    bash /tmp/folio-src/folio-suite/run-tests.sh "$@" || rc=1
done
exit $rc
