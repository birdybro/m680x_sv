"""Independent HD6303R Mode-2 peripheral transaction model.

Hitachi documents the HD6303R as sharing the HD6301V1 peripheral die while
also identifying an SCI framing-error behavior that differs from MC6801.
This profile selects that documented behavior explicitly instead of deriving
it from a generic manufacturer flag.
"""

from __future__ import annotations

from model.common import Memory
from model.mc6801_device import MC6801DeviceModel


class HD6303RMode2Model(MC6801DeviceModel):
    """Specification-derived HD6303R expanded-multiplexed Mode-2 profile."""

    def __init__(self, *, external_memory: Memory | None = None) -> None:
        super().__init__(
            2,
            external_memory=external_memory,
            transfer_framing_error=False,
            sci_biphase_supported=False,
            timer_counter_double_write=True,
            timer_overflow_at_zero=True,
        )
