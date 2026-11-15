#!/bin/bash
# The on-disk repository must keep verifying after the archive signing key is rotated.
#
# Until 1.20.1 install.sh signed both the online source and file:/var/lib/folio-studio with
# /usr/share/keyrings/folio-studio-archive-keyring.gpg. Replacing that keyring after a re-key --
# which is what the package page tells people to do -- left the on-disk index unverifiable, and
# apt reported NO_PUBKEY for file:/var/lib/folio-studio on every update from then on.
#
#   tests/keyring_rotation.sh [machine]       default /srv/jammy; RUN= the installer
set -u
M=${1:-/srv/jammy}
RUN=${RUN:-$(ls -t /home/claude/suite-out/folio-studio-*-installer.run 2>/dev/null | head -1)}
[ -f "$RUN" ] || { echo "no installer: build one with packaging/build-suite.sh"; exit 2; }
KEY=/usr/share/keyrings/folio-studio-archive-keyring.gpg
LOCAL_KEY=/usr/share/keyrings/folio-studio-local-keyring.gpg
LIST=/etc/apt/sources.list.d/folio-studio.list
pass=0; fail=0
ck() {  # $2 is a count or 0/1: anything but 0 passes
  if [ "${2:-0}" != 0 ]; then pass=$((pass+1)); echo "  PASS $1"
  else fail=$((fail+1)); echo "  FAIL $1${3:+ | $3}"; fi
}

# a key that is not the archive key, standing in for the one a re-key publishes
OTHER=$(mktemp -d); chmod 700 "$OTHER"
GNUPGHOME=$OTHER gpg --batch --passphrase '' --quick-gen-key "Folio Rotated <r@example.invalid>" ed25519 sign never >/dev/null 2>&1
GNUPGHOME=$OTHER gpg --batch --export "Folio Rotated" > "$M/tmp/rotated-keyring.gpg"
cp "$RUN" "$M/tmp/studio-installer.run"

# --repo-only sets up the repository and the source list without installing the apps
cat > "$M/tmp/kr.sh" <<'SH'
set -u
# an address nothing answers on, so the installer keeps its on-disk copy as well
FOLIO_STUDIO_SOURCE=https://127.0.0.1:9/ sh /tmp/studio-installer.run --repo-only >/tmp/kr-install.log 2>&1
echo "LIST:"; cat /etc/apt/sources.list.d/folio-studio.list
echo "KEYRINGS: $(ls /usr/share/keyrings/folio-studio-*-keyring.gpg 2>/dev/null | tr '\n' ' ')"
# the re-key: the published archive keyring is replaced by a different key
cp /tmp/rotated-keyring.gpg /usr/share/keyrings/folio-studio-archive-keyring.gpg
echo "AFTER-ROTATION:"
apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/folio-studio.list \
               -o Dir::Etc::sourceparts=/dev/null -o APT::Get::List-Cleanup=0 2>&1 |
  grep -iE 'NO_PUBKEY|InRelease|^W:|^E:' | sed 's/^/  /'
SH
out=$(flock /home/claude/.dpkg.lock chroot "$M" bash /tmp/kr.sh 2>&1)
echo "$out" | sed 's/^/    /'

echo "-- checks"
ck "the on-disk repository is in the source list" \
   "$(echo "$out" | grep -c "file:/var/lib/folio-studio")" 
ck "it is signed by a keyring of its own, not the archive keyring" \
   "$(echo "$out" | grep "file:/var/lib/folio-studio" | grep -c "signed-by=$LOCAL_KEY")"
ck "both keyrings are installed" \
   "$(echo "$out" | grep -c "KEYRINGS:.*local-keyring")"
ck "rotating the archive key leaves the on-disk repository verifiable" \
   "$([ "$(echo "$out" | sed -n '/AFTER-ROTATION:/,$p' | grep -c 'NO_PUBKEY')" = 0 ] && echo 1 || echo 0)" \
   "$(echo "$out" | sed -n '/AFTER-ROTATION:/,$p' | grep -m1 NO_PUBKEY)"

# a machine already in the broken state: installing over it must repair the layout
if [ -n "${PREV_RUN:-}" ] && [ -f "$PREV_RUN" ]; then
  cp "$PREV_RUN" "$M/tmp/studio-prev.run"
  rep=$(flock /home/claude/.dpkg.lock chroot "$M" bash -c '
    FOLIO_STUDIO_SOURCE=https://127.0.0.1:9/ sh /tmp/studio-prev.run --repo-only >/dev/null 2>&1
    FOLIO_STUDIO_SOURCE=https://127.0.0.1:9/ sh /tmp/studio-installer.run --repo-only >/dev/null 2>&1
    grep "file:/var/lib/folio-studio" /etc/apt/sources.list.d/folio-studio.list')
  ck "installing over the old layout repairs it" \
     "$(echo "$rep" | grep -c "signed-by=$LOCAL_KEY")" "$rep"
fi

# the ordinary path: a source that answers leaves no on-disk copy and no keyring for it
cp -r /home/claude/suite-out/site "$M/tmp/onlinerepo" 2>/dev/null || true
on=$(flock /home/claude/.dpkg.lock chroot "$M" bash -c '
  FOLIO_STUDIO_SOURCE=file:/tmp/onlinerepo sh /tmp/studio-installer.run --repo-only >/tmp/kr2.log 2>&1
  echo "LIST: $(cat /etc/apt/sources.list.d/folio-studio.list | tr "\n" "|")"
  echo "REPO-LEFT: $([ -d /var/lib/folio-studio ] && echo yes || echo no)"
  echo "LOCALKEY-LEFT: $([ -f /usr/share/keyrings/folio-studio-local-keyring.gpg ] && echo yes || echo no)"')
echo "$on" | sed 's/^/    /'
ck "a source that answers is the only one left" \
   "$([ "$(echo "$on" | grep -c 'LIST:.*file:/var/lib/folio-studio')" = 0 ] && echo 1 || echo 0)"
ck "no on-disk copy is left behind" "$(echo "$on" | grep -c 'REPO-LEFT: no')"
ck "no keyring for it is left behind" "$(echo "$on" | grep -c 'LOCALKEY-LEFT: no')"

# --remove takes both keyrings away
left=$(flock /home/claude/.dpkg.lock chroot "$M" bash -c "sh /tmp/studio-installer.run --remove >/dev/null 2>&1; ls /usr/share/keyrings/folio-studio-*-keyring.gpg 2>/dev/null | wc -l")
ck "--remove takes both keyrings away" "$([ "$left" = 0 ] && echo 1 || echo 0)" "$left left"
rm -rf "$OTHER"
echo "keyring_rotation: pass=$pass fail=$fail"
[ "$fail" = 0 ]
