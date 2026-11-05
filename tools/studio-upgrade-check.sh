#!/bin/bash
# Studio 1.11.1 checks on one machine: 1.11.0 installed, then
#  (a) the Software Updater path: apt upgrade from the new package source brings the new apps;
#  (b) the installer path: the 1.11.1 installer over 1.11.0.
# Then run-tests.sh --quick --only cork,suite.   studio_1111.sh <machine> <display>
NEW=/home/claude/out/studio-1.11.1
OLD=/home/claude/out/studio-1.11.0
/home/claude/mounts.sh >/dev/null 2>&1
m=$1
d=$2
cp $OLD/folio-studio-1.11.0-installer.run $NEW/folio-studio-1.11.1-installer.run $m/tmp/
# fresh folders for this run, so nothing has to be cleared first
mkdir -p $m/tmp/newrepo-1111 $m/tmp/folio-src-1111/folio-writer
cp -r $NEW/site/. $m/tmp/newrepo-1111/
flock /home/claude/.dpkg.lock chroot $m bash -c '
export DEBIAN_FRONTEND=noninteractive FOLIO_STUDIO_SOURCE=local
v() { dpkg-query -W -f="\${Version}" $1 2>/dev/null; }
sh /tmp/folio-studio-1.11.0-installer.run --remove >/dev/null 2>&1
sh /tmp/folio-studio-1.11.0-installer.run >/tmp/s0.log 2>&1 || tail -3 /tmp/s0.log
echo "before: studio $(v folio-studio) page $(v folio-page) sheet $(v folio-sheet) show $(v folio-show) cork $(v folio-cork)"
echo "deb [trusted=yes] file:/tmp/newrepo-1111 ./" > /etc/apt/sources.list.d/folio-studio.list
apt-get update -qq >/dev/null 2>&1; apt-get -y full-upgrade >/tmp/up.log 2>&1 || tail -3 /tmp/up.log
echo "updater: studio $(v folio-studio) page $(v folio-page) sheet $(v folio-sheet) show $(v folio-show) cork $(v folio-cork)"
sh /tmp/folio-studio-1.11.1-installer.run --remove >/dev/null 2>&1
sh /tmp/folio-studio-1.11.0-installer.run >/tmp/s0.log 2>&1 || tail -3 /tmp/s0.log
sh /tmp/folio-studio-1.11.1-installer.run >/tmp/s1.log 2>&1 || tail -3 /tmp/s1.log
echo "installer: studio $(v folio-studio) page $(v folio-page) sheet $(v folio-sheet) show $(v folio-show) cork $(v folio-cork) post=$(dpkg -s folio-post >/dev/null 2>&1 && echo installed || echo absent) apps: $(ls /usr/share/applications | grep -c folio)"
'
cp -r /home/claude/folio-suite $m/tmp/folio-src-1111/
cp -r /home/claude/folio-writer/tests $m/tmp/folio-src-1111/folio-writer/
chroot $m env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root DISPLAY=:$d WRITER_SRC=/tmp/folio-src-1111/folio-writer \
  bash /tmp/folio-src-1111/folio-suite/run-tests.sh --quick --only cork,suite 2>&1 | tail -8
