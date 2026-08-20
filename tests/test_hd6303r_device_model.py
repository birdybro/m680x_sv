from __future__ import annotations

import unittest

from model.hd6303r_device import HD6303RDeviceModel, HD6303RMode2Model
from model.mc6801_device import MC6801CycleInputs


class HD6303RDeviceModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD6303RDeviceModel, **values: int | bool):
        return model.cycle(MC6801CycleInputs(**values))

    @classmethod
    def write(cls, model: HD6303RDeviceModel, address: int, data: int) -> None:
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

    def test_all_documented_operating_modes_are_romless_and_distinct(self) -> None:
        with self.assertRaises(ValueError):
            HD6303RDeviceModel(0)
        with self.assertRaises(ValueError):
            HD6303RDeviceModel(7)

        for mode in (1, 2, 4):
            model = HD6303RDeviceModel(mode)
            self.assertEqual(model.active_mode, mode)
            for address in (0x0004, 0x0005, 0x0006, 0x0007, 0x000F):
                self.assertFalse(model.register_is_internal(address))
            self.assertTrue(model.ram_is_internal(0x0080))
            self.assertFalse(model.program_is_internal(0xF800))
            vector = self.cycle(model, address=0xFFFE, valid=True)
            self.assertTrue(vector.external_bus)
            self.assertFalse(vector.program_bus)

        mode1 = HD6303RDeviceModel(1)
        self.assertFalse(mode1.register_is_internal(0x0000))
        self.assertFalse(mode1.register_is_internal(0x0002))

        for mode in (2, 4):
            model = HD6303RDeviceModel(mode)
            self.assertTrue(model.register_is_internal(0x0000))
            self.assertTrue(model.register_is_internal(0x0002))

        mode4 = HD6303RDeviceModel(4)
        external = self.cycle(
            mode4, address=0x1280, valid=True, write=True, data=0xA5
        )
        self.assertTrue(external.external_bus)
        self.assertEqual(mode4.external_memory[0x1280], 0xA5)
        self.assertEqual(mode4.ram[0], 0x00)
        self.write(mode4, 0x0003, 0x20)
        self.assertEqual(mode4.active_mode, 4)


if __name__ == "__main__":
    unittest.main()
