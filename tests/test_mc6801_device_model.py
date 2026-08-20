from __future__ import annotations

import unittest

from model.common import Memory
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

    def test_all_mc6801_modes_and_rom_options_are_validated(self) -> None:
        self.assertEqual([MC6801DeviceModel(mode).active_mode for mode in range(8)], list(range(8)))
        for mode in (-1, 8):
            with self.assertRaisesRegex(ValueError, "range 0-7"):
                MC6801DeviceModel(mode)
        for start in (0xC800, 0xD800, 0xE800, 0xF800):
            self.assertEqual(MC6801DeviceModel(1, rom_start=start).rom_start, start)
        with self.assertRaisesRegex(ValueError, "ROM start"):
            MC6801DeviceModel(1, rom_start=0xD000)

    def test_mode_register_exclusions_and_program_windows(self) -> None:
        for mode in range(4):
            model = MC6801DeviceModel(mode)
            for address in (0x0004, 0x0005, 0x0006, 0x0007, 0x000F):
                self.assertFalse(model.register_is_internal(address))

        for mode in (4, 7):
            model = MC6801DeviceModel(mode)
            for address in (0x0004, 0x0005, 0x0006, 0x0007, 0x000F):
                self.assertTrue(model.register_is_internal(address))

        for mode in (5, 6):
            model = MC6801DeviceModel(mode)
            self.assertFalse(model.register_is_internal(0x0004))
            self.assertTrue(model.register_is_internal(0x0005))
            self.assertFalse(model.register_is_internal(0x0006))
            self.assertTrue(model.register_is_internal(0x0007))
            self.assertFalse(model.register_is_internal(0x000F))

        mode1 = MC6801DeviceModel(1)
        self.assertTrue(mode1.program_is_internal(0xF800))
        self.assertTrue(mode1.program_is_internal(0xFFEF))
        self.assertFalse(mode1.program_is_internal(0xFFF0))
        mode1r = MC6801DeviceModel(1, rom_start=0xD800)
        self.assertTrue(mode1r.program_is_internal(0xD800))
        self.assertFalse(mode1r.program_is_internal(0xF800))
        mode0 = MC6801DeviceModel(0, rom_start=0xC800)
        self.assertFalse(mode0.program_is_internal(0xC800))
        self.assertTrue(mode0.program_is_internal(0xF800))
        mode6r = MC6801DeviceModel(6, rom_start=0xE800)
        self.assertTrue(mode6r.program_is_internal(0xE800))
        self.assertFalse(mode6r.program_is_internal(0xFFFE))

    def test_mode0_reset_vector_is_external_for_two_reads_only(self) -> None:
        external = Memory()
        program = Memory()
        external[0xFFFE] = 0x12
        external[0xFFFF] = 0x34
        program[0xFFFE] = 0xAB
        model = MC6801DeviceModel(0, external_memory=external, program_memory=program)

        first = self.read(model, 0xFFFE)
        second = self.read(model, 0xFFFF)
        later = self.read(model, 0xFFFE)
        self.assertEqual((first.read_data, second.read_data), (0x12, 0x34))
        self.assertTrue(first.external_bus)
        self.assertTrue(second.external_bus)
        self.assertEqual(later.read_data, 0xAB)
        self.assertTrue(later.program_bus)
        self.assertFalse(later.external_bus)

    def test_mode4_mirrors_ram_and_switches_irreversibly_to_mode5(self) -> None:
        model = MC6801DeviceModel(4)
        self.write(model, 0x1280, 0xA5)
        self.assertEqual(self.read(model, 0x0080).read_data, 0xA5)
        self.assertEqual(self.read(model, 0xFF80).read_data, 0xA5)
        self.write(model, 0xFFFE, 0x56)
        self.assertEqual(self.read(model, 0x00FE).read_data, 0x56)
        self.assertFalse(self.read(model, 0x0200).external_bus)

        self.write(model, 0x0003, 0x20)
        self.assertEqual(model.active_mode, 5)
        self.assertEqual(self.read(model, 0x0003).read_data >> 5, 5)
        self.write(model, 0x0003, 0x00)
        self.assertEqual(model.active_mode, 5)
        self.assertFalse(model.ram_is_internal(0x1280))
        self.assertTrue(model.ram_is_internal(0x0080))

    def test_mode5_partial_bus_and_single_chip_unusable_space(self) -> None:
        external = Memory()
        program = Memory()
        external[0x0100] = 0x51
        external[0x0200] = 0x52
        program[0xF800] = 0x53
        mode5 = MC6801DeviceModel(5, external_memory=external, program_memory=program)
        selected = self.read(mode5, 0x0100)
        unselected = self.read(mode5, 0x0200)
        rom = self.read(mode5, 0xF800)
        self.assertEqual((selected.read_data, unselected.read_data, rom.read_data), (0x51, 0x52, 0x53))
        self.assertTrue(selected.external_bus)
        self.assertFalse(unselected.external_bus)
        self.assertTrue(rom.program_bus)

        mode7 = MC6801DeviceModel(7, external_memory=external, program_memory=program)
        self.assertEqual(self.read(mode7, 0x0200).read_data, 0xFF)
        self.assertFalse(self.read(mode7, 0x0200).external_bus)

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
        self.write(model, 0x000A, 0x5A)
        self.assertEqual(model.state.timer, 0xFFF9)

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

    def test_external_nrz_clock_divides_p22_edges_by_eight(self) -> None:
        model = MC6801DeviceModel(2)
        self.write(model, 0x0001, 0x04)
        self.write(model, 0x0010, 0x0C)
        self.assertEqual(model.port_outputs()[3] & 0x04, 0)
        self.read(model, 0x0011)
        self.write(model, 0x0013, 0xA6)
        self.write(model, 0x0011, 0x0A)

        for _ in range(32):
            self.idle(model, port2=0x0C)
        self.assertFalse(model.state.tdre)
        self.assertEqual(model.state.tx_marks, 9)
        self.assertEqual(model.state.sci_external_subcycles, 0)

        def external_bit(level: int) -> None:
            for _ in range(8):
                self.idle(model, port2=level << 3)
                self.idle(model, port2=(level << 3) | 0x04)

        for _ in range(9):
            external_bit(1)
        transmitted = []
        for level in [0, *(0xC3 >> bit & 1 for bit in range(8)), 1]:
            external_bit(level)
            transmitted.append(model.state.sci_tx)

        self.assertEqual(transmitted, [0, *(0xA6 >> bit & 1 for bit in range(8)), 1])
        self.assertTrue(model.state.tdre)
        self.assertTrue(model.state.rdrf)
        self.assertFalse(model.state.orfe)
        self.assertEqual(model.state.receive_data, 0xC3)

    def test_biphase_transition_coding_and_interval_receive(self) -> None:
        transmitter = MC6801DeviceModel(2)
        self.read(transmitter, 0x0011)
        self.write(transmitter, 0x0013, 0x4D)
        self.write(transmitter, 0x0011, 0x02)
        for _ in range(16 * 11):
            self.idle(transmitter, port2=0x08)
            if transmitter.state.tx_bits == 10:
                break
        self.assertEqual(transmitter.state.tx_bits, 10)

        bits = [0, *(0x4D >> bit & 1 for bit in range(8)), 1]
        for bit in bits:
            boundary_level = transmitter.state.sci_tx
            for _ in range(8):
                self.idle(transmitter, port2=0x08)
            self.assertEqual(transmitter.state.sci_tx, boundary_level ^ bit)
            for _ in range(8):
                self.idle(transmitter, port2=0x08)
            self.assertEqual(transmitter.state.sci_tx, boundary_level ^ bit ^ 1)

        receiver = MC6801DeviceModel(2)
        self.write(receiver, 0x0011, 0x08, port2=0x08)
        receive_level = 1

        def send_biphase_bit(bit: int) -> None:
            nonlocal receive_level
            receive_level ^= 1
            for _ in range(8):
                self.idle(receiver, port2=receive_level << 3)
            if bit:
                receive_level ^= 1
            for _ in range(8):
                self.idle(receiver, port2=receive_level << 3)

        send_biphase_bit(1)
        send_biphase_bit(1)
        for bit in [0, *(0xA7 >> bit & 1 for bit in range(8)), 1]:
            send_biphase_bit(bit)
        self.assertTrue(receiver.state.rdrf)
        self.assertFalse(receiver.state.orfe)
        self.assertEqual(receiver.state.receive_data, 0xA7)

        self.read(receiver, 0x0011, port2=receive_level << 3)
        self.read(receiver, 0x0012, port2=receive_level << 3)
        send_biphase_bit(1)
        send_biphase_bit(1)
        for bit in [0, *(0x5A >> bit & 1 for bit in range(8)), 0]:
            send_biphase_bit(bit)
        send_biphase_bit(1)
        self.assertFalse(receiver.state.rdrf)
        self.assertTrue(receiver.state.orfe)
        self.assertEqual(receiver.state.receive_data, 0x5A)

        wake_receiver = MC6801DeviceModel(2)
        self.write(wake_receiver, 0x0011, 0x09, port2=0x08)
        receive_level = 1

        def send_wake_mark() -> None:
            nonlocal receive_level
            receive_level ^= 1
            for _ in range(8):
                self.idle(wake_receiver, port2=receive_level << 3)
            receive_level ^= 1
            for _ in range(8):
                self.idle(wake_receiver, port2=receive_level << 3)

        for _ in range(11):
            send_wake_mark()
        self.assertEqual(wake_receiver.state.trcsr_control & 0x01, 0)

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
