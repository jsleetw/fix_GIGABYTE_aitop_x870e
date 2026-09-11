// Condensed disassembly of the two firmware SSDTs that define AMDIF031 devices (BIOS F13c).
// Both tables carry OEM ID "AMD" and OEM Table ID "AmdTable" -> the kernel's replace-by-ID is ambiguous.
// The 24-entry GpioIo lists are trimmed.

// ---- SSDT19: first chipset GPIO (PTIO) at fixed 0xFEC40000, outside any PCI window: harmless
DefinitionBlock ("", "SSDT", 2, "AMD", "AmdTable", 0x00000001)
{
    Scope (\_SB)
    {
        Name (TGPI, 0x0F)
        Device (PTIO)
        {
            Name (_HID, "AMDIF031")  // _HID: Hardware ID
            Name (_CID, "AMDIF031")  // _CID: Compatible ID
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0xFEC40000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                Return (RBUF) /* \_SB_.PTIO._CRS.RBUF */
            }
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }
        }
                    /* ... 24 x GpioIo ("\\_SB.PTIO") trimmed ... */
                Return (RBUF) /* \_SB_.ASMT._CRS.RBUF */
            }
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((TGPI == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }
}

// ---- SSDT20: second chipset GPIO (SPTO) at 0xDD500000, INSIDE the 00:02.1 bridge window: the culprit
DefinitionBlock ("", "SSDT", 2, "AMD", "AmdTable", 0x00000001)
{
    External (_SB_.PCI0.GPP7.UP00.DP40.UP00.DP68, DeviceObj)
    Scope (\_SB.PCI0.GPP7.UP00.DP40.UP00.DP68)
    {
        Name (SPTS, 0x01)
        Name (TSGP, 0x0F)
        Device (SPTO)
        {
            Name (_HID, "AMDIF031")  // _HID: Hardware ID
            Name (_CID, "AMDIF031")  // _CID: Compatible ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0xDD500000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                Return (RBUF) /* \_SB_.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTO._CRS.RBUF */
            }
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((SPTS == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
        Device (ASMP)
        {
            Name (_ADR, Zero)  // _ADR: Address
                    /* ... 24 x GpioIo ("\\_SB.PCI0.GPP7.UP00.DP40.UP00.DP68.SPTO") trimmed ... */
                Return (RBUF) /* \_SB_.PCI0.GPP7.UP00.DP40.UP00.DP68.ASMP._CRS.RBUF */
            }
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((TSGP == One))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }
}
