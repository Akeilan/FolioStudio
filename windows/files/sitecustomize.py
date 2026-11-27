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


def _spelling():
    """pyenchant is told which enchant library to load (the name has changed between versions)."""
    root = os.environ.get("FOLIO_ROOT")
    if sys.platform != "win32" or not root or os.environ.get("PYENCHANT_LIBRARY_PATH"):
        return
    import glob
    found = sorted(glob.glob(os.path.join(root, "runtime", "bin", "libenchant-2*.dll")))
    if found:
        os.environ["PYENCHANT_LIBRARY_PATH"] = found[0]


def _log():
    """A window program has nowhere to print to, so what it would print (a crash above all) goes to
    the log the launcher names (FOLIO_LOG), which the launcher points to if the app stops."""
    path = os.environ.get("FOLIO_LOG")
    if sys.platform != "win32" or not path or sys.stderr is not None:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        f = open(path, "w", encoding="utf-8", errors="replace", buffering=1)
    except OSError:
        return
    sys.stdout = sys.stderr = f


def _no_console_windows():
    """In a window program, the console programs an app starts (ffmpeg, folio-reel, PowerShell)
    would each open a console window; started with CREATE_NO_WINDOW, they don't."""
    if sys.platform != "win32":
        return
    try:
        import ctypes
        if ctypes.windll.kernel32.GetConsoleWindow():
            return
    except (OSError, AttributeError):
        return
    import subprocess
    plain = subprocess.Popen.__init__

    def init(self, *args, **kw):
        if len(args) < 14 and not kw.get("creationflags"):   # creationflags is the 14th argument
            kw["creationflags"] = subprocess.CREATE_NO_WINDOW
        plain(self, *args, **kw)
    subprocess.Popen.__init__ = init


_log()
_no_console_windows()
_private_fonts()
_spelling()
