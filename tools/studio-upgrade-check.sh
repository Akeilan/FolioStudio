#!/bin/bash
# Studio 1.12.0 checks on one machine: 1.11.1 installed, then
#  (a) the Software Updater path: apt full-upgrade from the new package source brings the new apps;
#  (b) the installer path: the 1.12.0 installer over 1.11.1.
# Checks that Draw moves from the GTK version to the Rust one and that folio-fonts arrives with it.
#   tools/studio-upgrade-check.sh <machine> <display>
NEW=${NEW:-/home/claude/studio-out}
OLD=${OLD:-/home/claude/out/studio-1.11.1}
/home/claude/mounts.sh >/dev/null 2>&1
m=$1
d=$2
cp $OLD/folio-studio-1.11.1-installer.run $NEW/folio-studio-1.12.0-installer.run $m/tmp/
# fresh folders for this run, so nothing has to be cleared first
mkdir -p $m/tmp/newrepo-1120
cp -r $NEW/site/. $m/tmp/newrepo-1120/
flock /home/claude/.dpkg.lock chroot $m bash -c '
export DEBIAN_FRONTEND=noninteractive FOLIO_STUDIO_SOURCE=local
v() { dpkg-query -W -f="\${Version}" $1 2>/dev/null; }
sh /tmp/folio-studio-1.12.0-installer.run --remove >/dev/null 2>&1
sh /tmp/folio-studio-1.11.1-installer.run >/tmp/s0.log 2>&1 || tail -3 /tmp/s0.log
echo "before:    studio $(v folio-studio) draw $(v folio-draw) reel $(v folio-reel) cork $(v folio-cork) fonts $(v folio-fonts)"
echo "deb [trusted=yes] file:/tmp/newrepo-1120 ./" > /etc/apt/sources.list.d/folio-studio.list
apt-get update -qq >/dev/null 2>&1; apt-get -y full-upgrade >/tmp/up.log 2>&1 || tail -5 /tmp/up.log
echo "updater:   studio $(v folio-studio) draw $(v folio-draw) reel $(v folio-reel) cork $(v folio-cork) fonts $(v folio-fonts)"
# the GTK Draws files must be gone and the new command must work
d=/usr/lib/python3/dist-packages/folio_draw
if [ -d "$d" ]; then echo "  the old Python app is still there: $(ls -A $d | tr "\n" " ")"; else echo "  the old Python app is gone"; fi
folio-draw --version
sh /tmp/folio-studio-1.12.0-installer.run --remove >/dev/null 2>&1
sh /tmp/folio-studio-1.11.1-installer.run >/tmp/s0.log 2>&1 || tail -3 /tmp/s0.log
sh /tmp/folio-studio-1.12.0-installer.run >/tmp/s1.log 2>&1 || tail -3 /tmp/s1.log
echo "installer: studio $(v folio-studio) draw $(v folio-draw) reel $(v folio-reel) cork $(v folio-cork) fonts $(v folio-fonts) apps: $(ls /usr/share/applications | grep -c folio)"
folio-draw --version
'
# the new Draw really runs on that machine
chroot $m bash -c "rm -rf /tmp/draw-up; DISPLAY=:$d WAYLAND_DISPLAY= timeout 300 folio-draw --ui-test /tmp/draw-up 2>&1 | grep -E '^FAIL|passed'"
