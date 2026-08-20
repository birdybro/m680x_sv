"""Independent HD63701V0 legal-mode digital device model.

The HD63701V0 reuses documented HD6301-family execution and peripherals while
selecting its 192-byte RAM map and framing-error transfer rule. The manual's
Mode-5/7 address-error rows conflict with that RAM map for 0040-007F; this
model permits instruction fetches throughout physical RAM and records that
choice as an implementation policy rather than verified silicon behavior.
"""

from __future__ import annotations

from model.common import Memory
from model.hd6301v1_device import HD6301V1DeviceModel


class HD63701V0DeviceModel(HD6301V1DeviceModel):
    """Specification-derived model of every legal HD63701V0 MCU mode."""

    def __init__(
        self,
        operating_mode: int = 7,
        *,
        external_memory: Memory | None = None,
        program_memory: Memory | None = None,
    ) -> None:
        if operating_mode not in {0, 1, 2, 5, 6, 7}:
            raise ValueError(
                "HD63701V0 operating mode must be 0, 1, 2, 5, 6, or 7"
            )
        super().__init__(
            operating_mode,
            external_memory=external_memory,
            program_memory=program_memory,
        )
        self.transfer_framing_error = True
        self.internal_ram_start = 0x0040
        self.ram = bytearray(192)
        # The table includes physical RAM at 0040-007F for Modes 5 and 7.
        # The documented memory map/prose wins at this normalized boundary.
        self.mode57_address_trap_low_end = 0x003F


class HD63701V0Mode7Model(HD63701V0DeviceModel):
    """Backward-compatible name for the single-chip Mode-7 profile."""

    def __init__(self, *, program_memory: Memory | None = None) -> None:
        super().__init__(7, program_memory=program_memory)
