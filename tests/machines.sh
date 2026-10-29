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
  for app in folio-writer folio-sheets folio-deliver foliopost folio-draw gable; do
    [ -d "$SRC/$app/tests" ] && { mkdir -p $m/tmp/folio-src/$app; cp -r "$SRC/$app/tests" $m/tmp/folio-src/$app/; }
  done
  cp -r "$HERE" $m/tmp/folio-src/folio-suite
  echo "== $m"
  chroot $m env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root DISPLAY=$D \
    WRITER_SRC=/tmp/folio-src/folio-writer SHEETS_SRC=/tmp/folio-src/folio-sheets DELIVER_SRC=/tmp/folio-src/folio-deliver \
    POST_SRC=/tmp/folio-src/foliopost DRAW_SRC=/tmp/folio-src/folio-draw GABLE_SRC=/tmp/folio-src/gable \
    bash /tmp/folio-src/folio-suite/run-tests.sh "$@" || rc=1
done
exit $rc
