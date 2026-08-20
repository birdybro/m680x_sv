from __future__ import annotations

import unittest

from model.common import Memory
from model.hd63701v0_device import HD63701V0Mode7Model
from model.mc6801_device import MC6801CycleInputs


class HD63701V0Mode7ModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD63701V0Mode7Model, **values: int | bool):
        return model.cycle(MC6801CycleInputs(**values))

    @classmethod
    def write(cls, model: HD63701V0Mode7Model, address: int, data: int, **values):
        return cls.cycle(model, address=address, valid=True, write=True, data=data, **values)

    @classmethod
    def read(cls, model: HD63701V0Mode7Model, address: int, **values):
        return cls.cycle(model, address=address, valid=True, write=False, **values)

    def test_mode7_eprom_ram_and_address_classification(self) -> None:
        program = Memory()
        program[0xF000] = 0xA5
        model = HD63701V0Mode7Model(program_memory=program)

        result = self.read(model, 0xF000, opcode_fetch=True)
        self.assertEqual(result.read_data, 0xA5)
        self.assertTrue(result.program_bus)
        self.assertFalse(result.address_error)

        for address, value in ((0x0040, 0x3C), (0x00FF, 0xC3)):
            self.write(model, address, value)
            result = self.read(model, address, opcode_fetch=True)
            self.assertEqual(result.read_data, value)
            self.assertFalse(result.program_bus)
            self.assertFalse(result.external_bus)
            self.assertFalse(result.address_error)

        self.assertTrue(self.read(model, 0x003F, opcode_fetch=True).address_error)
        self.assertTrue(self.read(model, 0x0100, opcode_fetch=True).address_error)
        self.assertFalse(self.read(model, 0x0100).address_error)

    def test_rame_disables_physical_ram_without_external_bus(self) -> None:
        model = HD63701V0Mode7Model()
        self.write(model, 0x0040, 0x5A)
        self.write(model, 0x0014, 0x00)
        result = self.read(model, 0x0040)
        self.assertEqual(result.read_data, 0xFF)
        self.assertFalse(result.external_bus)
        self.write(model, 0x0014, 0x40)
        self.assertEqual(self.read(model, 0x0040).read_data, 0x5A)

    def test_framing_error_transfers_receive_shift_register(self) -> None:
        model = HD63701V0Mode7Model()
        model.state.receive_data = 0x3C
        self.write(model, 0x0010, 0x04)
        self.write(model, 0x0011, 0x08)
        levels = [0, *(0xA5 >> bit & 1 for bit in range(8)), 0]
        for level in levels:
            for _ in range(16):
                self.cycle(model, port2=level << 3)
        self.assertTrue(model.state.orfe)
        self.assertFalse(model.state.rdrf)
        self.assertEqual(model.state.receive_data, 0xA5)

    def test_hitachi_timer_and_mode7_gpio(self) -> None:
        model = HD63701V0Mode7Model()
        self.write(model, 0x0004, 0xF0)
        self.write(model, 0x0005, 0x0F)
        self.write(model, 0x0006, 0xA5)
        self.write(model, 0x0007, 0x5A)
        self.assertEqual(model.port34_outputs(), (0xA5, 0xF0, 0x5A, 0x0F))

        self.write(model, 0x0009, 0x12)
        self.write(model, 0x000A, 0x34)
        self.assertEqual(model.state.timer, 0x1234)
        model.state.timer = 0xFFFE
        model.state.tcsr = 0
        self.cycle(model)
        self.assertFalse(model.state.tcsr & 0x20)
        self.cycle(model)
        self.assertTrue(model.state.tcsr & 0x20)

    def test_asynchronous_standby_retained_domain(self) -> None:
        model = HD63701V0Mode7Model()
        self.write(model, 0x0040, 0x96)
        self.write(model, 0x0014, 0xC0)
        self.write(model, 0x0004, 0xFF)
        model.standby_reset(retention_power_ok=True)

        self.assertEqual(model.ram[0], 0x96)
        self.assertTrue(model.state.standby_power)
        self.assertEqual(model.port34_outputs()[1], 0)
        self.assertEqual(model.state.timer, 0)


if __name__ == "__main__":
    unittest.main()
