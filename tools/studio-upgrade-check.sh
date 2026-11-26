#!/bin/bash
# The two ways a Studio release reaches a computer that has the previous one, checked on one machine:
#  (a) the Software Updater: apt full-upgrade from the new package source;
#  (b) the installer: the new installer run over the old Studio.
# Each ends with every package at the version the new source holds and the discontinued apps gone.
#   tools/studio-upgrade-check.sh <machine> <old build folder> <new build folder>
# A build folder is what packaging/build-suite.sh writes: the installer and site/.
set -u
m=${1:?machine, e.g. /srv/jammy}
OLD=${2:?the previous build folder}
NEW=${3:?the new build folder}
OLDRUN=$(ls "$OLD"/folio-studio-*-installer.run | head -1)
NEWRUN=$(ls "$NEW"/folio-studio-*-installer.run | head -1)
/home/claude/mounts.sh >/dev/null 2>&1
rm -rf "$m/tmp/upcheck"; mkdir -p "$m/tmp/upcheck/site"
cp "$OLDRUN" "$m/tmp/upcheck/old.run"
cp "$NEWRUN" "$m/tmp/upcheck/new.run"
cp -r "$NEW/site/." "$m/tmp/upcheck/site/"
# what the new source holds: package and version, one a line
# (the third field says "gone" for a discontinued app's empty package, "app" for the rest)
for f in "$NEW"/site/*.deb; do
  kind=app; dpkg-deb -f "$f" Description | head -1 | grep -q "has been discontinued" && kind=gone
  echo "$(dpkg-deb -f "$f" Package) $(dpkg-deb -f "$f" Version) $kind"
done \
  > "$m/tmp/upcheck/want.txt"
flock /home/claude/.dpkg.lock chroot "$m" bash -c '
export DEBIAN_FRONTEND=noninteractive
U=/tmp/upcheck
fails=0
judge() {   # how: every package installed is at the new version; discontinued ones are empty or gone
  while read -r p want kind; do
    have=$(dpkg-query -W -f="\${Status} \${Version}" "$p" 2>/dev/null | sed -n "s/^install ok installed //p")
    if [ "$kind" = gone ]; then
      [ -z "$have" ] || [ "$have" = "$want" ] || { echo "FAIL $1: $p $have is still the app, not the discontinued $want"; fails=$((fails+1)); }
      [ -e "/usr/bin/$p" ] && { echo "FAIL $1: /usr/bin/$p is still there"; fails=$((fails+1)); }
    elif [ -n "$have" ] && [ "$have" != "$want" ]; then
      echo "FAIL $1: $p is $have, the new source has $want"; fails=$((fails+1))
    fi
  done < $U/want.txt
  studio=$(dpkg-query -W -f="\${Version}" folio-studio 2>/dev/null)
  echo "$1: folio-studio $studio, $(ls /usr/share/applications | grep -c "^org.folio") app menu entries"
}
clean() { sh $U/new.run --remove >/dev/null 2>&1; sh $U/old.run --remove >/dev/null 2>&1; }
# (a) the Software Updater
clean
sh $U/old.run >$U/old.log 2>&1 || { echo "FAIL the old installer"; tail -3 $U/old.log; }
echo "before: folio-studio $(dpkg-query -W -f="\${Version}" folio-studio 2>/dev/null)"
cp $U/site/folio-studio-archive-keyring.gpg /usr/share/keyrings/folio-upcheck.gpg
echo "deb [signed-by=/usr/share/keyrings/folio-upcheck.gpg] file:$U/site ./" > /etc/apt/sources.list.d/folio-upcheck.list
# only the new source is read: the online one is what is being replaced
apt-get update -qq -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=- \
  -o Dir::Etc::SourceParts=/etc/apt/sources.list.d >/dev/null 2>&1
apt-get -y -q -o Dir::Etc::sourcelist=/dev/null full-upgrade >$U/up.log 2>&1 || { echo "FAIL full-upgrade"; tail -5 $U/up.log; }
judge updater
rm -f /etc/apt/sources.list.d/folio-upcheck.list /usr/share/keyrings/folio-upcheck.gpg
# (b) the installer over the old Studio
clean
sh $U/old.run >$U/old.log 2>&1
sh $U/new.run >$U/new.log 2>&1 || { echo "FAIL the new installer"; tail -3 $U/new.log; }
judge installer
[ $fails = 0 ] && echo "UPGRADE all passed" || echo "UPGRADE FAILED: $fails"
'
