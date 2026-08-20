"""Independent digital pin-phase model for the Motorola MC6801 bus.

The four subphases summarize the ordering in MC6801RM(AD2) figures 3-23 and
3-28. They intentionally do not represent oscillator, pad, nanosecond setup,
hold, or propagation-delay behavior.
"""

from __future__ import annotations

from dataclasses import dataclass


MULTIPLEXED_MODES = frozenset({0, 1, 2, 3, 6})


@dataclass(frozen=True)
class MC6801BusInputs:
    mode: int
    phase: int
    reset_n: bool
    address: int
    write: bool = False
    normalized_port3: int = 0
    normalized_port3_oe: int = 0
    normalized_port4: int = 0
    normalized_port4_oe: int = 0
    os3_n: bool = True


@dataclass(frozen=True)
class MC6801BusPins:
    e: bool
    sc1: bool
    sc1_oe: bool
    sc2: bool
    port3: int
    port3_oe: int
    port4: int
    port4_oe: int


def bus_pins(inputs: MC6801BusInputs) -> MC6801BusPins:
    """Return digital pin values for one documented bus subphase."""

    if inputs.mode not in range(8):
        raise ValueError("MC6801 operating mode must be in the range 0-7")
    if inputs.phase not in range(4):
        raise ValueError("MC6801 bus phase must be in the range 0-3")

    mode = inputs.mode
    phase = inputs.phase
    multiplexed = mode in MULTIPLEXED_MODES
    nonmultiplexed = mode == 5
    e = phase >= 2

    port3 = inputs.normalized_port3 & 0xFF
    port3_oe = inputs.normalized_port3_oe & 0xFF
    sc1 = True
    sc1_oe = multiplexed or nonmultiplexed
    sc2 = inputs.os3_n if not sc1_oe else not inputs.write

    if not inputs.reset_n:
        port3_oe = 0
        sc1 = True
        sc2 = True
    elif multiplexed:
        sc1 = phase == 0
        if phase == 0:
            port3 = inputs.address & 0xFF
            port3_oe = 0xFF
        elif phase == 1:
            port3_oe = 0
    elif nonmultiplexed:
        sc1 = not (0x0100 <= (inputs.address & 0xFFFF) <= 0x01FF)
        if not e:
            port3_oe = 0

    return MC6801BusPins(
        e=e,
        sc1=sc1,
        sc1_oe=sc1_oe,
        sc2=sc2,
        port3=port3,
        port3_oe=port3_oe,
        port4=inputs.normalized_port4 & 0xFF,
        port4_oe=inputs.normalized_port4_oe & 0xFF,
    )


@dataclass
class MC6801BusSequencer:
    """Minimal integration-clock sequencer independent of CPU state."""

    phase: int = 0

    def reset(self) -> None:
        self.phase = 0

    def tick(self, clock_enable: bool = True) -> int:
        if clock_enable:
            self.phase = (self.phase + 1) & 3
        return self.phase
