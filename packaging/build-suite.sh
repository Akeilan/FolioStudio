#!/bin/bash
# Builds the Folio Studio installer (formerly Folio Suite): one file that installs Page, Sheet,
# Show, Post, Draw, Gable and Chord through a local apt repository, so later versions arrive
# through the normal Software Updater.
#
#   packaging/build-suite.sh <folder with the app .debs> [output folder]
#
# Makes folio-studio_<ver>_all.deb (depends on every app), the transitional folio-suite package,
# a signed apt repository holding the newest .deb of each package (and the transitional packages
# for the old app names), and folio-studio-<ver>-installer.run around it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEBS="$(cd "$1" && pwd)"
OUT="$(mkdir -p "${2:-$HERE/out}" && cd "${2:-$HERE/out}" && pwd)"
VERSION="$(cat "$HERE/VERSION")"
KEYHOME="${FOLIO_SUITE_KEYS:-$HOME/.folio-suite-signing}"
# the online package source the installer points apt at (tools/publish.sh puts the repository there)
SOURCE_URL="${FOLIO_STUDIO_SOURCE:-https://akeilan.github.io/FolioStudio/}"
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
for p in folio-page folio-sheet folio-show folio-post folio-draw folio-gable folio-chord; do
  f="$(newest $p)"
  [ -n "$f" ] || { echo "missing $p in $DEBS" >&2; exit 1; }
  cp "$f" "$REPO/"
  DEPENDS+=("$p (>= $(dpkg-deb -f "$f" Version))")
  echo "  $(basename "$f")"
done
# the old app names, now transitional packages: kept in the repository so an upgrade moves over
for p in folio-writer folio-sheets folio-deliver; do
  f="$(newest $p)"
  if [ -n "$f" ] && [ "$(dpkg-deb -f "$f" Architecture)" = all ]; then cp "$f" "$REPO/"; echo "  $(basename "$f") (transitional)"; fi
done

# ---- the studio package: depends on every app; cleans up its repository when purged
meta() {  # name, depends, description...
  local name="$1" dep="$2"; shift 2
  local M="$WORK/meta-$name"
  mkdir -p "$M/DEBIAN" "$M/usr/share/doc/$name"
  { echo "Package: $name"; echo "Version: $VERSION"; echo "Section: metapackages"; echo "Priority: optional"
    echo "Architecture: all"; echo "Maintainer: Ron Shillings <ron.shillings@gmail.com>"; echo "Depends: $dep"
    printf '%s\n' "$@"; } > "$M/DEBIAN/control"
  cp "$HERE/README.md" "$M/usr/share/doc/$name/README.md"
  if [ "$name" = folio-studio ]; then
    cat > "$M/DEBIAN/postrm" <<'SH'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
  rm -f /etc/apt/sources.list.d/folio-studio.list /usr/share/keyrings/folio-studio-archive-keyring.gpg
  rm -rf /var/lib/folio-studio
fi
SH
    chmod 755 "$M/DEBIAN/postrm"
  fi
  dpkg-deb --root-owner-group --build -Zxz "$M" "$REPO/${name}_${VERSION}_all.deb" >/dev/null
  cp "$REPO/${name}_${VERSION}_all.deb" "$OUT/"
  echo "  ${name}_${VERSION}_all.deb"
}
DEP="$(IFS=,; echo "${DEPENDS[*]}" | sed 's/,/, /g')"
meta folio-studio "$DEP" \
  "Breaks: folio-suite (<< $VERSION)" \
  "Description: Folio Studio: Page, Sheet, Show, Post, Draw, Gable and Chord" \
  " Installs the Folio apps together: Folio Page (word processor), Folio Sheet" \
  " (spreadsheet), Folio Show (presentations), Folio Post (mail), Folio Draw" \
  " (pictures), Folio Gable (3D modelling) and Folio Chord (music, radio and" \
  " podcasts). Updates come from the Folio" \
  " Studio package source through the normal Software Updater."
meta folio-suite "folio-studio (>= $VERSION)" "Description: transitional package: Folio Suite is now Folio Studio" \
  " This package can be removed safely."

# ---- the repository index, signed
( cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null 2>/dev/null > Packages && gzip -9kn Packages )
python3 - "$REPO" "$VERSION" <<'PY'
import hashlib, os, sys, time
repo, ver = sys.argv[1], sys.argv[2]
files = ["Packages", "Packages.gz"]
lines = ["Origin: Folio", "Label: Folio Studio", "Suite: stable", "Version: " + ver,
         "Date: " + time.strftime("%a, %d %b %Y %H:%M:%S UTC", time.gmtime()),
         "Architectures: amd64 all", "Description: Folio Studio packages"]
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
gpg --batch --export "Folio Suite" > "$WORK/payload/folio-studio-archive-keyring.gpg"
echo "$SOURCE_URL" > "$WORK/payload/source-url"
# the same signed repository, for tools/publish.sh
rm -rf "$OUT/site"; cp -r "$REPO" "$OUT/site"
cp "$WORK/payload/folio-studio-archive-keyring.gpg" "$OUT/site/"   # the public key, for adding the source by hand
cp "$HERE/packaging/install.sh" "$WORK/payload/install.sh"
chmod 755 "$WORK/payload/install.sh"

# ---- one file: a script with the repository after it
RUN="$OUT/folio-studio-${VERSION}-installer.run"
{
  cat <<'HEAD'
#!/bin/sh
# Folio Studio installer. Run: sh folio-studio-*-installer.run   (asks for your password)
#   --remove      take Folio Studio off again
#   --repo-only   set up the package source without installing (the Software Updater
#                 then offers the new versions)
#   --old-formats also install LibreOffice's converter for old file formats (not needed otherwise)
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
