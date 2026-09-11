#!/bin/sh
# /etc/initramfs-tools/hooks/nic-link — equivalent for Debian/Ubuntu initramfs-tools (untested here;
# this machine uses dracut). Copies the .link files so udev applies them inside the initramfs.
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p "$DESTDIR/etc/systemd/network"
cp /etc/systemd/network/10-nic-*.link "$DESTDIR/etc/systemd/network/"
