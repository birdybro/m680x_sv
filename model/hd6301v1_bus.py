"""Independent digital pin-phase model for the Hitachi HD6301V1 bus.

The active-cycle and mode roles follow Hitachi #U07 sections 2.1 and 2.10 and
figures 5-1/5-2. Reset and low-power behavior follows sections 2.8 and 2.12.
Nanosecond limits, oscillator behavior, and pad behavior are not represented.
"""

from __future__ import annotations

from dataclasses import dataclass


LEGAL_MODES = frozenset({0, 1, 2, 4, 5, 6, 7})
MULTIPLEXED_MODES = frozenset({0, 2, 4, 6})
FULL_UPPER_ADDRESS_MODES = frozenset({0, 1, 2, 4})


@dataclass(frozen=True)
class HD6301V1BusInputs:
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
    port1: int = 0
    port1_oe: int = 0
    port3: int = 0
    port3_oe: int = 0
    port4: int = 0
    port4_oe: int = 0
    os3_n: bool = True


@dataclass(frozen=True)
class HD6301V1BusPins:
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


def bus_pins(inputs: HD6301V1BusInputs) -> HD6301V1BusPins:
    if inputs.mode not in LEGAL_MODES:
        raise ValueError("HD6301V1 operating mode must be 0, 1, 2, 4, 5, 6, or 7")
    if inputs.phase not in range(4):
        raise ValueError("HD6301V1 bus phase must be in the range 0-3")
    if inputs.reset_low_cycles not in range(4):
        raise ValueError("HD6301V1 reset-low cycle count must be in the range 0-3")

    multiplexed = inputs.mode in MULTIPLEXED_MODES
    mode1 = inputs.mode == 1
    mode5 = inputs.mode == 5
    single_chip = inputs.mode == 7
    idle = (inputs.sleeping or inputs.waiting) and not single_chip
    address = 0xFFFF if idle else inputs.address & 0xFFFF
    write = inputs.write and not (inputs.sleeping or inputs.waiting)
    released = inputs.standby or (
        not inputs.reset_n and inputs.reset_low_cycles == 3
    )

    e = inputs.phase >= 2 and not inputs.standby
    sc1 = inputs.phase == 0 if multiplexed else True
    if mode5:
        sc1 = (address >> 8) != 0x01
    sc1_oe = multiplexed or mode5
    sc2 = (inputs.phase < 2 or inputs.os3_n) if single_chip else not write
    port1 = inputs.port1 & 0xFF
    port1_oe = inputs.port1_oe & 0xFF
    port3 = inputs.port3 & 0xFF
    port3_oe = inputs.port3_oe & 0xFF
    port4 = inputs.port4 & 0xFF
    port4_oe = inputs.port4_oe & 0xFF

    if released:
        port1_oe = 0
        port3_oe = 0
        port4_oe = 0
        sc1 = True
        sc2 = True
    elif single_chip:
        sc1_oe = False
    elif mode1:
        port1 = address & 0xFF
        port1_oe = 0xFF
        port4 = address >> 8
        port4_oe = 0xFF
        port3_oe = (
            inputs.port3_oe & 0xFF
            if inputs.phase >= 2 and not (inputs.sleeping or inputs.waiting)
            else 0
        )
        sc1_oe = False
    elif mode5:
        port4 = address & 0xFF
        port3_oe = (
            inputs.port3_oe & 0xFF
            if inputs.phase >= 2 and not (inputs.sleeping or inputs.waiting)
            else 0
        )
    elif multiplexed:
        port4 = address >> 8
        if inputs.mode in FULL_UPPER_ADDRESS_MODES:
            port4_oe = 0xFF
        if inputs.phase == 0:
            port3 = address & 0xFF
            port3_oe = 0xFF
        elif inputs.phase == 1:
            port3_oe = 0
        elif inputs.sleeping or inputs.waiting:
            port3_oe = 0

    return HD6301V1BusPins(
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
class HD6301V1BusSequencer:
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
