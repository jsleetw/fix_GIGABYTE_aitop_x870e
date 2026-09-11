/*
 * ssdt-sptooff.dsl — hide the second Promontory21 chipset GPIO controller (ACPI device SPTO,
 * _HID AMDIF031, _UID 2) from Linux on GIGABYTE X870E AORUS XTREME AI TOP (BIOS F13a / F13c).
 *
 * The firmware SSDT defines:
 *
 *   Scope (\_SB.PCI0.GPP7.UP00.DP40.UP00.DP68)
 *   {
 *       Name (SPTS, 0x01)
 *       Device (SPTO)
 *       {
 *           Name (_HID, "AMDIF031")
 *           Method (_CRS) { ... Memory32Fixed (ReadWrite, 0xDD500000, 0x00001000) ... }
 *           Method (_STA) { If ((SPTS == One)) { Return (0x0F) } Else { Return (Zero) } }
 *       }
 *   }
 *
 * 0xDD500000 lies inside the PCIe bridge 00:02.1 window (0xDC400000-0xDDAFFFFF). Linux inserts
 * the platform-device resource into the root of the iomem tree before it claims PCI bridge
 * windows, then refuses the window ("can't claim; address conflict with AMDIF031:00"),
 * releases the whole chipset subtree and re-allocates it into a smaller area where the second
 * Aquantia AQC113C NIC cannot get its 4 MB BAR ("can't assign; no space").
 *
 * This table is *appended*: its OEM ID / OEM Table ID match no firmware table, so the kernel's
 * initrd table-upgrade code adds it instead of replacing anything, and it is loaded after the
 * firmware SSDTs. Its only content is module-level code that clears SPTS, so SPTO._STA
 * evaluates to 0 when Linux scans the namespace: no platform device is created, no resource is
 * inserted, and the bridge window is claimed exactly as the BIOS laid it out.
 *
 * Why not simply add a _STA method in a new table?  SPTO already has one (AE_ALREADY_EXISTS).
 * Why not replace the firmware table?  SSDT19 and SSDT20 on this board carry the identical
 * OEM ID "AMD" / OEM Table ID "AmdTable", so the kernel's replace-by-ID matching is ambiguous.
 *
 * Cost: Linux loses the 24 GPIO lines of the second chipset (pinctrl driver "pt-gpio").
 * Nothing consumes them — the only ACPI consumer (device ASMP) is itself gated off by TSGP —
 * and the firmware keeps using the GPIO during POST regardless.
 *
 * Other boards: the ACPI path and the gate variable name may differ. Run
 * scripts/find-chipset-gpio.sh as root and adjust the two lines below.
 */
DefinitionBlock ("", "SSDT", 2, "FIXNIC", "SPTOOFF", 0x00000001)
{
    External (\_SB.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTS, IntObj)

    \_SB.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTS = Zero
}
