"""Run by Python as it starts, for every Folio app on Windows (it sits in <root>\\lib\\python,
which the launchers put on PYTHONPATH).

The fonts that ship with Folio (Carlito, Liberation, STIX Two Math) are made available to this
program only, the way Windows lets a program use fonts without installing them for everyone:
GTK and Pango then find them like any other font, and documents look as they do on Linux."""
import os
import sys


def _private_fonts():
    root = os.environ.get("FOLIO_ROOT")
    if sys.platform != "win32" or not root:
        return
    try:
        import ctypes
        add = ctypes.windll.gdi32.AddFontResourceExW
    except (OSError, AttributeError):
        return
    FR_PRIVATE = 0x10
    for d in (os.path.join(root, "share", "folio", "fonts"), os.path.join(root, "share", "folio-page", "fonts")):
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            if n.lower().endswith((".ttf", ".otf", ".ttc")):
                add(os.path.join(d, n), FR_PRIVATE, None)


_private_fonts()
