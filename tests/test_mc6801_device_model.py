from __future__ import annotations

import unittest

from model.mc6801_device import (
    MC6801CycleInputs,
    MC6801DeviceModel,
    VECTOR_INPUT_CAPTURE,
    VECTOR_IRQ1,
    VECTOR_SCI,
)


class MC6801DeviceModelTests(unittest.TestCase):
    @staticmethod
    def write(
        model: MC6801DeviceModel,
        address: int,
        data: int,
        **inputs: int | bool,
    ):
        return model.cycle(
            MC6801CycleInputs(address=address, valid=True, write=True, data=data, **inputs)
        )

    @staticmethod
    def read(model: MC6801DeviceModel, address: int, **inputs: int | bool):
        return model.cycle(
            MC6801CycleInputs(address=address, valid=True, write=False, **inputs)
        )

    @staticmethod
    def idle(model: MC6801DeviceModel, **inputs: int | bool):
        return model.cycle(MC6801CycleInputs(**inputs))

    def test_only_documented_mc6803_operating_modes_are_accepted(self) -> None:
        self.assertEqual(MC6801DeviceModel(2).operating_mode, 2)
        self.assertEqual(MC6801DeviceModel(3).operating_mode, 3)
        for mode in (0, 1, 4, 5, 6, 7):
            with self.assertRaisesRegex(ValueError, "only Modes 2 and 3"):
                MC6801DeviceModel(mode)

    def test_mode_dependent_ram_and_register_decode(self) -> None:
        mode2 = MC6801DeviceModel(2)
        write_result = self.write(mode2, 0x0080, 0xA5)
        self.assertFalse(write_result.external_bus)
        self.assertEqual(self.read(mode2, 0x0080).read_data, 0xA5)
        self.assertEqual(mode2.external_memory[0x0080], 0)
        self.assertTrue(self.write(mode2, 0x0004, 0x77).external_bus)
        self.assertEqual(mode2.external_memory[0x0004], 0x77)

        mode3 = MC6801DeviceModel(3)
        write_result = self.write(mode3, 0x0080, 0x5A)
        self.assertTrue(write_result.external_bus)
        self.assertEqual(mode3.external_memory[0x0080], 0x5A)
        self.assertEqual(self.read(mode3, 0x0003, port2=0x15).read_data, 0x75)

    def test_gpio_pin_reads_and_sci_direction_overrides(self) -> None:
        model = MC6801DeviceModel()
        self.write(model, 0x0002, 0xA5)
        self.write(model, 0x0000, 0xF0)
        self.assertEqual(self.read(model, 0x0002, port1=0x3C).read_data, 0x3C)
        self.assertEqual(self.read(model, 0x0000).read_data, 0xFF)
        self.assertEqual(model.port_outputs()[:2], (0xA5, 0xF0))

        self.write(model, 0x0010, 0x0C)  # output-clock SCI mode, P22 input
        self.write(model, 0x0011, 0x0A)  # receiver and transmitter enabled
        self.write(model, 0x0001, 0x1F)
        self.write(model, 0x0003, 0x1F)
        _, _, _port2_value, port2_oe = model.port_outputs()
        self.assertEqual(port2_oe & 0x1C, 0x10)
        self.assertEqual(model.state.port2_ddr & 0x1C, 0x10)

    def test_timer_flags_coherent_read_and_ordered_clear(self) -> None:
        model = MC6801DeviceModel()
        model.state.timer = 0x1233
        model.state.output_compare = 0x1234
        model.state.tcsr = 0x01
        result = self.idle(model)
        self.assertEqual(result.state["timer"], 0x1234)
        self.assertEqual(result.state["TCSR"] & 0x40, 0x40)
        self.assertTrue(model.state.output_level)

        model.state.timer = 0xAB12
        self.assertEqual(self.read(model, 0x0009).read_data, 0xAB)
        self.assertEqual(self.read(model, 0x000A).read_data, 0x12)
        self.write(model, 0x0009, 0x00)
        self.assertEqual(model.state.timer, 0xFFF8)

        model.state.tcsr |= 0xE0
        self.read(model, 0x0008)
        self.read(model, 0x000D)
        self.write(model, 0x000C, 0x55)
        self.read(model, 0x0009)
        self.assertEqual(model.state.tcsr & 0xE0, 0)

        model.state.timer = 0xFFFE
        self.idle(model)
        self.assertEqual(model.state.timer, 0xFFFF)
        self.assertEqual(model.state.tcsr & 0x20, 0x20)

    def test_synchronized_capture_uses_second_following_cycle(self) -> None:
        model = MC6801DeviceModel()
        self.idle(model, port2=0x01)
        self.idle(model, port2=0x01)
        before_edge = model.state.timer
        self.idle(model, port2=0x00)
        self.assertEqual(model.state.tcsr & 0x80, 0)
        self.idle(model, port2=0x00)
        self.assertEqual(model.state.tcsr & 0x80, 0x80)
        self.assertEqual(model.state.input_capture, (before_edge + 2) & 0xFFFF)

    def test_irq_request_latches_and_late_priority_vector(self) -> None:
        model = MC6801DeviceModel()
        model.state.tcsr = 0x90
        result = self.idle(model, interrupt_mask=False)
        self.assertTrue(result.state["irq2_pending"])
        self.assertEqual(result.irq_vector, VECTOR_INPUT_CAPTURE)

        result = self.write(model, 0x0008, 0x00, interrupt_mask=False)
        self.assertTrue(result.irq_request)
        self.assertEqual(result.irq_vector, VECTOR_SCI)

        result = self.idle(model, irq1_n=False, interrupt_mask=False)
        self.assertTrue(result.state["irq1_pending"])
        self.assertEqual(result.irq_vector, VECTOR_IRQ1)
        result = self.idle(model, interrupt_mask=True)
        self.assertFalse(result.state["irq1_pending"])
        self.assertFalse(result.state["irq2_pending"])

    def test_nrz_transmit_receive_and_overrun_retention(self) -> None:
        model = MC6801DeviceModel()
        self.write(model, 0x0010, 0x04)
        self.read(model, 0x0011)
        self.write(model, 0x0013, 0xA5)
        self.write(model, 0x0011, 0x0A)
        for _ in range(16 * 11):
            self.idle(model, port2=0x08)
            if model.state.tx_bits == 10:
                break
        self.assertEqual(model.state.tx_bits, 10)
        self.assertEqual(model.state.tx_frame, 0x34A)
        self.assertEqual(model.state.sci_tx, 0)
        self.assertTrue(model.state.tdre)

        def send_byte(value: int) -> None:
            levels = [0, *(value >> bit & 1 for bit in range(8)), 1]
            for level in levels:
                for _ in range(16):
                    self.idle(model, port2=level << 3)

        send_byte(0x3C)
        self.assertTrue(model.state.rdrf)
        self.assertEqual(model.state.receive_data, 0x3C)
        send_byte(0xA7)
        self.assertTrue(model.state.orfe)
        self.assertEqual(model.state.receive_data, 0x3C)
        self.read(model, 0x0011)
        self.read(model, 0x0012)
        self.assertFalse(model.state.rdrf)
        self.assertFalse(model.state.orfe)

    def test_mc6801_framing_error_transfers_misframed_byte(self) -> None:
        model = MC6801DeviceModel()
        self.write(model, 0x0010, 0x04)
        self.write(model, 0x0011, 0x08)
        levels = [0, *(0xA5 >> bit & 1 for bit in range(8)), 0]
        for level in levels:
            for _ in range(16):
                self.idle(model, port2=level << 3)
        self.assertTrue(model.state.orfe)
        self.assertFalse(model.state.rdrf)
        self.assertEqual(model.state.receive_data, 0xA5)


if __name__ == "__main__":
    unittest.main()
