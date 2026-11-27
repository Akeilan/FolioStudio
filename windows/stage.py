#!/usr/bin/env python3
"""Puts Folio Studio for Windows together, and makes its MSI. Run by build.sh, in the MSYS2
UCRT64 shell; the MSI step also runs on Linux (wixl from msitools), which is how it is checked.

  stage.py runtime <dir> <package>...   the MSYS2 packages the apps run on, with everything they
                                        depend on, copied into <dir> (headers, docs, static
                                        libraries and the like left out)
  stage.py msi <tree> <out.msi> <version>
                                        one MSI holding <tree> (the installation folder as it
                                        will be), with the Start menu entries and file types

The MSI installs for everyone in C:\\Program Files\\Folio Studio. A newer MSI replaces an older
one in place; Settings > Apps removes it."""
import hashlib
import os
import shutil
import subprocess
import sys
import uuid
from xml.sax.saxutils import quoteattr

# one for good: every Folio Studio MSI replaces the one before
UPGRADE_CODE = "{6F1E0F51-3C4B-4B8E-9E0A-2D8F7C1A5B21}"
NS = uuid.UUID("0b8f6a3e-6d2c-4e0b-9d7a-1f3c5e7a9b11")

# the apps: launcher, name, icon, the file types each opens, and which of those are its own
APPS = [
    ("FolioPage.exe", "Folio Page", "folio-page.ico", "Word processor",
     [".docx", ".docm", ".dotx", ".dotm", ".doc", ".rtf", ".odt"], []),
    ("FolioSheet.exe", "Folio Sheet", "folio-sheet.ico", "Spreadsheet",
     [".xlsx", ".xlsm", ".xltx", ".xltm", ".xls", ".ods", ".csv"], []),
    ("FolioShow.exe", "Folio Show", "folio-show.ico", "Presentations",
     [".pptx", ".pptm", ".ppsx", ".potx", ".ppt", ".odp"], []),
    ("FolioDraw.exe", "Folio Draw", "folio-draw.ico", "Pictures and embroidery",
     [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".tif", ".tiff", ".ora", ".psd"], []),
    ("FolioGable.exe", "Folio Gable", "folio-gable.ico", "3D modelling",
     [".gbl"], [".gbl"]),
    ("FolioChord.exe", "Folio Chord", "folio-chord.ico", "Music, radio and podcasts",
     [".mp3", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".wav", ".aiff", ".m3u", ".m3u8"], []),
    ("FolioReel.exe", "Folio Reel", "folio-reel.ico", "Video editing",
     [".reel"], [".reel"]),
]

# left out of the runtime: what only building needs
SKIP_DIRS = ("include/", "share/doc/", "share/man/", "share/info/", "share/gtk-doc/", "share/devhelp/",
             "lib/pkgconfig/", "lib/cmake/", "share/aclocal/", "share/gir-1.0/", "share/pkgconfig/",
             "share/qt6/doc/", "share/qt6/examples/", "share/vala/", "share/bash-completion/")
SKIP_ENDS = (".a", ".la", ".h", ".hpp", ".pc", ".cmake", ".prl")


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


# ---------------------------------------------------------------- the runtime
def runtime(dest, packages):
    # build.sh says where MSYS2's UCRT64 packages are, both ways round (pacman names files the
    # MSYS2 way, /ucrt64/...; Python opens them the Windows way, C:/msys64/ucrt64/...)
    prefix = os.environ.get("FOLIO_POSIX_PREFIX") or "/ucrt64"
    win_prefix = (os.environ.get("FOLIO_WIN_PREFIX") or sh("cygpath", "-m", prefix).strip()).rstrip("/")
    closure = set()
    for p in packages:
        out = sh("pactree", "-lu", p)
        closure.update(x.strip() for x in out.splitlines() if x.strip())
    files = sh("pacman", "-Qlq", *sorted(closure)).splitlines()
    n = size = 0
    for f in files:
        if f.endswith("/") or not f.startswith(prefix + "/"):
            continue
        rel = f[len(prefix) + 1:]
        if rel.startswith(SKIP_DIRS) or rel.endswith(SKIP_ENDS) or "/test/" in rel or "/tests/" in rel:
            continue
        src = win_prefix + "/" + rel
        if not os.path.isfile(src):
            continue
        out = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copy2(src, out)
        n += 1
        size += os.path.getsize(out)
    # made when the packages were installed, so in no package's file list
    py = sorted(d for d in os.listdir(win_prefix + "/lib") if d.startswith("python3."))
    extra = ["share/glib-2.0/schemas/gschemas.compiled", "lib/gio/modules/giomodule.cache",
             "share/icons/Adwaita/icon-theme.cache", "share/icons/hicolor/icon-theme.cache",
             "lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"]
    for rel in extra:
        src = win_prefix + "/" + rel
        if os.path.isfile(src):
            os.makedirs(os.path.dirname(os.path.join(dest, rel)), exist_ok=True)
            shutil.copy2(src, os.path.join(dest, rel))
    for d in ("share/mime",) + tuple("lib/%s/site-packages" % v for v in py[-1:]):
        if os.path.isdir(win_prefix + "/" + d):
            shutil.copytree(win_prefix + "/" + d, os.path.join(dest, d), dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("tests", "test"))
    # the picture loaders' list names them by where MSYS2 is; relative, they are found wherever
    # the suite is installed
    cache = os.path.join(dest, "lib/gdk-pixbuf-2.0/2.10.0/loaders.cache")
    if os.path.exists(cache):
        text = open(cache, encoding="utf-8").read()
        for p in (win_prefix + "/", win_prefix.replace("/", "\\\\") + "\\\\", win_prefix.replace("/", "\\") + "\\"):
            text = text.replace(p, "")
        open(cache, "w", encoding="utf-8").write(text)
    print("runtime: %d packages, %d files, %.0f MB" % (len(closure), n, size / 1e6))


# ---------------------------------------------------------------- the MSI
def _id(prefix, text):
    return prefix + hashlib.sha1(text.encode("utf-8")).hexdigest()[:24]


def _guid(text):
    return "{%s}" % str(uuid.uuid5(NS, text)).upper()


def msi(tree, out, version):
    tree = os.path.abspath(tree)
    out = os.path.abspath(out)
    here = os.path.dirname(out)
    os.makedirs(here, exist_ok=True)

    def src(path):
        # wixl takes sources relative to where it runs (an absolute path it can't find)
        return os.path.relpath(path, here).replace(os.sep, "/")
    icons = os.path.join(tree, "share", "folio", "icons")
    lines = ['<?xml version="1.0" encoding="utf-8"?>',
             '<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">',
             '<Product Id="*" Name="Folio Studio" Language="1033" Version=%s Manufacturer="Folio Studio" UpgradeCode=%s>'
             % (quoteattr(version), quoteattr(UPGRADE_CODE)),
             '<Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" '
             'Description="Folio Studio: Page, Sheet, Show, Draw, Gable, Chord and Reel" Comments="MIT licence"/>',
             '<MajorUpgrade DowngradeErrorMessage="A newer Folio Studio is already installed."/>']
    # files, a cabinet for each 1.5 GB (a cabinet can't hold more than 2 GB)
    media, used, comps = 1, 0, []
    dirs = {}

    def walk(path, rel):
        nonlocal media, used
        body = []
        for name in sorted(os.listdir(path)):
            full = os.path.join(path, name)
            r = (rel + "/" + name) if rel else name
            if os.path.isdir(full):
                did = _id("d", r)
                dirs[r] = did
                body.append('<Directory Id="%s" Name=%s>' % (did, quoteattr(name)))
                body += walk(full, r)
                body.append('</Directory>')
            else:
                sz = os.path.getsize(full)
                if used + sz > 1_500_000_000 and used:
                    media += 1
                    used = 0
                used += sz
                cid = _id("c", r)
                comps.append(cid)
                body.append('<Component Id="%s" Guid="%s" Win64="yes"><File Id="%s" Name=%s Source=%s KeyPath="yes" DiskId="%d"/></Component>'
                            % (cid, _guid(r), _id("f", r), quoteattr(name), quoteattr(src(full)), media))
        return body
    tree_xml = walk(tree, "")
    for m in range(1, media + 1):
        lines.append('<Media Id="%d" Cabinet="folio%d.cab" EmbedCab="yes"/>' % (m, m))
    for exe, name, ico, _what, _types, _own in APPS:
        lines.append('<Icon Id="%s" SourceFile=%s/>' % (ico, quoteattr(src(os.path.join(icons, ico)))))
    lines.append('<Property Id="ARPPRODUCTICON" Value="folio-page.ico"/>')
    lines.append('<Property Id="ARPNOMODIFY" Value="1"/>')
    lines.append('<Directory Id="TARGETDIR" Name="SourceDir">')
    lines.append('<Directory Id="ProgramFiles64Folder"><Directory Id="INSTALLDIR" Name="Folio Studio">')
    lines += tree_xml
    lines.append('</Directory></Directory>')
    lines.append('<Directory Id="ProgramMenuFolder"><Directory Id="AppMenu" Name="Folio Studio"/></Directory>')
    lines.append('</Directory>')
    # the Start menu
    sc = ['<DirectoryRef Id="AppMenu"><Component Id="StartMenu" Guid="%s" Win64="yes">' % _guid("start menu")]
    for exe, name, ico, what, _types, _own in APPS:
        sc.append('<Shortcut Id=%s Name=%s Description=%s Target="[INSTALLDIR]bin\\%s" WorkingDirectory="INSTALLDIR" Icon="%s"/>'
                  % (quoteattr(_id("s", exe)), quoteattr(name), quoteattr(what), exe, ico))
    sc.append('<RemoveFolder Id="AppMenu" On="uninstall"/>')
    sc.append('<RegistryValue Root="HKLM" Key="Software\\Folio Studio" Name="StartMenu" Type="integer" Value="1" KeyPath="yes"/>')
    sc.append('</Component></DirectoryRef>')
    comps.append("StartMenu")
    lines += sc
    # file types: each app is offered under "Open with" for what it opens, registered for
    # Settings > Default apps, and made the default only for its own formats (.gbl, .reel)
    reg = ['<DirectoryRef Id="INSTALLDIR"><Component Id="FileTypes" Guid="%s" Win64="yes">' % _guid("file types"),
           '<RegistryValue Root="HKLM" Key="Software\\Folio Studio" Name="Version" Type="string" Value=%s KeyPath="yes"/>'
           % quoteattr(version)]
    for exe, name, ico, what, types, own in APPS:
        app = name.split()[-1]
        progid = "FolioStudio.%s" % app
        cmd = '"[INSTALLDIR]bin\\%s" "%%1"' % exe
        k = "Software\\Classes\\%s" % progid

        def rv(key, val, nm=None, typ="string"):
            reg.append('<RegistryValue Root="HKLM" Key=%s%s Type="%s" Value=%s/>'
                       % (quoteattr(key), (" Name=%s" % quoteattr(nm)) if nm else "", typ, quoteattr(val)))
        rv(k, "%s document" % name)
        rv(k + "\\DefaultIcon", "[INSTALLDIR]share\\folio\\icons\\%s" % ico)
        rv(k + "\\shell\\open\\command", cmd)
        cap = "Software\\Folio Studio\\%s\\Capabilities" % app
        rv(cap, name, "ApplicationName")
        rv(cap, what, "ApplicationDescription")
        rv("Software\\RegisteredApplications", cap, name)
        ak = "Software\\Classes\\Applications\\%s" % exe
        rv(ak, name, "FriendlyAppName")
        rv(ak + "\\shell\\open\\command", cmd)
        for t in types:
            rv("Software\\Classes\\%s\\OpenWithProgids" % t, "", progid)
            rv(cap + "\\FileAssociations", progid, t)
            rv(ak + "\\SupportedTypes", "", t)
            if t in own:
                rv("Software\\Classes\\%s" % t, progid)
    reg.append('</Component></DirectoryRef>')
    comps.append("FileTypes")
    lines += reg
    lines.append('<Feature Id="FolioStudio" Title="Folio Studio" Level="1">')
    lines += ['<ComponentRef Id="%s"/>' % c for c in comps]
    lines.append('</Feature>')
    lines.append('</Product></Wix>')
    wxs = os.path.splitext(out)[0] + ".wxs"
    with open(wxs, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    r = subprocess.run(["wixl", "-a", "x64", "-o", os.path.basename(out), os.path.basename(wxs)],
                       capture_output=True, text=True, cwd=here)
    noise = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.strip() and "CRITICAL" not in ln]
    if r.returncode != 0 or not os.path.exists(out):
        print("\n".join(noise[-20:]), file=sys.stderr)
        raise SystemExit("wixl couldn't make the MSI")
    print("msi: %s, %d files, %.0f MB" % (out, len(comps) - 2, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "runtime":
        runtime(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 5 and sys.argv[1] == "msi":
        msi(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
        sys.exit(2)
