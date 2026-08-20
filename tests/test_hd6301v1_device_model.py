from __future__ import annotations

import unittest

from model.common import Memory
from model.hd6301v1_device import HD6301V1DeviceModel, HD6301V1Mode7Model
from model.mc6801_device import MC6801CycleInputs, VECTOR_IRQ1


class HD6301V1Mode7ModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD6301V1Mode7Model, **values: int | bool):
        return model.cycle(MC6801CycleInputs(**values))

    @classmethod
    def write(cls, model: HD6301V1Mode7Model, address: int, data: int, **values):
        return cls.cycle(model, address=address, valid=True, write=True, data=data, **values)

    @classmethod
    def read(cls, model: HD6301V1Mode7Model, address: int, **values):
        return cls.cycle(model, address=address, valid=True, write=False, **values)

    def test_mode7_memory_classification_and_address_error(self) -> None:
        program = Memory()
        program[0xF000] = 0xA5
        program[0xFFFE] = 0xF0
        model = HD6301V1Mode7Model(program_memory=program)

        result = self.read(model, 0xF000, opcode_fetch=True)
        self.assertEqual(result.read_data, 0xA5)
        self.assertTrue(result.program_bus)
        self.assertFalse(result.external_bus)
        self.assertFalse(result.address_error)

        self.write(model, 0x0080, 0x3C)
        result = self.read(model, 0x0080, opcode_fetch=True)
        self.assertEqual(result.read_data, 0x3C)
        self.assertFalse(result.program_bus)
        self.assertFalse(result.address_error)

        self.assertFalse(self.read(model, 0x0100).address_error)
        result = self.read(model, 0x0100, opcode_fetch=True)
        self.assertEqual(result.read_data, 0xFF)
        self.assertTrue(result.address_error)
        self.assertFalse(result.external_bus)
        self.assertTrue(self.read(model, 0x000F, opcode_fetch=True).address_error)
        self.assertFalse(self.read(model, 0x0080, opcode_fetch=True).address_error)
        self.assertFalse(self.read(model, 0xF000, opcode_fetch=True).address_error)

    def test_port3_latch_strobe_and_ordered_flag_clear(self) -> None:
        model = HD6301V1Mode7Model()
        self.write(model, 0x000F, 0x48)
        self.assertEqual(self.read(model, 0x000F).read_data, 0x6F)

        self.cycle(model, port3=0x96, is3_n=False)
        self.cycle(model, port3=0x96, is3_n=False)
        self.assertEqual(model.state.snapshot()["P3CSR"], 0xEF)
        self.assertTrue(model.port3_irq)
        self.assertEqual(model.irq_vector(), VECTOR_IRQ1)

        status = self.read(model, 0x000F)
        self.assertEqual(status.read_data, 0xEF)
        latched = self.read(model, 0x0006, port3=0x55)
        self.assertEqual(latched.read_data, 0x96)
        self.assertFalse(latched.os3_n)
        self.assertFalse(model.port3_irq)
        self.assertEqual(self.read(model, 0x000F).read_data, 0x6F)

        self.write(model, 0x000F, 0x58)
        self.assertTrue(self.read(model, 0x0006, port3=0x22).os3_n)
        self.assertFalse(self.write(model, 0x0006, 0xA5).os3_n)

    def test_port34_gpio_and_reset_values(self) -> None:
        model = HD6301V1Mode7Model()
        self.assertEqual(model.state.snapshot()["P3CSR"], 0x27)
        self.assertEqual(model.port34_outputs(), (0, 0, 0, 0))

        self.write(model, 0x0004, 0xF0)
        self.write(model, 0x0005, 0x0F)
        self.write(model, 0x0006, 0xA5)
        self.write(model, 0x0007, 0x5A)
        self.assertEqual(model.port34_outputs(), (0xA5, 0xF0, 0x5A, 0x0F))
        self.assertEqual(self.read(model, 0x0006, port3=0x3C).read_data, 0x3C)
        self.assertEqual(self.read(model, 0x0007, port4=0xC3).read_data, 0xC3)
        self.assertEqual(self.read(model, 0x0003, port2=0x15).read_data, 0xF5)

    def test_hd6301_framing_error_does_not_transfer_misframed_byte(self) -> None:
        model = HD6301V1Mode7Model()
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

    def test_reserved_rmcr_zero_does_not_enable_motorola_biphase(self) -> None:
        model = HD6301V1Mode7Model()
        self.read(model, 0x0011)
        self.write(model, 0x0013, 0xA5)
        self.write(model, 0x0011, 0x02)
        for _ in range(64):
            self.cycle(model, port2=0x08)
        self.assertEqual(model.state.sci_tx, 1)
        self.assertEqual(model.state.tx_bits, 0)
        self.assertFalse(model.state.tdre)

    def test_hitachi_counter_double_write_and_rollover_flag(self) -> None:
        model = HD6301V1Mode7Model()
        self.write(model, 0x0009, 0xA5)
        self.assertEqual(model.state.timer, 0xFFF8)
        self.write(model, 0x000A, 0x5A)
        self.assertEqual(model.state.timer, 0xA55A)

        model.state.tcsr = 0
        model.state.timer = 0xFFFE
        self.cycle(model)
        self.assertEqual(model.state.timer, 0xFFFF)
        self.assertFalse(model.state.tcsr & 0x20)
        self.cycle(model)
        self.assertEqual(model.state.timer, 0x0000)
        self.assertTrue(model.state.tcsr & 0x20)

    def test_standby_resets_active_state_and_retains_supplied_ram(self) -> None:
        model = HD6301V1Mode7Model()
        self.write(model, 0x0080, 0xA5)
        self.write(model, 0x0014, 0xC0)
        self.write(model, 0x0000, 0xFF)
        self.cycle(model)
        self.assertNotEqual(model.state.timer, 0)

        model.standby_reset(retention_power_ok=True)
        self.assertEqual(model.ram[0], 0xA5)
        self.assertTrue(model.state.standby_power)
        self.assertTrue(model.state.rame)
        self.assertEqual(model.port_outputs()[1], 0)
        self.assertEqual(model.state.timer, 0)

        model.standby_reset(retention_power_ok=False)
        self.assertFalse(model.state.standby_power)


class HD6301V1LegalModeModelTests(unittest.TestCase):
    @staticmethod
    def read(model: HD6301V1DeviceModel, address: int):
        return model.cycle(MC6801CycleInputs(address=address, valid=True))

    def test_all_legal_modes_have_documented_memory_partitions(self) -> None:
        with self.assertRaises(ValueError):
            HD6301V1DeviceModel(3)

        for mode in (0, 1, 2, 4, 5, 6, 7):
            external = Memory()
            program = Memory()
            external[0xF000] = 0x5A
            program[0xF000] = 0xA5
            model = HD6301V1DeviceModel(
                mode, external_memory=external, program_memory=program
            )
            self.assertEqual(model.active_mode, mode)
            self.assertTrue(model.ram_is_internal(0x0080))

            result = self.read(model, 0xF000)
            if mode in {0, 5, 6, 7}:
                self.assertEqual(result.read_data, 0xA5)
                self.assertTrue(result.program_bus)
                self.assertFalse(result.external_bus)
            else:
                self.assertEqual(result.read_data, 0x5A)
                self.assertFalse(result.program_bus)
                self.assertTrue(result.external_bus)

        mode0 = HD6301V1DeviceModel(0)
        self.assertTrue(self.read(mode0, 0xFFFE).external_bus)
        self.assertTrue(self.read(mode0, 0xFFFF).external_bus)
        self.assertTrue(self.read(mode0, 0xFFFE).program_bus)

        mode1 = HD6301V1DeviceModel(1)
        self.assertFalse(mode1.register_is_internal(0x0000))
        self.assertFalse(mode1.register_is_internal(0x0002))

        mode4 = HD6301V1DeviceModel(4)
        self.assertTrue(self.read(mode4, 0x1280).external_bus)
        mode4.cycle(
            MC6801CycleInputs(address=0x0003, valid=True, write=True, data=0x20)
        )
        self.assertEqual(mode4.active_mode, 4)

        mode5 = HD6301V1DeviceModel(5)
        self.assertTrue(self.read(mode5, 0x0100).external_bus)
        self.assertFalse(self.read(mode5, 0x0200).external_bus)

        mode7 = HD6301V1DeviceModel(7)
        self.assertFalse(self.read(mode7, 0x0100).external_bus)


if __name__ == "__main__":
    unittest.main()
