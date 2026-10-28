#!/bin/bash
# Builds the Folio Suite installer: one file that installs Writer, Sheets, Draw, Gable,
# Deliver and Post through a local apt repository, so later versions arrive
# through the normal Software Updater.
#
#   packaging/build-suite.sh <folder with the app .debs> [output folder]
#
# Makes folio-suite_<ver>_all.deb (depends on every app), a signed apt repository holding the
# newest .deb of each package, and folio-suite-<ver>-installer.run around it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEBS="$(cd "$1" && pwd)"
OUT="$(mkdir -p "${2:-$HERE/out}" && cd "${2:-$HERE/out}" && pwd)"
VERSION="$(cat "$HERE/VERSION")"
KEYHOME="${FOLIO_SUITE_KEYS:-$HOME/.folio-suite-signing}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

newest() {   # newest .deb of a package in $DEBS
  local best="" bv=""
  for f in "$DEBS"/"$1"_*_*.deb; do
    [ -f "$f" ] || continue
    local v; v="$(dpkg-deb -f "$f" Version)"
    if [ -z "$bv" ] || dpkg --compare-versions "$v" gt "$bv"; then best="$f"; bv="$v"; fi
  done
  echo "$best"
}

REPO="$WORK/payload/repo"
mkdir -p "$REPO"
DEPENDS=()
for p in folio-sheets folio-draw folio-gable folio-writer folio-deliver folio-post; do
  f="$(newest $p)"
  if [ -n "$f" ]; then
    cp "$f" "$REPO/"
    DEPENDS+=("$p (>= $(dpkg-deb -f "$f" Version))")
    echo "  $(basename "$f")"
  elif [ "$p" != folio-writer ] && [ "$p" != folio-deliver ] && [ "$p" != folio-post ]; then
    echo "missing $p in $DEBS" >&2; exit 1
  fi
done

# ---- the suite package: depends on every app; cleans up its repository when purged
M="$WORK/meta"
mkdir -p "$M/DEBIAN" "$M/usr/share/doc/folio-suite"
DEP="$(IFS=,; echo "${DEPENDS[*]}" | sed 's/,/, /g')"
cat > "$M/DEBIAN/control" <<CTL
Package: folio-suite
Version: $VERSION
Section: metapackages
Priority: optional
Architecture: all
Maintainer: Ron Shillings <ron.shillings@gmail.com>
Depends: $DEP
Description: Folio office suite: Writer, Sheets, Deliver, Post, Draw and Gable
 Installs the Folio apps together: Folio Writer (word processor), Folio Sheets
 (spreadsheet), Folio Deliver (presentations), Folio Post (mail), Folio Draw
 (pictures) and Folio Gable (3D modelling). Updates come from
 the suite's local repository through the normal Software Updater.
CTL
cat > "$M/DEBIAN/postrm" <<'SH'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
  rm -f /etc/apt/sources.list.d/folio-suite.list /usr/share/keyrings/folio-suite-archive-keyring.gpg
  rm -rf /var/lib/folio-suite
fi
SH
chmod 755 "$M/DEBIAN/postrm"
cp "$HERE/README.md" "$M/usr/share/doc/folio-suite/README.md"
dpkg-deb --root-owner-group --build -Zxz "$M" "$REPO/folio-suite_${VERSION}_all.deb" >/dev/null
cp "$REPO/folio-suite_${VERSION}_all.deb" "$OUT/"
echo "  folio-suite_${VERSION}_all.deb"

# ---- the repository index, signed
( cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null 2>/dev/null > Packages && gzip -9kn Packages )
python3 - "$REPO" "$VERSION" <<'PY'
import hashlib, os, sys, time
repo, ver = sys.argv[1], sys.argv[2]
files = ["Packages", "Packages.gz"]
lines = ["Origin: Folio", "Label: Folio Suite", "Suite: stable", "Version: " + ver,
         "Date: " + time.strftime("%a, %d %b %Y %H:%M:%S UTC", time.gmtime()),
         "Architectures: amd64 all", "Description: Folio Suite local repository"]
for algo, name in (("md5", "MD5Sum"), ("sha256", "SHA256")):
    lines.append(name + ":")
    for f in files:
        d = open(os.path.join(repo, f), "rb").read()
        lines.append(" %s %d %s" % (hashlib.new(algo, d).hexdigest(), len(d), f))
open(os.path.join(repo, "Release"), "w").write("\n".join(lines) + "\n")
PY
mkdir -p "$KEYHOME"; chmod 700 "$KEYHOME"
export GNUPGHOME="$KEYHOME"
if ! gpg --batch --list-secret-keys "Folio Suite" >/dev/null 2>&1; then
  gpg --batch --passphrase '' --quick-gen-key "Folio Suite Archive <ron.shillings@gmail.com>" ed25519 sign never >/dev/null 2>&1
fi
gpg --batch --yes --local-user "Folio Suite" --clearsign -o "$REPO/InRelease" "$REPO/Release"
gpg --batch --yes --local-user "Folio Suite" -abs -o "$REPO/Release.gpg" "$REPO/Release"
gpg --batch --export "Folio Suite" > "$WORK/payload/folio-suite-archive-keyring.gpg"
cp "$HERE/packaging/install.sh" "$WORK/payload/install.sh"
chmod 755 "$WORK/payload/install.sh"

# ---- one file: a script with the repository after it
RUN="$OUT/folio-suite-${VERSION}-installer.run"
{
  cat <<'HEAD'
#!/bin/sh
# Folio Suite installer. Run: sh folio-suite-*-installer.run   (asks for your password)
#   --remove      take the suite off again
#   --repo-only   update the local repository without installing (the Software Updater
#                 then offers the new versions)
set -e
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LINE=$(awk '/^__PAYLOAD__$/ {print NR + 1; exit 0}' "$0")
tail -n +"$LINE" "$0" | tar -xz -C "$TMP"
if [ "$(id -u)" -ne 0 ]; then
  if command -v pkexec >/dev/null 2>&1 && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then exec pkexec sh "$TMP/install.sh" "$@"; fi
  exec sudo sh "$TMP/install.sh" "$@"
fi
sh "$TMP/install.sh" "$@"
exit $?
__PAYLOAD__
HEAD
  tar -czf - -C "$WORK/payload" .
} > "$RUN"
chmod 755 "$RUN"
echo "Built $RUN"
