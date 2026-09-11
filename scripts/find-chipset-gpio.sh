#!/usr/bin/env bash
# Locate the ACPI table(s) that define AMDIF031 devices and print a condensed disassembly, so you
# can confirm the ACPI path of the chipset GPIO device that sits inside a PCI bridge window and
# the name of the variable that gates its _STA (SPTS on GIGABYTE X870E AORUS XTREME AI TOP).
# Needs root (ACPI tables are 0400) and iasl (acpica-tools).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
command -v iasl >/dev/null || { echo "iasl not found: install acpica-tools" >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
for t in /sys/firmware/acpi/tables/DSDT /sys/firmware/acpi/tables/SSDT*; do
  [ -f "$t" ] || continue
  grep -aq AMDIF031 "$t" || continue
  cp "$t" "$work/$(basename "$t").dat"
done
cd "$work"
ls *.dat >/dev/null 2>&1 || { echo "no table mentions AMDIF031 — different platform?"; exit 1; }
for f in *.dat; do iasl -d "$f" >/dev/null 2>&1 || true; done
for dsl in *.dsl; do
  echo "=== ${dsl%.dsl}  (OEM: $(sed -n 's/^DefinitionBlock.*"SSDT", *[0-9]*, *"\([^"]*\)", *"\([^"]*\)".*/\1 \/ \2/p' "$dsl"))"
  grep -nE 'Scope|Device \(|_HID|_UID|Name \([A-Z0-9]{4}, |Memory32Fixed|0x[0-9A-F]{8}, |_STA|If \(|Return' "$dsl" | grep -vE 'GpioIo|_CRS\.RBUF' | head -40 | sed 's/^/  /'
done
echo
echo "Now compare with:  dmesg | grep -E \"can't claim|AMDIF031\""
echo "The device whose Memory32Fixed address falls inside the reported bridge window is the one to hide."
