#!/bin/bash
# Run a command as a Wayland client: a Weston compositor shown in the X display $DISPLAY (an Xvfb),
# so the session has a real seat (keyboard and pointer) like a desktop's.   wl.sh CMD...
export XDG_RUNTIME_DIR=/tmp/wlrt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
weston --backend=x11-backend.so --socket=wayland-folio --width=1600 --height=1000 --idle-time=0 >/tmp/weston.out 2>&1 &
W=$!; for i in $(seq 100); do [ -S $XDG_RUNTIME_DIR/wayland-folio ] && break; sleep 0.1; done
export WAYLAND_DISPLAY=wayland-folio GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland XTEST_DISPLAY="$DISPLAY"
X="$DISPLAY"; DISPLAY= "$@"; rc=$?
if ! kill -0 $W 2>/dev/null && [ -z "$WL_RETRIED" ]; then
  # Weston itself crashed under the run: say so, and run the command once more in a fresh compositor
  echo "wl.sh: weston crashed during the run ($(grep -m1 -iE 'segment|signal|abort' /tmp/weston.out)); running it again"
  rm -rf $XDG_RUNTIME_DIR; DISPLAY="$X" WL_RETRIED=1 exec "$0" "$@"
fi
kill $W 2>/dev/null; wait $W 2>/dev/null; rm -rf $XDG_RUNTIME_DIR; exit $rc
