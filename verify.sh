#!/usr/bin/env bash
# Post-reboot check. Run as root (dmesg and ACPI sysfs status are root-only on most distros).
p() { printf '  %s\n' "$*"; }
echo "== Secure Boot / lockdown (the kernel refuses initrd ACPI tables under lockdown) =="
p "$(mokutil --sb-state 2>/dev/null || echo 'mokutil not installed')   lockdown: $(cat /sys/kernel/security/lockdown 2>/dev/null)"
echo "== Override table =="
dmesg | grep -E 'Table Upgrade|SSDT .*SPTOOFF' | sed 's/^/  /'
p "SPTOOFF lines: $(dmesg | grep -c SPTOOFF)   (expect >= 1; 0 = not loaded -> check lockdown and grub.cfg)"
echo "== Conflict messages (all should be 0) =="
p "can't claim: $(dmesg | grep -c "can't claim")   address conflict with AMDIF031: $(dmesg | grep -c 'address conflict with AMDIF031')   no space (excluding SR-IOV VF BARs): $(dmesg | grep 'no space' | grep -vc 'VF BAR')"
echo "== AMDIF031 devices (the one inside the bridge window should show _STA=0, platform-device=no) =="
for d in /sys/bus/acpi/devices/AMDIF031:*; do [ -e "$d" ] || continue
  p "$(basename "$d")  path=$(cat "$d/path")  _STA=$(cat "$d/status")  platform-device=$([ -e "/sys/bus/platform/devices/$(basename "$d")" ] && echo yes || echo no)"; done
echo "== Aquantia NICs (PCI vendor 1d6a) — both should have driver=atlantic =="
for d in /sys/bus/pci/devices/*; do [ "$(cat "$d/vendor")" = 0x1d6a ] || continue; n=$(ls "$d/net" 2>/dev/null | head -1)
  p "$(basename "$d")  driver=$([ -e "$d/driver" ] && basename "$(readlink -f "$d/driver")" || echo none)  iface=${n:-none}  $( [ -n "$n" ] && cat "/sys/class/net/$n/operstate")"; done
echo "== Chipset bridge 00:02.1 window (should be the BIOS layout, e.g. dc400000-ddafffff) =="
lspci -s 00:02.1 -v 2>/dev/null | grep -E 'Memory behind bridge' | sed 's/^\s*/  /'
