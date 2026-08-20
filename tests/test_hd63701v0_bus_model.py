from __future__ import annotations

import unittest

from model.hd63701v0_bus import (
    HD63701V0BusInputs,
    HD63701V0BusSequencer,
    bus_pins,
)


class HD63701V0BusModelTests(unittest.TestCase):
    def pins(self, mode: int, phase: int, **values: int | bool):
        defaults: dict[str, int | bool] = {
            "phase_reset_n": True,
            "reset_active": False,
            "standby": False,
            "address": 0xA55A,
            "port1": 0x96,
            "port1_oe": 0x3C,
            "port2": 0x15,
            "port2_oe": 0x1B,
            "port3": 0xC7,
            "port3_oe": 0,
            "port4": 0x69,
            "port4_oe": 0x0F,
        }
        defaults.update(values)
        return bus_pins(HD63701V0BusInputs(mode=mode, phase=phase, **defaults))

    def test_four_subphase_and_synchronous_reset_recovery(self) -> None:
        sequencer = HD63701V0BusSequencer()
        self.assertEqual([sequencer.tick() for _ in range(4)], [1, 2, 3, 0])
        self.assertFalse(sequencer.reset_active)
        sequencer.tick(reset_n=False)
        self.assertTrue(sequencer.reset_active)
        self.assertEqual(sequencer.phase, 1)
        for _ in range(3):
            sequencer.tick(reset_n=True)
        self.assertFalse(sequencer.reset_active)
        sequencer.tick(standby_n=False)
        self.assertEqual(sequencer.phase, 0)
        self.assertTrue(sequencer.reset_active)
        sequencer.tick(phase_reset_n=False)
        self.assertEqual(sequencer.phase, 0)

    def test_active_mode_roles_and_phase_order(self) -> None:
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

            for mode in (0, 2, 6):
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
        sequencer = HD63701V0BusSequencer()
        for _ in range(4):
            sequencer.tick()
        self.assertFalse(sequencer.reset_active)
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
            for mode in (0, 2, 6):
                mux = self.pins(mode, 0, address=address)
                self.assertEqual(mux.port3, address & 0xFF)
                self.assertEqual(mux.port4, address >> 8)

    def test_reset_pin_table_and_integration_reset_are_distinct(self) -> None:
        for mode in (0, 1, 2, 5, 6, 7):
            for phase in range(4):
                reset = self.pins(mode, phase, reset_active=True, port3_oe=0xFF)
                self.assertEqual(
                    (reset.port1_oe, reset.port2_oe,
                     reset.port3_oe, reset.port4_oe),
                    (0, 0, 0, 0),
                )
                self.assertTrue(reset.sc2)
                if mode == 7:
                    self.assertFalse(reset.sc1_oe)
                elif mode == 5:
                    self.assertTrue(reset.sc1_oe)
                else:
                    self.assertEqual(reset.sc1_oe, phase < 2)

                integration_reset = self.pins(
                    mode, phase, phase_reset_n=False, port3_oe=0xFF
                )
                self.assertFalse(integration_reset.e)
                self.assertFalse(integration_reset.sc1_oe)
                self.assertEqual(integration_reset.port2_oe, 0)

    def test_standby_sleep_and_wait_pin_states(self) -> None:
        for mode in (0, 1, 2, 5, 6, 7):
            for phase in range(4):
                standby = self.pins(mode, phase, standby=True, port3_oe=0xFF)
                self.assertFalse(standby.e)
                self.assertEqual(
                    (standby.port1_oe, standby.port2_oe,
                     standby.port3_oe, standby.port4_oe),
                    (0, 0, 0, 0),
                )

        for mode in (0, 1, 2, 5, 6):
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

    def test_invalid_mode_and_phase_are_rejected(self) -> None:
        for invalid_mode in (3, 4):
            with self.assertRaisesRegex(ValueError, "operating mode"):
                self.pins(invalid_mode, 0)
        with self.assertRaisesRegex(ValueError, "bus phase"):
            self.pins(2, 4)


if __name__ == "__main__":
    unittest.main()
