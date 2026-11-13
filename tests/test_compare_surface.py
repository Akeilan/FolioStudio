#!/usr/bin/env python3
"""X4-05: the comparison itself, checked. Run: python3 tests/test_compare_surface.py"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CMP = os.path.join(HERE, "..", "tools", "compare-surface.py")
N = [0]
FAILS = []


def check(cond, what, info=None):
    N[0] += 1
    print(("ok   " if cond else "FAIL ") + what + ("" if cond or info is None else "  -- %r" % (info,)))
    if not cond:
        FAILS.append(what)
    sys.stdout.flush()


def surface(tmp, name, lines):
    p = os.path.join(tmp, name + ".json")
    with open(p, "w") as f:
        json.dump({"app": name, "lines": sorted(lines)}, f)
    return p


def run(*args):
    r = subprocess.run([sys.executable, CMP] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    tmp = tempfile.mkdtemp(prefix="surface_")
    full = ["menu:File", "menu:File > Open", "menu:File > Save", "menu:View",
            "ribbon:Home", "ribbon:Home > Clipboard", "button:Play", "command:play"]

    code, out = run(surface(tmp, "a", full), surface(tmp, "b", full))
    check(code == 0, "the same surface passes", (code, out[-120:]))

    code, out = run(surface(tmp, "c", full), surface(tmp, "d", full + ["button:New Thing"]))
    check(code == 0, "a candidate that adds things passes", code)
    check("+ button:New Thing" in out, "and says what is new", out[-200:])

    gone = [x for x in full if not x.startswith("menu:")]
    code, out = run(surface(tmp, "e", full), surface(tmp, "f", gone))
    check(code == 1, "a candidate that lost its whole menu bar fails", code)
    check("4 GONE" in out and "- menu:File > Open" in out, "and names what went", out[-300:])

    one_less = [x for x in full if x != "button:Play"]
    code, out = run(surface(tmp, "g", full), surface(tmp, "h", one_less))
    check(code == 1, "losing a single button fails too", code)

    allow = os.path.join(tmp, "allow.txt")
    with open(allow, "w") as f:
        f.write("# Play went when the transport moved to the status bar\nbutton:Play\n")
    code, out = run(surface(tmp, "i", full), surface(tmp, "j", one_less), "--allow", allow)
    check(code == 0, "a removal written down in the allow file passes", (code, out[-200:]))
    check("gone on purpose" in out, "and is still reported", out[-200:])

    code, out = run(surface(tmp, "k", full), surface(tmp, "l", [x for x in one_less if x != "menu:View"]),
                    "--allow", allow)
    check(code == 1, "but only the lines written down are excused", code)

    same = surface(tmp, "m", full)
    code, out = run(same, same)
    check(code == 2, "the very same file on both sides is refused", (code, out[-150:]))
    check("nothing was compared" in out, "and says why", out[-150:])

    print("%d checks, %d failed" % (N[0], len(FAILS)))
    print("all passed" if not FAILS else "FAILED")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
