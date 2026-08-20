"""Independent digital phase model for the MC6800 FPGA integration wrapper.

The real MC6800 receives non-overlapping phi1 and phi2 clock inputs. This model
describes the repository's four-subphase digital projection and the trailing-
phi1 processor-control sampling boundary; it does not model electrical timing.
"""

from __future__ import annotations

from dataclasses import dataclass


PHI1 = 0
GAP_12 = 1
PHI2 = 2
GAP_21 = 3


def phase_levels(phase: int, phase_reset_n: bool = True) -> tuple[bool, bool]:
    if phase not in range(4):
        raise ValueError("MC6800 bus phase must be in the range 0-3")
    return (
        phase_reset_n and phase == PHI1,
        phase_reset_n and phase == PHI2,
    )


def normalized_cycle_enable(phase: int, clock_enable: bool, tsc: bool) -> bool:
    if phase not in range(4):
        raise ValueError("MC6800 bus phase must be in the range 0-3")
    return clock_enable and not tsc and phase == GAP_21


@dataclass
class MC6800PhaseSequencer:
    phase: int = PHI1
    sampled_irq_n: bool = True
    sampled_nmi_n: bool = True
    sampled_halt_n: bool = True

    def reset(self) -> None:
        self.phase = PHI1
        self.sampled_irq_n = True
        self.sampled_nmi_n = True
        self.sampled_halt_n = True

    def tick(
        self,
        *,
        clock_enable: bool = True,
        tsc: bool = False,
        irq_n: bool = True,
        nmi_n: bool = True,
        halt_n: bool = True,
    ) -> int:
        if clock_enable and not tsc:
            if self.phase == PHI1:
                self.sampled_irq_n = irq_n
                self.sampled_nmi_n = nmi_n
                self.sampled_halt_n = halt_n
            self.phase = (self.phase + 1) & 3
        return self.phase
