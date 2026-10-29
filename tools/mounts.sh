#!/bin/bash
for r in /srv/jammy /srv/nolo /srv/noble; do
  mountpoint -q $r/proc || mount -t proc proc $r/proc
  mountpoint -q $r/dev || mount --bind /dev $r/dev
  mkdir -p $r/tmp/.X11-unix; mountpoint -q $r/tmp/.X11-unix || mount --bind /tmp/.X11-unix $r/tmp/.X11-unix
done
pgrep -x Xvfb >/dev/null || (setsid Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 &)
sleep 0.5
