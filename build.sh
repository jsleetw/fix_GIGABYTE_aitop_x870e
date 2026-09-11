#!/usr/bin/env bash
# Compile ssdt-sptooff.dsl into an uncompressed cpio archive that the kernel picks up as an
# ACPI table upgrade (CONFIG_ACPI_TABLE_UPGRADE) and install it into /boot.
#
#   sudo ./build.sh              -> /boot/acpi-override-spto.cpio
#   DEST=/tmp/out ./build.sh     -> build elsewhere (no root needed)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest=${DEST:-/boot}
name=acpi-override-spto.cpio
command -v iasl >/dev/null || { echo "iasl not found: install acpica-tools" >&2; exit 1; }
command -v cpio >/dev/null || { echo "cpio not found" >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/kernel/firmware/acpi"
iasl -p "$work/kernel/firmware/acpi/ssdt-sptooff" "$here/ssdt-sptooff.dsl" >/dev/null
( cd "$work" && find kernel | cpio -o -H newc --quiet > "$work/$name" )
mkdir -p "$dest"
install -m 0644 "$work/$name" "$dest/$name"
echo "Installed $dest/$name:"; cpio -tv < "$dest/$name" 2>/dev/null | grep aml
cat <<MSG

Next steps (GRUB):
  1. /etc/default/grub:   GRUB_EARLY_INITRD_LINUX_CUSTOM="$name"
     (remove pci=realloc from GRUB_CMDLINE_LINUX_DEFAULT if you added it while experimenting)
  2. sudo update-grub      # then: grep '$name' /boot/grub/grub.cfg
  3. reboot and run: sudo ./verify.sh
MSG
