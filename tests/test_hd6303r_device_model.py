from __future__ import annotations

import unittest

from model.hd6303r_device import HD6303RMode2Model
from model.mc6801_device import MC6801CycleInputs


class HD6303RMode2ModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD6303RMode2Model, **values: int | bool):
        return model.cycle(MC6801CycleInputs(**values))

    @classmethod
    def write(cls, model: HD6303RMode2Model, address: int, data: int) -> None:
        cls.cycle(model, address=address, valid=True, write=True, data=data)

    def test_framing_error_does_not_transfer_misframed_byte(self) -> None:
        model = HD6303RMode2Model()
        model.state.receive_data = 0x3C
        self.write(model, 0x0010, 0x04)
        self.write(model, 0x0011, 0x08)
        levels = [0, *(0xA5 >> bit & 1 for bit in range(8)), 0]
        for level in levels:
            for _ in range(16):
                self.cycle(model, port2=level << 3)
        self.assertTrue(model.state.orfe)
        self.assertFalse(model.state.rdrf)
        self.assertEqual(model.state.receive_data, 0x3C)

    def test_hitachi_counter_double_write_and_rollover_flag(self) -> None:
        model = HD6303RMode2Model()
        self.write(model, 0x0009, 0x12)
        self.write(model, 0x000A, 0x34)
        self.assertEqual(model.state.timer, 0x1234)

        model.state.tcsr = 0
        model.state.timer = 0xFFFE
        self.cycle(model)
        self.assertFalse(model.state.tcsr & 0x20)
        self.cycle(model)
        self.assertTrue(model.state.tcsr & 0x20)

    def test_standby_retained_domain(self) -> None:
        model = HD6303RMode2Model()
        self.write(model, 0x0080, 0x5A)
        self.write(model, 0x0014, 0xC0)
        self.write(model, 0x0000, 0xFF)
        model.standby_reset(retention_power_ok=True)

        self.assertEqual(model.ram[0], 0x5A)
        self.assertTrue(model.state.standby_power)
        self.assertEqual(model.state.port1_ddr, 0)
        self.assertEqual(model.state.timer, 0)


if __name__ == "__main__":
    unittest.main()
