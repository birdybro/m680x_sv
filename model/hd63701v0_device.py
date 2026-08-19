"""Independent HD63701V0 single-chip Mode-7 digital device model.

The HD63701V0 reuses documented HD6301-family execution and peripherals while
selecting its 192-byte RAM map and framing-error transfer rule. The manual's
Mode-7 address-error table conflicts with that RAM map for 0040-007F; this
model permits instruction fetches throughout physical RAM and records that
choice as an implementation policy rather than verified silicon behavior.
"""

from __future__ import annotations

from model.common import Memory
from model.hd6301v1_device import HD6301V1Mode7Model


class HD63701V0Mode7Model(HD6301V1Mode7Model):
    """Specification-derived model of the HD63701V0 Mode-7 boundary."""

    def __init__(self, *, program_memory: Memory | None = None) -> None:
        super().__init__(program_memory=program_memory)
        self.transfer_framing_error = True
        self.internal_ram_start = 0x0040
        self.ram = bytearray(192)
        self.instruction_address_trap_low_end = 0x003F
