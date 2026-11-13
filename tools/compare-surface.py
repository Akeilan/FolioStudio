#!/usr/bin/env python3
"""X4-05: compare what a candidate shows a person with what the app it replaces showed.

  compare-surface.py <before.json> <after.json> [--allow <file>]

Exit 0 when the candidate still shows everything the app it replaces did. Exit 1 when anything has
gone, and say what. A release gate that only runs an app's own tests cannot catch a rewrite that
dropped a whole menu bar, because the tests were written for the rewrite: this compares the two.

--allow names a file of lines that are allowed to disappear, one per line, '#' for a comment: the
place to write down something deliberately taken out, with a reason, rather than loosening the gate.
"""
import json
import sys


def load(path):
    with open(path) as f:
        d = json.load(f)
    return d.get("app", "?"), set(d.get("lines", []))


def allowed(path):
    if not path:
        return set()
    out = set()
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if line:
                out.add(line)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip())
        return 2
    before, after = argv[1], argv[2]
    allow = allowed(argv[argv.index("--allow") + 1] if "--allow" in argv else None)
    old_app, old = load(before)
    new_app, new = load(after)
    if old_app == new_app:
        # the same app wrote both: an install that quietly failed leaves the version before it in
        # place, and an app compared with itself passes every time
        print("FAIL: both surfaces say they came from %s, so nothing was compared." % old_app)
        return 2
    gone = sorted(old - new - allow)
    added = sorted(new - old)
    excused = sorted((old - new) & allow)
    print("was: %s, %d lines" % (old_app, len(old)))
    print("now: %s, %d lines" % (new_app, len(new)))
    if added:
        print("\n%d new:" % len(added))
        for line in added[:40]:
            print("  + " + line)
        if len(added) > 40:
            print("  ... and %d more" % (len(added) - 40))
    if excused:
        print("\n%d gone on purpose (in the allow file):" % len(excused))
        for line in excused[:20]:
            print("  ~ " + line)
    if gone:
        print("\n%d GONE:" % len(gone))
        for line in gone[:80]:
            print("  - " + line)
        if len(gone) > 80:
            print("  ... and %d more" % (len(gone) - 80))
        print("\nFAIL: the candidate no longer shows %d things the app it replaces showed." % len(gone))
        return 1
    print("\nok: the candidate still shows everything the app it replaces did.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
