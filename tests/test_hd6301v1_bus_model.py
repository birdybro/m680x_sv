from __future__ import annotations

import unittest

from model.hd6301v1_bus import (
    HD6301V1BusInputs,
    HD6301V1BusSequencer,
    bus_pins,
)


class HD6301V1BusModelTests(unittest.TestCase):
    def pins(self, mode: int, phase: int, **values: int | bool):
        defaults: dict[str, int | bool] = {
            "reset_n": True,
            "standby": False,
            "address": 0xA55A,
            "data": 0xC7,
            "port1": 0x96,
            "port1_oe": 0x3C,
            "port3": 0xC7,
            "port3_oe": 0,
            "port4": 0x69,
            "port4_oe": 0x0F,
        }
        defaults.update(values)
        return bus_pins(HD6301V1BusInputs(mode=mode, phase=phase, **defaults))

    def test_four_subphase_sequence_and_reset_counter(self) -> None:
        sequencer = HD6301V1BusSequencer()
        self.assertEqual([sequencer.tick() for _ in range(4)], [1, 2, 3, 0])
        for expected in range(1, 4):
            for _ in range(4):
                sequencer.tick(reset_n=False)
            self.assertEqual(sequencer.reset_low_cycles, expected)
        for _ in range(4):
            sequencer.tick(reset_n=False)
        self.assertEqual(sequencer.reset_low_cycles, 3)
        sequencer.tick(False, True)
        self.assertEqual(sequencer.reset_low_cycles, 0)
        sequencer.reset()
        self.assertEqual(sequencer.phase, 0)

    def test_mode_roles_and_phase_order(self) -> None:
        for phase in range(4):
            mode1 = self.pins(1, phase, port3_oe=0xFF)
            self.assertEqual((mode1.port1, mode1.port1_oe), (0x5A, 0xFF))
            self.assertEqual((mode1.port4, mode1.port4_oe), (0xA5, 0xFF))
            self.assertEqual(mode1.port3_oe, 0xFF if phase >= 2 else 0)
            self.assertFalse(mode1.sc1_oe)

            mode5 = self.pins(5, phase, address=0x015A, port3_oe=0xFF)
            self.assertEqual((mode5.port4, mode5.port4_oe), (0x5A, 0x0F))
            self.assertEqual(mode5.port3_oe, 0xFF if phase >= 2 else 0)
            self.assertFalse(mode5.sc1)

            mode7 = self.pins(7, phase, os3_active=True)
            self.assertEqual((mode7.port1, mode7.port1_oe), (0x96, 0x3C))
            self.assertEqual((mode7.port4, mode7.port4_oe), (0x69, 0x0F))
            self.assertFalse(mode7.sc1_oe)
            self.assertFalse(mode7.sc2)

            for mode in (0, 2, 4, 6):
                mux = self.pins(mode, phase, port3_oe=0xFF)
                self.assertEqual(mux.sc1, phase == 0)
                self.assertTrue(mux.sc1_oe)
                self.assertEqual(mux.port3_oe, 0xFF if phase != 1 else 0)
                if phase == 0:
                    self.assertEqual(mux.port3, 0x5A)
                self.assertEqual(mux.port4, 0xA5)
                expected_oe = 0x0F if mode == 6 else 0xFF
                self.assertEqual(mux.port4_oe, expected_oe)

    def test_mode7_os3_spans_one_complete_e_cycle(self) -> None:
        sequencer = HD6301V1BusSequencer()
        sequencer.tick(single_chip=True)
        sequencer.tick(single_chip=True, os3_selected=True)
        for expected_phase in (2, 3, 0, 1):
            self.assertEqual(sequencer.phase, expected_phase)
            self.assertTrue(sequencer.os3_active)
            self.assertFalse(
                self.pins(7, expected_phase, os3_active=True).sc2
            )
            if expected_phase != 1:
                sequencer.tick(single_chip=True)
        sequencer.tick(single_chip=True)
        self.assertEqual(sequencer.phase, 2)
        self.assertFalse(sequencer.os3_active)
        self.assertTrue(self.pins(7, 2).sc2)
        sequencer.os3_active = True
        sequencer.tick(clock_enable=False, reset_n=False)
        self.assertEqual(sequencer.phase, 2)
        self.assertFalse(sequencer.os3_active)

    def test_address_projection_and_ios_decode_are_exhaustive(self) -> None:
        for address in range(0x10000):
            mode1 = self.pins(1, 0, address=address)
            self.assertEqual(mode1.port1, address & 0xFF)
            self.assertEqual(mode1.port4, address >> 8)
            mode5 = self.pins(5, 0, address=address)
            self.assertEqual(mode5.port4, address & 0xFF)
            self.assertEqual(mode5.sc1, not (0x0100 <= address <= 0x01FF))
            for mode in (0, 2, 4, 6):
                mux = self.pins(mode, 0, address=address)
                self.assertEqual(mux.port3, address & 0xFF)
                self.assertEqual(mux.port4, address >> 8)

    def test_reset_standby_sleep_and_wait(self) -> None:
        for mode in (0, 1, 2, 4, 5, 6, 7):
            for phase in range(4):
                reset = self.pins(
                    mode, phase, reset_n=False, reset_low_cycles=3,
                    port3_oe=0xFF,
                )
                self.assertEqual(
                    (reset.port1_oe, reset.port3_oe, reset.port4_oe),
                    (0, 0, 0),
                )
                standby = self.pins(mode, phase, standby=True, port3_oe=0xFF)
                self.assertFalse(standby.e)
                self.assertEqual(
                    (standby.port1_oe, standby.port3_oe, standby.port4_oe),
                    (0, 0, 0),
                )

        for mode in (0, 1, 2, 4, 5, 6):
            for low_power in ("sleeping", "waiting"):
                address_pins = self.pins(
                    mode, 0, write=True, **{low_power: True}
                )
                data_pins = self.pins(
                    mode, 2, write=True, port3_oe=0xFF,
                    **{low_power: True},
                )
                self.assertTrue(address_pins.sc2)
                self.assertEqual(data_pins.port3_oe, 0)
                if mode == 1:
                    self.assertEqual(
                        (address_pins.port1, address_pins.port4),
                        (0xFF, 0xFF),
                    )
                elif mode == 5:
                    self.assertEqual(address_pins.port4, 0xFF)
                    self.assertTrue(address_pins.sc1)
                else:
                    self.assertEqual(
                        (address_pins.port3, address_pins.port4),
                        (0xFF, 0xFF),
                    )

    def test_invalid_mode_phase_and_reset_count_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "operating mode"):
            self.pins(3, 0)
        with self.assertRaisesRegex(ValueError, "bus phase"):
            self.pins(2, 4)
        with self.assertRaisesRegex(ValueError, "reset-low cycle count"):
            self.pins(2, 0, reset_low_cycles=4)


if __name__ == "__main__":
    unittest.main()
