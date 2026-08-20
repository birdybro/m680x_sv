from __future__ import annotations

import unittest

from model.mc6801_bus import MC6801BusInputs, MC6801BusSequencer, bus_pins


class MC6801BusModelTests(unittest.TestCase):
    def pins(self, mode: int, phase: int, **values: int | bool):
        defaults: dict[str, int | bool] = {
            "reset_n": True,
            "address": 0xA55A,
            "normalized_port3": 0xC7,
            "normalized_port3_oe": 0,
            "normalized_port4": 0xA5,
            "normalized_port4_oe": 0xFF,
        }
        defaults.update(values)
        return bus_pins(MC6801BusInputs(mode=mode, phase=phase, **defaults))

    def test_four_subphase_sequence_and_enable(self) -> None:
        sequencer = MC6801BusSequencer()
        self.assertEqual([sequencer.tick() for _ in range(4)], [1, 2, 3, 0])
        self.assertEqual(sequencer.tick(False), 0)
        sequencer.tick()
        sequencer.reset()
        self.assertEqual(sequencer.phase, 0)

    def test_every_mode_has_documented_sc1_role_and_e_levels(self) -> None:
        for mode in range(8):
            for phase in range(4):
                pins = self.pins(mode, phase)
                self.assertEqual(pins.e, phase >= 2)
                self.assertEqual(pins.sc1_oe, mode not in {4, 7})
                if mode in {0, 1, 2, 3, 6}:
                    self.assertEqual(pins.sc1, phase == 0)

    def test_multiplexed_address_turnaround_and_data(self) -> None:
        for mode in (0, 1, 2, 3, 6):
            address = self.pins(mode, 0)
            self.assertEqual((address.port3, address.port3_oe), (0x5A, 0xFF))
            self.assertEqual(self.pins(mode, 1).port3_oe, 0)
            self.assertEqual(self.pins(mode, 2).port3_oe, 0)
            write = self.pins(mode, 2, write=True, normalized_port3_oe=0xFF)
            self.assertEqual((write.port3, write.port3_oe, write.sc2), (0xC7, 0xFF, False))

    def test_mode5_ios_is_exhaustive_over_address_space(self) -> None:
        for address in range(0x10000):
            pins = self.pins(5, 0, address=address)
            self.assertEqual(not pins.sc1, 0x0100 <= address <= 0x01FF)
            self.assertEqual(pins.port3_oe, 0)
        self.assertEqual(
            self.pins(5, 2, address=0x0100, write=True,
                      normalized_port3_oe=0xFF).port3_oe,
            0xFF,
        )

    def test_single_chip_os3_is_qualified_by_e(self) -> None:
        for mode in (4, 7):
            self.assertTrue(self.pins(mode, 0, os3_n=False).sc2)
            self.assertTrue(self.pins(mode, 1, os3_n=False).sc2)
            self.assertFalse(self.pins(mode, 2, os3_n=False).sc2)
            self.assertFalse(self.pins(mode, 3, os3_n=False).sc2)

    def test_reset_releases_data_and_holds_controls_high(self) -> None:
        for mode in range(8):
            for phase in range(4):
                pins = self.pins(mode, phase, reset_n=False, write=True,
                                 normalized_port3_oe=0xFF, os3_n=False)
                self.assertEqual(pins.port3_oe, 0)
                self.assertTrue(pins.sc1)
                self.assertTrue(pins.sc2)

    def test_wai_repeats_post_stack_sp_read(self) -> None:
        for phase in range(4):
            mode2 = self.pins(
                2,
                phase,
                waiting=True,
                stack_pointer=0x1FF8,
                write=True,
                normalized_port3_oe=0xFF,
            )
            self.assertTrue(mode2.sc2)
            self.assertEqual(mode2.port4, 0x1F)
            self.assertEqual(mode2.port3_oe, 0xFF if phase == 0 else 0)
            if phase == 0:
                self.assertEqual(mode2.port3, 0xF8)

            mode5 = self.pins(
                5,
                phase,
                waiting=True,
                stack_pointer=0x0180,
                write=True,
                normalized_port3_oe=0xFF,
            )
            self.assertTrue(mode5.sc2)
            self.assertFalse(mode5.sc1)
            self.assertEqual(mode5.port4, 0x80)
            self.assertEqual(mode5.port3_oe, 0)

    def test_invalid_mode_and_phase_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "operating mode"):
            self.pins(8, 0)
        with self.assertRaisesRegex(ValueError, "bus phase"):
            self.pins(2, 4)


if __name__ == "__main__":
    unittest.main()
