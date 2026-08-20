from __future__ import annotations

import unittest

from model.mc6800_phase import (
    GAP_12,
    GAP_21,
    PHI1,
    PHI2,
    MC6800PhaseSequencer,
    normalized_cycle_enable,
    phase_levels,
)


class MC6800PhaseModelTests(unittest.TestCase):
    def test_nonoverlapping_phase_projection(self) -> None:
        self.assertEqual(
            [phase_levels(phase) for phase in range(4)],
            [(True, False), (False, False), (False, True), (False, False)],
        )
        for phase in range(4):
            self.assertEqual(phase_levels(phase, False), (False, False))
        with self.assertRaisesRegex(ValueError, "range 0-3"):
            phase_levels(4)

    def test_normalized_core_advances_after_phi2_and_second_gap(self) -> None:
        self.assertEqual(
            [normalized_cycle_enable(phase, True, False) for phase in range(4)],
            [False, False, False, True],
        )
        self.assertFalse(normalized_cycle_enable(GAP_21, False, False))
        self.assertFalse(normalized_cycle_enable(GAP_21, True, True))
        with self.assertRaisesRegex(ValueError, "range 0-3"):
            normalized_cycle_enable(4, True, False)

    def test_controls_sample_only_at_trailing_phi1(self) -> None:
        sequencer = MC6800PhaseSequencer()
        self.assertEqual(sequencer.phase, PHI1)
        self.assertEqual(
            sequencer.tick(irq_n=False, nmi_n=False, halt_n=False), GAP_12
        )
        self.assertEqual(
            (
                sequencer.sampled_irq_n,
                sequencer.sampled_nmi_n,
                sequencer.sampled_halt_n,
            ),
            (False, False, False),
        )
        sequencer.tick(irq_n=True, nmi_n=True, halt_n=True)
        self.assertEqual(sequencer.phase, PHI2)
        sequencer.tick(irq_n=True, nmi_n=True, halt_n=True)
        self.assertEqual(sequencer.phase, GAP_21)
        sequencer.tick(irq_n=True, nmi_n=True, halt_n=True)
        self.assertEqual(sequencer.phase, PHI1)
        self.assertEqual(
            (
                sequencer.sampled_irq_n,
                sequencer.sampled_nmi_n,
                sequencer.sampled_halt_n,
            ),
            (False, False, False),
        )

    def test_clock_enable_and_tsc_hold_phase_and_samples(self) -> None:
        for values in (
            {"clock_enable": False, "tsc": False},
            {"clock_enable": True, "tsc": True},
        ):
            sequencer = MC6800PhaseSequencer()
            sequencer.tick(**values, irq_n=False, nmi_n=False, halt_n=False)
            self.assertEqual(sequencer.phase, PHI1)
            self.assertEqual(
                (
                    sequencer.sampled_irq_n,
                    sequencer.sampled_nmi_n,
                    sequencer.sampled_halt_n,
                ),
                (True, True, True),
            )
        sequencer.reset()
        self.assertEqual(sequencer.phase, PHI1)


if __name__ == "__main__":
    unittest.main()
