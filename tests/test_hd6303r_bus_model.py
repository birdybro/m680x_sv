from __future__ import annotations

import unittest

from model.hd6303r_bus import (
    HD6303RBusInputs,
    HD6303RBusSequencer,
    bus_pins,
)


class HD6303RBusModelTests(unittest.TestCase):
    def pins(self, mode: int, phase: int, **values: int | bool):
        defaults: dict[str, int | bool] = {
            "reset_n": True,
            "standby": False,
            "address": 0xA55A,
            "data": 0xC7,
            "gpio_port1": 0x96,
            "gpio_port1_oe": 0x3C,
        }
        defaults.update(values)
        return bus_pins(HD6303RBusInputs(mode=mode, phase=phase, **defaults))

    def test_four_subphase_sequence_and_enable(self) -> None:
        sequencer = HD6303RBusSequencer()
        self.assertEqual([sequencer.tick() for _ in range(4)], [1, 2, 3, 0])
        self.assertEqual(sequencer.tick(False), 0)
        sequencer.tick()
        sequencer.reset()
        self.assertEqual(sequencer.phase, 0)

    def test_mode1_has_dedicated_address_and_data_pins(self) -> None:
        for phase in range(4):
            read = self.pins(1, phase)
            self.assertEqual((read.port1, read.port1_oe), (0x5A, 0xFF))
            self.assertEqual((read.port4, read.port4_oe), (0xA5, 0xFF))
            self.assertEqual(read.port3_oe, 0)
            self.assertFalse(read.sc1_oe)
            write = self.pins(1, phase, write=True)
            self.assertEqual(write.port3_oe, 0xFF if phase >= 2 else 0)

    def test_modes2_and4_multiplex_address_and_data(self) -> None:
        for mode in (2, 4):
            for phase in range(4):
                read = self.pins(mode, phase)
                self.assertEqual(read.e, phase >= 2)
                self.assertEqual(read.sc1, phase == 0)
                self.assertTrue(read.sc1_oe)
                self.assertEqual(read.port4, 0xA5)
                self.assertEqual(read.port3_oe, 0xFF if phase == 0 else 0)
                write = self.pins(mode, phase, write=True)
                self.assertEqual(
                    write.port3_oe,
                    0xFF if phase == 0 or phase >= 2 else 0,
                )

    def test_address_projection_is_exhaustive(self) -> None:
        for address in range(0x10000):
            mode1 = self.pins(1, 0, address=address)
            self.assertEqual(mode1.port1, address & 0xFF)
            self.assertEqual(mode1.port4, address >> 8)
            for mode in (2, 4):
                mux = self.pins(mode, 0, address=address)
                self.assertEqual(mux.port3, address & 0xFF)
                self.assertEqual(mux.port4, address >> 8)

    def test_reset_and_standby_release_buses(self) -> None:
        for mode in (1, 2, 4):
            for phase in range(4):
                reset = self.pins(mode, phase, reset_n=False, write=True)
                self.assertEqual(
                    (reset.port1_oe, reset.port3_oe, reset.port4_oe),
                    (0, 0, 0),
                )
                self.assertEqual(reset.e, phase >= 2)
                standby = self.pins(mode, phase, standby=True, write=True)
                self.assertEqual(
                    (standby.port1_oe, standby.port3_oe, standby.port4_oe),
                    (0, 0, 0),
                )
                self.assertFalse(standby.e)
                self.assertTrue(standby.sc2)

    def test_sleep_keeps_e_and_presents_idle_ffff_read(self) -> None:
        for mode in (1, 2, 4):
            for phase in range(4):
                pins = self.pins(mode, phase, sleeping=True, write=True)
                self.assertEqual(pins.e, phase >= 2)
                self.assertTrue(pins.sc2)
                self.assertEqual(pins.port4, 0xFF)
                self.assertEqual(pins.port3_oe, 0xFF if mode != 1 and phase == 0 else 0)
                if mode == 1:
                    self.assertEqual(pins.port1, 0xFF)
                elif phase == 0:
                    self.assertEqual(pins.port3, 0xFF)

    def test_invalid_mode_and_phase_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "operating mode"):
            self.pins(5, 0)
        with self.assertRaisesRegex(ValueError, "bus phase"):
            self.pins(2, 4)


if __name__ == "__main__":
    unittest.main()
