"""Clipboard chain, step 2 (Folio Draw): paste the view Gable copied, then copy the picture
for Sheets. Run with the installed folio_draw (or PYTHONPATH pointing at a source tree).
Args: <exchange dir>"""
import os
import sys
import time

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk  # noqa: E402

from folio_draw import dialogs as D  # noqa: E402
from folio_draw import theme  # noqa: E402
from folio_draw.app import App  # noqa: E402
from folio_draw.window import Window  # noqa: E402

ex = sys.argv[1]


def pump(t=0.1):
    end = time.time() + t
    while time.time() < end:
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        time.sleep(0.01)


def wait_for(name, secs=120):
    end = time.time() + secs
    while not os.path.exists(os.path.join(ex, name)) and time.time() < end:
        pump(0.1)
    return os.path.exists(os.path.join(ex, name))


bad = []


def check(what, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + repr(detail)), flush=True)
    if not ok:
        bad.append(what)


D.ask_choice = lambda *a, **k: 2          # "Enlarge canvas" when the picture is larger
app = App()
app.register(None)
theme.install()
win = Window(app)
win.show_all()
pump(0.5)
if not wait_for("gable.ready"):
    check("Gable put its view on the clipboard", False)
    sys.exit(1)
gw, gh = (int(v) for v in open(os.path.join(ex, "gable.ready")).read().split())
win.c_paste()
pump(0.2)
r = win.doc.float_rect()
check("Draw pastes the view Gable copied, at its size", r is not None and (r[2], r[3]) == (gw, gh), (r, gw, gh))
win.finalize_pending()
win.c_select_all()
check("and copies the picture for the next program", win.c_copy())
pump(0.2)
with open(os.path.join(ex, "draw.ready"), "w") as f:
    f.write("%d %d\n" % (win.doc.width, win.doc.height))
open(os.path.join(ex, "gable.done"), "w").close()
wait_for("draw.done")
print("%d failed" % len(bad), flush=True)
os._exit(1 if bad else 0)
