#!/bin/bash
# Run a command as a Wayland client: a Weston compositor shown in the X display $DISPLAY (an Xvfb),
# so the session has a real seat (keyboard and pointer) like a desktop's.   wl.sh CMD...
export XDG_RUNTIME_DIR=/tmp/wlrt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
weston --backend=x11-backend.so --socket=wayland-folio --width=1600 --height=1000 --idle-time=0 >/tmp/weston.out 2>&1 &
W=$!; for i in $(seq 100); do [ -S $XDG_RUNTIME_DIR/wayland-folio ] && break; sleep 0.1; done
export WAYLAND_DISPLAY=wayland-folio GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland
DISPLAY= "$@"; rc=$?
kill $W 2>/dev/null; wait $W 2>/dev/null; rm -rf $XDG_RUNTIME_DIR; exit $rc
