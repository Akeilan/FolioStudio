"""Checks the installed Folio Studio on Windows with every app's own tests, and writes a report.

  test.cmd                    everything (an hour or two: windows open and close by themselves;
                              leave the mouse and keyboard alone while it runs)
  test.cmd --quick            the engines and one window test per app (a few minutes)
  test.cmd --only page,reel   some apps: page sheet show draw gable chord reel

The tests come from the apps' code that build.sh fetched (FOLIO_SRC, normally
C:\\msys64\\home\\<you>\\folio-src); --src says where else to look. The report,
folio-test-report.txt, is put on your Desktop: send it back as it is."""
import argparse
import datetime
import glob
import os
import platform
import re
import subprocess
import sys
import tempfile
import time

ROOT = os.environ.get("FOLIO_ROOT") or os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Folio Studio")
ROWS = []
DETAILS = []


def load_env():
    """The same settings the launchers give the apps (bin\\folio-env.txt)."""
    env = dict(os.environ)
    with open(os.path.join(ROOT, "bin", "folio-env.txt"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.replace("%ROOT%", ROOT)
            v = re.sub(r"%([A-Za-z_][A-Za-z0-9_()]*)%", lambda m: env.get(m.group(1), ""), v)
            env[k] = v
    env["FOLIO_ROOT"] = ROOT
    return env


def counts(out):
    """(checks, failed) from a test's output, as Folio Studio's run-tests.sh reads it."""
    m = re.findall(r"(\d+) checks, (\d+) failed", out)
    if m:
        return int(m[-1][0]), int(m[-1][1])
    m = re.findall(r"^(\d+) passed, (\d+) failed", out, re.M)
    if m:
        return int(m[-1][0]), int(m[-1][1])
    m = re.findall(r"test result: \w+\. (\d+) passed; (\d+) failed", out)
    if m:
        return sum(int(a) for a, _b in m), sum(int(b) for _a, b in m)
    p = len(re.findall(r"^(PASS|ok) ", out, re.M))
    q = len(re.findall(r"^(FAIL|ERROR) ", out, re.M))
    if p or q:
        return p + q, q
    return None, None


def run(name, args, env, timeout=600, log=None, cwd=None):
    t0 = time.time()
    if log and os.path.exists(log):
        os.remove(log)
    try:
        r = subprocess.run(args, env=env, cwd=cwd or tempfile.gettempdir(), capture_output=True, timeout=timeout,
                           encoding="utf-8", errors="replace")
        out, rc = (r.stdout or "") + (r.stderr or ""), r.returncode
    except subprocess.TimeoutExpired as e:
        out = ((e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")) + \
              "\n(stopped after %d s)" % timeout
        rc = -1
    except OSError as e:
        out, rc = "couldn't start: %s" % e, -1
    if log and os.path.exists(log):
        with open(log, encoding="utf-8", errors="replace") as f:
            out = f.read() + "\n" + out
    n, f = counts(out)
    bad = f is None or f > 0 or (rc != 0 and f == 0) or ("Traceback" in out and not f)
    shown = "error" if (f is None or (bad and not f)) else str(f)
    ROWS.append((name, "?" if n is None else str(n), shown, "%.0f s" % (time.time() - t0)))
    print("%-36s %6s %6s" % (name, ROWS[-1][1], shown), flush=True)
    if bad:
        keep = [ln for ln in out.splitlines() if re.match(r"^(FAIL|ERROR|  File|Traceback|\w*Error|\(stopped)", ln)]
        DETAILS.append((name, "\n".join((keep or out.splitlines())[-25:])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--only", default="page,sheet,show,draw,gable,chord,reel")
    ap.add_argument("--src", default=None)
    a = ap.parse_args()
    want = set(a.only.split(","))
    src = a.src or os.environ.get("FOLIO_SRC") or os.path.join(os.environ.get("MSYS2_ROOT", r"C:\msys64"), "home",
                                                                os.environ.get("USERNAME", ""), "folio-src")
    if not os.path.isdir(src):
        sys.exit("The apps' code isn't in %s (build.sh puts it there). Say where with --src." % src)
    env = load_env()
    py = os.path.join(ROOT, "runtime", "bin", "python.exe")
    bin_ = os.path.join(ROOT, "bin")
    # the tests write to /tmp, as on Linux: on Windows that is \tmp on this drive
    os.makedirs(os.path.join(os.path.splitdrive(tempfile.gettempdir())[0] + os.sep, "tmp"), exist_ok=True)
    work = tempfile.mkdtemp(prefix="folio-test-")
    log = os.path.join(work, "ftest.log")
    quick = a.quick
    print("Folio Studio tests on %s, from %s\n" % (platform.platform(), src))

    def app_env(pypath, **extra):
        e = dict(env)
        e["PYTHONPATH"] = pypath + os.pathsep + os.path.join(ROOT, "lib", "python")
        e["XDG_CONFIG_HOME"] = tempfile.mkdtemp(dir=work)
        e["XDG_DATA_HOME"] = tempfile.mkdtemp(dir=work)
        e["XDG_CACHE_HOME"] = tempfile.mkdtemp(dir=work)
        e["FOLIO_TEST_DELAY"] = "1500"
        e["UI_OUT"] = os.path.join(work, "ui_out")
        e.update({k: str(v) for k, v in extra.items()})
        return e

    def pick(files):
        files = sorted(f for f in files if os.path.exists(f))
        return files[:1] if quick else files

    # ---- Page
    if "page" in want:
        t = os.path.join(src, "page", "tests")
        for f in pick(glob.glob(os.path.join(t, "native", "n*.py"))):
            run("Page " + os.path.basename(f)[:-3], [py, "-m", "folio"],
                app_env(os.path.join(ROOT, "apps", "page"), FOLIO_ENGINE="native", FOLIO_WRITER_TESTS=t,
                        FOLIO_TEST_SCRIPT=f, FOLIO_TEST_LOG=log, FOLIO_SHARE=os.path.join(ROOT, "share", "folio-page")),
                timeout=300, log=log)
    # ---- Sheet
    if "sheet" in want:
        t = os.path.join(src, "sheet", "tests")
        for f in pick(glob.glob(os.path.join(t, "*_audit.py"))):
            run("Sheet " + os.path.basename(f)[:-3], [py, "-m", "folio_sheets"],
                app_env(os.path.join(ROOT, "apps", "sheet"), FOLIO_TEST_SCRIPT=f), timeout=600)
    # ---- Show
    if "show" in want:
        t = os.path.join(src, "show", "tests")
        for f in sorted(glob.glob(os.path.join(t, "test_engine*.py"))):
            run("Show " + os.path.basename(f)[:-3], [py, f], app_env(os.path.join(ROOT, "apps", "show")))
        ui = ["ui_basic.py", "ui_more.py", "ui_anim.py", "ui_review.py", "ui_master.py", "ui_show2.py",
              "ui_objects.py", "ui_media.py", "ui_theme.py"]
        for f in pick(os.path.join(t, u) for u in ui):
            run("Show " + os.path.basename(f)[:-3], [py, "-m", "folio_deliver"],
                app_env(os.path.join(ROOT, "apps", "show"), FOLIO_TEST_SCRIPT=f), timeout=600)
    # ---- Draw
    if "draw" in want:
        exe = os.path.join(bin_, "folio-draw.exe")
        run("Draw window test", [exe, "--ui-test", tempfile.mkdtemp(dir=work)], env, timeout=600)
        run("Draw without a display", [exe, "--ui-test", tempfile.mkdtemp(dir=work), "--headless"], env, timeout=600)
    # ---- Gable
    if "gable" in want:
        e = dict(env)
        if quick:
            e["AUDIT_QUICK"] = "1"
        e["HOME"] = tempfile.mkdtemp(dir=work)
        run("Gable audit" + (" (quick)" if quick else ""), [os.path.join(bin_, "folio-gable.exe"), "--audit"], e, timeout=3600)
    # ---- Chord
    if "chord" in want:
        t = os.path.join(src, "chord", "tests")
        pp = os.path.join(ROOT, "apps", "chord")
        for name in ("test_engine.py", "test_net.py", "test_more.py", "test_sharing.py"):
            f = os.path.join(t, name)
            if os.path.exists(f):
                run("Chord " + name[:-3], [py, f], app_env(pp, FOLIO_CHORD_AUDIOSINK="fakesink", FOLIO_TESTS=t))
        ui = ["ui_library.py", "ui_play.py", "ui_net.py", "ui_more.py", "ui_shared.py", "ui_classic.py", "command_walk.py"]
        stub = "http://127.0.0.1:9"
        for f in pick(os.path.join(t, u) for u in ui):
            run("Chord " + os.path.basename(f)[:-3], [py, "-m", "folio_chord"],
                app_env(pp, FOLIO_TEST_SCRIPT=f, FOLIO_TESTS=t, FOLIO_CHORD_DATA=tempfile.mkdtemp(dir=work),
                        FOLIO_CHORD_NON_UNIQUE=1, FOLIO_CHORD_NO_SCAN=1, FOLIO_CHORD_NO_AUTOSYNC=1,
                        FOLIO_CHORD_RADIO_API=stub, FOLIO_CHORD_APPLE_API=stub, FOLIO_CHORD_PODCASTINDEX_API=stub,
                        FOLIO_CHORD_MUSICBRAINZ=stub, FOLIO_CHORD_COVERART=stub, FOLIO_CHORD_NO_KEYRING=1,
                        FOLIO_CHORD_AUDIOSINK="fakesink"), timeout=900)
    # ---- Reel
    if "reel" in want:
        t = os.path.join(src, "reel", "tests")
        pp = os.path.join(ROOT, "apps", "reel")
        run("Reel test_engine", [py, os.path.join(t, "test_engine.py")], app_env(pp), timeout=1800)
        run("Reel test_cli", [py, os.path.join(t, "test_cli.py")],
            app_env(pp, REEL_CMD=os.path.join(bin_, "folio-reel.exe")), timeout=900)
        if not quick:
            run("Reel test_backlog9", [py, os.path.join(t, "test_backlog9.py")],
                app_env(pp, REEL_CMD=os.path.join(bin_, "folio-reel.exe")), timeout=3600)
        ui = ["ui_basic.py", "ui_record.py", "ui_steady.py", "ui_scrub.py", "ui_picture.py", "ui_sound.py",
              "ui_speed.py", "ui_backlog9.py", "command_walk.py"]
        for f in pick(os.path.join(t, u) for u in ui):
            run("Reel " + os.path.basename(f)[:-3], [py, "-m", "folio_reel"],
                app_env(pp, FOLIO_TEST_SCRIPT=f, REEL_TESTS=t, FOLIO_REEL_AUDIOSINK="fakesink",
                        FOLIO_REEL_AUDIOSRC="audiotestsrc is-live=true freq=500", HOME=tempfile.mkdtemp(dir=work)),
                timeout=1500 if f.endswith("command_walk.py") else 600)

    failed = [r for r in ROWS if r[2] != "0"]
    lines = ["Folio Studio tests on Windows, %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
             "Windows: %s (%s)" % (platform.platform(), platform.machine()),
             "Installed: %s" % ROOT,
             "Folio Studio %s" % _installed_version(), "",
             "%-36s %6s %6s %8s" % ("Test", "Checks", "Failed", "Time")]
    lines += ["%-36s %6s %6s %8s" % r for r in ROWS]
    summary = "All passed." if not failed else "%d of %d failed." % (len(failed), len(ROWS))
    lines += ["", summary]
    for name, text in DETAILS:
        lines += ["", "---- " + name, text]
    report = os.path.join(os.path.expanduser("~"), "Desktop", "folio-test-report.txt")
    if not os.path.isdir(os.path.dirname(report)):
        report = os.path.join(os.path.expanduser("~"), "folio-test-report.txt")
    with open(report, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n" + summary)
    print("The report is in %s" % report)
    return 0 if not failed else 1


def _installed_version():
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"Software\Folio Studio") as k:
            return winreg.QueryValueEx(k, "Version")[0]
    except OSError:
        return "(version not found)"


if __name__ == "__main__":
    sys.exit(main())
