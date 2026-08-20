"""Independent digital pin-phase model for the Hitachi HD6303R bus.

The active-cycle ordering follows Hitachi #U07 figures 5-1 and 5-2. Reset-entry
timing follows section 2.8 and figure 2-8-1. The model does not represent
nanosecond limits, oscillator behavior, pad behavior, or oscillator recovery.
"""

from __future__ import annotations

from dataclasses import dataclass


MULTIPLEXED_MODES = frozenset({2, 4})
LEGAL_MODES = frozenset({1, 2, 4})


@dataclass(frozen=True)
class HD6303RBusInputs:
    mode: int
    phase: int
    reset_n: bool
    standby: bool
    address: int
    reset_low_cycles: int = 3
    sleeping: bool = False
    waiting: bool = False
    write: bool = False
    data: int = 0
    gpio_port1: int = 0
    gpio_port1_oe: int = 0


@dataclass(frozen=True)
class HD6303RBusPins:
    e: bool
    sc1: bool
    sc1_oe: bool
    sc2: bool
    port1: int
    port1_oe: int
    port3: int
    port3_oe: int
    port4: int
    port4_oe: int


def bus_pins(inputs: HD6303RBusInputs) -> HD6303RBusPins:
    """Return the documented digital pin roles for one active subphase."""

    if inputs.mode not in LEGAL_MODES:
        raise ValueError("HD6303R operating mode must be 1, 2, or 4")
    if inputs.phase not in range(4):
        raise ValueError("HD6303R bus phase must be in the range 0-3")
    if inputs.reset_low_cycles not in range(4):
        raise ValueError("HD6303R reset-low cycle count must be in the range 0-3")

    multiplexed = inputs.mode in MULTIPLEXED_MODES
    stopped = inputs.standby
    reset_bus_released = not inputs.reset_n and inputs.reset_low_cycles == 3
    active = not stopped and not reset_bus_released
    e = inputs.phase >= 2 and not stopped
    sc1 = inputs.phase == 0 if multiplexed else True
    sc1_oe = multiplexed
    address = 0xFFFF if (inputs.sleeping or inputs.waiting) else inputs.address & 0xFFFF
    write = False if (inputs.sleeping or inputs.waiting) else inputs.write
    sc2 = not write
    port1 = inputs.gpio_port1 & 0xFF
    port1_oe = inputs.gpio_port1_oe & 0xFF
    port3 = inputs.data & 0xFF
    port3_oe = 0
    port4 = address >> 8
    port4_oe = 0xFF

    if not active:
        port1_oe = 0
        port3_oe = 0
        port4_oe = 0
        sc1 = True
        sc2 = True
    elif inputs.mode == 1:
        port1 = address & 0xFF
        port1_oe = 0xFF
        if e and write:
            port3_oe = 0xFF
    else:
        if inputs.phase == 0:
            port3 = address & 0xFF
            port3_oe = 0xFF
        elif inputs.phase >= 2 and write:
            port3_oe = 0xFF

    return HD6303RBusPins(
        e=e,
        sc1=sc1,
        sc1_oe=sc1_oe,
        sc2=sc2,
        port1=port1,
        port1_oe=port1_oe,
        port3=port3,
        port3_oe=port3_oe,
        port4=port4,
        port4_oe=port4_oe,
    )


@dataclass
class HD6303RBusSequencer:
    """Four-subphase integration sequencer; standby affects E, not this state."""

    phase: int = 0
    reset_low_cycles: int = 0

    def reset(self) -> None:
        self.phase = 0
        self.reset_low_cycles = 0

    def tick(self, clock_enable: bool = True, reset_n: bool = True) -> int:
        previous_phase = self.phase
        if reset_n:
            self.reset_low_cycles = 0
        if clock_enable:
            self.phase = (self.phase + 1) & 3
            if not reset_n and previous_phase == 3:
                self.reset_low_cycles = min(self.reset_low_cycles + 1, 3)
        return self.phase
