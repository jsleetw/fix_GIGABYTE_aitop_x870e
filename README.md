# Second onboard 10GbE NIC missing under Linux on GIGABYTE X870E AORUS XTREME AI TOP — root cause and a 114-byte fix

**TL;DR.** On this board (and by the same mechanism on other AMD X870E boards with two Promontory21 chipsets — ASRock X870E Taichi is reported in [kernel Bugzilla #220767](https://bugzilla.kernel.org/show_bug.cgi?id=220767)) Linux brings up only **one** of the two onboard Aquantia/Marvell AQC113C NICs, and *which one* changes between boots. The BIOS declares the second chipset's GPIO controller (ACPI `AMDIF031`, device `SPTO`) at a fixed MMIO address that sits **inside** the chipset PCIe bridge window. Linux refuses that bridge window, re-allocates the whole chipset subtree into a smaller area, and the losing NIC never gets its 4 MB BAR (`can't assign; no space`).

The fix is a **114-byte SSDT loaded from the initrd** that clears the firmware's own gate variable so `SPTO._STA` returns 0. Linux then never inserts the conflicting resource, claims the BIOS bridge layout as-is, and both NICs come up every boot. No kernel patch, no BIOS modification, fully reversible.

GIGABYTE's reply to the bug report: *the board only supports Windows 11*. The kernel maintainers rejected a device-specific quirk for `AMDIF031` in October 2025 with *fix the firmware*. Neither side is going to move, so this repo is the practical workaround.

Tested on: X870E AORUS XTREME AI TOP rev 1.x, BIOS F13a and F13c, Ryzen 9 9950X3D, Ubuntu 26.04, kernel 7.0.0-30 (dracut initramfs, GRUB).

---

## Symptoms

```
pci 0000:00:02.1: bridge window [mem 0xdc400000-0xddafffff]: can't claim; address conflict with AMDIF031:00 [mem 0xdd500000-0xdd500fff]
pci 0000:03:00.0: bridge window [mem 0xdc400000-0xddafffff]: can't claim; no compatible bridge window
... (every bridge and BAR under the chipset: "can't claim; no compatible bridge window")
pci 0000:10:00.0: BAR 4 [mem size 0x00400000 64bit]: can't assign; no space
atlantic 0000:10:00.0: probe with driver atlantic failed with error -5
```

One AQC113C works, the other has no driver bound and no interface. Full log: [`evidence/dmesg-before.txt`](evidence/dmesg-before.txt).

Windows does not show this. Its PnP arbiter allocates the `SPTO` resource from its parent bridge's window, following the ACPI namespace hierarchy. So "reproduce it on Windows" is not possible, even though the root cause is the same ACPI table.

## Root cause (three layers)

1. **Firmware declaration.** The second chipset's GPIO block is physically behind the chipset PCIe switch, so its registers *must* live inside that bridge window. The BIOS (`SSDT20`) declares it as an ACPI platform device with `Memory32Fixed(0xDD500000, 0x1000)`, and names it as a child of the PCIe downstream port `DP68`. Hardware-wise that is legitimate. The first chipset's equivalent (`PTIO`, `SSDT19`) sits at `0xFEC40000`, outside any PCI window, and is harmless. See [`evidence/firmware-ssdt-excerpt.dsl`](evidence/firmware-ssdt-excerpt.dsl).
2. **Linux ordering.** `platform_device_add()` inserts platform-device resources at the *root* of the iomem tree during the ACPI scan. Later, `pci_claim_resource()` for bridge `00:02.1` finds a foreign resource inside its range and refuses the whole window. The kernel then releases every window in the chipset subtree (both NICs, WiFi, NVMe, USB, SATA) and re-plans them from scratch.
3. **Re-planning falls short.** Each NIC needs a 5 MB bridge window aligned to its largest BAR (4 MB). The re-planned space for the upstream switch is 15 MB; after the first NIC takes its slot, the remaining 5 MB does not start on a 4 MB boundary and the allocator reports `no space`. Which NIC wins is enumeration order, i.e. a coin toss per boot.

Nothing here is time- or power-dependent: power-cycling does not help, and `pci=realloc`, `pnpacpi=off`, disabling USB4 in the BIOS and updating F13a → F13c all change nothing.

## The fix

[`ssdt-sptooff.dsl`](ssdt-sptooff.dsl):

```asl
DefinitionBlock ("", "SSDT", 2, "FIXNIC", "SPTOOFF", 0x00000001)
{
    External (\_SB.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTS, IntObj)

    \_SB.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTS = Zero
}
```

The firmware's own `SPTO._STA` is `If (SPTS == One) Return (0x0F) Else Return (Zero)`. This table is **appended** via the kernel's initrd ACPI table upgrade (its OEM ID / Table ID match no firmware table, so nothing is replaced), loads after the firmware SSDTs, and its module-level code clears `SPTS`. When Linux scans the namespace, `SPTO` reports "not present": no platform device, no resource inserted, bridge window claimed exactly as the BIOS laid it out.

Why not something simpler?

- *Add a `_STA` in a new table* — `SPTO` already has one; AML cannot redefine it (`AE_ALREADY_EXISTS`).
- *Replace `SSDT20`* — `SSDT19` and `SSDT20` both carry OEM ID `AMD` / Table ID `AmdTable`; the kernel's replace-by-ID matching is ambiguous and could swap the wrong table.
- *Kernel boot parameter* — there is none that hides a single ACPI device.

What you lose: Linux no longer sees the 24 GPIO lines of the second chipset (`pt-gpio` driver). On this board nothing uses them: the only ACPI consumer (`ASMP`, an ASMedia helper device) is itself gated off by `TSGP`, and the firmware keeps using the GPIO during POST regardless of what the OS does.

## Install (GRUB; works with dracut or initramfs-tools because GRUB loads the cpio as a separate early initrd)

Prerequisites: `acpica-tools` (for `iasl`), `cpio`, kernel with `CONFIG_ACPI_TABLE_UPGRADE=y` (Ubuntu/Fedora/Arch have it), **Secure Boot disabled** — kernel lockdown refuses ACPI tables from the initrd, silently.

1. Confirm your board has the same layout (path and gate variable):
   ```
   sudo scripts/find-chipset-gpio.sh
   ```
   Look for the `AMDIF031` device whose `Memory32Fixed` address falls inside the bridge window reported by `dmesg | grep "can't claim"`, and note the variable tested in its `_STA`. If either differs, edit the two lines in `ssdt-sptooff.dsl`.
2. Build and install the cpio:
   ```
   sudo ./build.sh          # -> /boot/acpi-override-spto.cpio
   ```
3. Tell GRUB to load it before the main initrd. In `/etc/default/grub`:
   ```
   GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi-override-spto.cpio"
   ```
   (also remove `pci=realloc` if you added it while experimenting), then `sudo update-grub` and check `grep acpi-override /boot/grub/grub.cfg`.
4. Optional but recommended if your two NICs feed a bridge/bond: see [Interface naming race](#interface-naming-race-two-nics--netplan-set-name--dracut) below.
5. Reboot, then:
   ```
   sudo ./verify.sh
   ```

Expected after reboot ([`evidence/dmesg-after.txt`](evidence/dmesg-after.txt)):

```
ACPI: Table Upgrade: install [SSDT-FIXNIC- SPTOOFF]
ACPI: SSDT 0x... 000072 (v02 FIXNIC SPTOOFF  00000001 INTL 20251212)
```
- `dmesg | grep -c "can't claim"` → 0
- `/sys/bus/acpi/devices/AMDIF031:00/status` → 0, and no `AMDIF031:00` under `/sys/bus/platform/devices/`
- both `1d6a:14c0` devices bound to `atlantic`, BARs at their BIOS addresses (`0xdc400000…`, `0xdcc00000…`)
- `lspci -s 00:02.1 -v` → `Memory behind bridge: dc400000-ddafffff`

## Test it live, without rebooting

`acpi_configfs` lets you load the same table at runtime. It will not free the already-allocated resources (that needs a reboot), but it proves the AML does what you expect on your firmware:

```
sudo modprobe acpi_configfs
DEST=/tmp/t ./build.sh && cd /tmp/t && cpio -id < acpi-override-spto.cpio
sudo mkdir /sys/kernel/config/acpi/table/sptooff
sudo sh -c 'cat kernel/firmware/acpi/ssdt-sptooff.aml > /sys/kernel/config/acpi/table/sptooff/aml'
cat /sys/bus/acpi/devices/AMDIF031:00/status     # 15 before, 0 after
```

## Rollback

Delete the `GRUB_EARLY_INITRD_LINUX_CUSTOM` line, `sudo update-grub`, reboot. Nothing else is touched.

## Interface naming race (two NICs + netplan `set-name` + dracut)

Once both NICs are present you may hit a second, unrelated problem. The dracut initramfs contains systemd's `99-default.link`, so interfaces get their PCI-path names (`enp15s0`, `enp16s0`) at ~3 s, inside the initramfs. netplan's `set-name` `.link` files only appear in the real root a few seconds later. On this board the second NIC's path name (`enp16s0` = bus 0x10) is exactly the name netplan wants to give the *first* NIC, so that rename fails and a bridge built on `enp16s0` has no member.

Fix: pin names by permanent MAC in `/etc/systemd/network/` **and copy those files into the initramfs**, so the very first udev pass already produces the final names (`eth0 → enp16s0`, `eth1 → enp17s0`, no intermediate names, no clash):

- [`examples/10-nic-primary.link`](examples/10-nic-primary.link), [`examples/10-nic-secondary.link`](examples/10-nic-secondary.link) → `/etc/systemd/network/`
- dracut: [`examples/90-nic-link.conf`](examples/90-nic-link.conf) → `/etc/dracut.conf.d/`, then `sudo dracut -f`
- initramfs-tools: [`examples/initramfs-tools-hook.sh`](examples/initramfs-tools-hook.sh) → `/etc/initramfs-tools/hooks/nic-link` (untested), then `sudo update-initramfs -u`

## Things that did not work (so you can skip them)

| Attempt | Result |
|---|---|
| `pci=realloc` | no change: the conflict is not about space |
| `pnpacpi=off` | no change: `AMDIF031` is an ACPI platform device, not PNP |
| Disable USB4 / ASM4242 in BIOS (frees ~776 MB of MMIO) | no change |
| BIOS F13a → F13c | identical tables, identical conflict |
| Power off for minutes ("firmware hang") | the NIC firmware was never hung; MMIO simply was not routed |
| Kernel module that claims a 5 MB window for the losing NIC's downstream port, then rescans | works by hand; from a cold boot the BARs stay unassigned. Also, one wrong `rescan` on an empty bus released every window in the chipset subtree and took the NVMe and both VMs down. Do not do this on a live machine. |

## References

- Kernel Bugzilla #220767 — ASRock X870E Taichi, identical message: <https://bugzilla.kernel.org/show_bug.cgi?id=220767>
- LKML, Oct 2025, `kernel: resource: Add conditional handling for ACPI device` (AMDIF031 quirk, NAKed): <https://lkml.iu.edu/2510.3/02842.html>
- Kernel documentation, *Upgrading ACPI tables via initrd*: <https://docs.kernel.org/admin-guide/acpi/initrd_table_override.html>

## License

MIT — see [LICENSE](LICENSE).

---

## 繁體中文摘要

**症狀**：X870E AORUS XTREME AI TOP 在 Linux 下兩顆板載 AQC113C 10G 網卡只有一顆能用，而且每次開機死的可能不同顆。dmesg 關鍵字：`can't claim; address conflict with AMDIF031:00`、`can't assign; no space`。

**根因**：BIOS 把第二顆晶片組的 GPIO 裝置（`SPTO`，_HID `AMDIF031`）宣告在 `0xDD500000`，正好落在晶片組 PCIe 橋 `00:02.1` 的視窗內。Linux 先把平台裝置資源插進 iomem 根層，之後認領橋視窗判定衝突、整棵子樹放掉重排；重排時兩顆網卡各要 5 MB 且 4 MB 對齊，只夠塞一顆。Windows 依 ACPI 命名空間父子關係配資源所以不會重現；技嘉回覆「僅支援 Windows 11」，核心端的 quirk 也被退，兩邊都不會修。ASRock X870E Taichi 有一模一樣的回報（kernel Bugzilla #220767）。

**解法**：新增一張 114 bytes 的 SSDT，載入時把韌體自己的變數 `SPTS` 清 0，`SPTO._STA` 就回 0 → Linux 不建平台裝置 → 橋視窗按 BIOS 配置認領 → 兩顆網卡每次都在。不改 BIOS、不改核心，刪一行 GRUB 設定即可回滾。代價只有 OS 少 24 條沒人用的 GPIO。

**安裝**：`sudo ./build.sh` → `/etc/default/grub` 加 `GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi-override-spto.cpio"` → `update-grub` → 重開 → `sudo ./verify.sh`。**Secure Boot 必須關閉**，否則核心會靜默拒載 initrd 內的 ACPI 表。兩顆網卡都在之後若有 bridge/bond，另外注意 initramfs 內的路徑命名會撞名，用 `examples/` 的 .link 依 MAC 鎖名並塞進 initramfs。
