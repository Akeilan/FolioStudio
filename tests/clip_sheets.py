# Clipboard chain, step 3 (Folio Sheets, as FOLIO_TEST_SCRIPT): paste the picture Draw copied,
# then copy a range and read back the HTML table other programs get.
import os
import time

from gi.repository import Gdk, GdkPixbuf, Gtk

ex = os.environ["CLIP_EXCHANGE"]
bad = []


def check(what, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + repr(detail)), flush=True)
    if not ok:
        bad.append(what)


def pump(t=0.1):
    end = time.time() + t
    while time.time() < end:
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        time.sleep(0.01)


end = time.time() + 120
while not os.path.exists(os.path.join(ex, "draw.ready")) and time.time() < end:
    pump(0.1)
dw, dh = (int(v) for v in open(os.path.join(ex, "draw.ready")).read().split())
g = win.grid
b = win.book
g.select_range((1, 1, 1, 1), (1, 1))
win.run("paste")
objs = b.objects(0)
check("Sheets pastes Draw's picture as a picture", len(objs) == 1 and objs[0]["kind"] == "picture", objs)
got = b.picture_bytes(0, 0) if objs else None
size = None
if got:
    loader = GdkPixbuf.PixbufLoader()
    loader.write(bytes(got[0]))
    loader.close()
    pb = loader.get_pixbuf()
    size = (pb.get_width(), pb.get_height())
check("the whole picture, at full size", size == (dw, dh), (size, dw, dh))
w, h = objs[0]["rect"][2:] if objs else (0, 1)
check("shown in its own proportions", abs(w / h - dw / dh) < 0.01, (w, h))
open(os.path.join(ex, "draw.done"), "w").close()
b.set_input(0, 20, 0, "Part")
b.set_input(0, 20, 1, "Qty")
b.set_input(0, 21, 0, "Bolt")
b.set_input(0, 21, 1, "12")
g.deselect_objects()
g.select_range((20, 0, 21, 1), (20, 0))
win.run("copy")
pump(0.2)
sel = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).wait_for_contents(Gdk.Atom.intern("text/html", False))
html = sel.get_data().decode("utf-8") if sel else ""
check("a copied range is offered as an HTML table (what Writer will take)", "<td>Bolt</td>" in html and "<td>12</td>" in html, html[:120])
print("%d failed" % len(bad), flush=True)
os._exit(1 if bad else 0)
