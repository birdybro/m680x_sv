from __future__ import annotations

import unittest

from model.common import Memory
from model.hd63705v0_device import (
    EPROM_DEFINED_STATES,
    HD63705V0CycleInputs,
    HD63705V0DeviceModel,
    HD63705V0EPROMInputs,
    VECTOR_INT,
    VECTOR_SCI_TIMER2,
    VECTOR_TIMER_INT2,
    VECTOR_WAIT_TIMER,
    eprom_cycle,
)


class HD63705V0DeviceModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD63705V0DeviceModel, **values: int | bool):
        return model.cycle(HD63705V0CycleInputs(**values))

    @classmethod
    def write(cls, model: HD63705V0DeviceModel, address: int, data: int, **values):
        return cls.cycle(model, address=address, valid=True, write=True, data=data, **values)

    @classmethod
    def read(cls, model: HD63705V0DeviceModel, address: int, **values):
        return cls.cycle(model, address=address, valid=True, write=False, **values)

    @staticmethod
    def eprom(**values: int | bool):
        inputs: dict[str, int | bool] = {
            "eprom_mode": True,
            "read_voltage": False,
            "program_voltage": False,
            "ce_n": True,
            "oe_n": True,
            "address": 0x123,
            "input_data": 0xC3,
            "stored_data": 0x5A,
        }
        inputs.update(values)
        return eprom_cycle(HD63705V0EPROMInputs(**inputs))

    def test_eprom_table_2_9_states_are_exact(self) -> None:
        states = {
            (True, False, False, False): "read",
            (True, False, False, True): "output_disable",
            (False, True, False, True): "program",
            (False, True, True, False): "verify",
            (False, True, True, True): "program_verify_disable",
        }
        self.assertEqual(set(states.values()), set(EPROM_DEFINED_STATES))
        for (read_voltage, vpp, ce_n, oe_n), expected in states.items():
            cycle = self.eprom(
                read_voltage=read_voltage,
                program_voltage=vpp,
                ce_n=ce_n,
                oe_n=oe_n,
            )
            self.assertEqual(cycle.state, expected)
            self.assertEqual(cycle.storage_read, expected in {"read", "verify"})
            self.assertEqual(cycle.data_oe, expected in {"read", "verify"})
            self.assertEqual(cycle.program_request, expected == "program")
            self.assertEqual(cycle.output_data, 0x5A)
            self.assertEqual(cycle.program_data, 0xC3)

        # CE is explicitly don't-care for VPP verification.
        verify_ce_low = self.eprom(program_voltage=True, ce_n=False, oe_n=False)
        self.assertEqual(verify_ce_low.state, "verify")
        self.assertTrue(verify_ce_low.storage_read)

    def test_eprom_address_map_is_exhaustive(self) -> None:
        for address in range(0x1000):
            cycle = self.eprom(
                read_voltage=True,
                ce_n=False,
                oe_n=False,
                address=address,
            )
            self.assertEqual(cycle.storage_address, 0x1000 | address)
            self.assertTrue(cycle.storage_read)
            self.assertTrue(cycle.mcu_stopped)

    def test_unlisted_eprom_controls_are_safe_and_explicit(self) -> None:
        for values in (
            {"read_voltage": False, "program_voltage": False,
             "ce_n": False, "oe_n": False},
            {"read_voltage": True, "program_voltage": False,
             "ce_n": True, "oe_n": False},
            {"read_voltage": True, "program_voltage": False,
             "ce_n": True, "oe_n": True},
        ):
            cycle = self.eprom(**values)
            self.assertEqual(cycle.state, "undefined_by_documentation")
            self.assertFalse(cycle.storage_read)
            self.assertFalse(cycle.data_oe)
            self.assertFalse(cycle.program_request)

    def test_memory_map_reset_registers_and_gpio(self) -> None:
        program = Memory()
        program[0x1000] = 0xA5
        model = HD63705V0DeviceModel(program_memory=program)

        self.assertEqual(self.read(model, 0x1000).read_data, 0xA5)
        self.assertTrue(self.read(model, 0x1000).program_bus)
        self.assertFalse(self.read(model, 0x2000).program_bus)
        self.assertEqual(self.read(model, 0x2000).read_data, 0xFF)
        self.assertEqual(self.read(model, 0x08).read_data, 0xF0)
        self.assertEqual(self.read(model, 0x09).read_data, 0x50)
        self.assertEqual(self.read(model, 0x0A).read_data, 0x5F)
        self.assertEqual(self.read(model, 0x10).read_data, 0x00)
        self.assertEqual(self.read(model, 0x11).read_data, 0x37)

        self.write(model, 0x00, 0xA5)
        self.write(model, 0x04, 0xF0)
        self.assertEqual(self.read(model, 0x00, port_a=0x3C).read_data, 0xAC)
        self.assertEqual(model.port_outputs()[:2], (0xA5, 0xF0))
        self.write(model, 0x03, 0x7F)
        self.write(model, 0x07, 0x55)
        self.assertEqual(self.read(model, 0x03, port_d=0x2A).read_data, 0xFF)
        self.assertEqual(self.read(model, 0x07).read_data, 0xD5)

        for address, value in ((0x0040, 0x12), (0x00FF, 0x34)):
            self.write(model, address, value)
            self.assertEqual(self.read(model, address).read_data, value)
        model.state.timer_previous = True
        model.state.int_previous = False
        model.state.int2_previous = False
        model.reset()
        self.assertEqual(self.read(model, 0x0040).read_data, 0x12)
        self.assertEqual(self.read(model, 0x00FF).read_data, 0x34)
        self.assertFalse(model.state.timer_previous)
        self.assertTrue(model.state.int_previous)
        self.assertTrue(model.state.int2_previous)

    def test_normal_memory_map_and_ram_retention_are_exhaustive(self) -> None:
        program = Memory()
        for address in range(0x1000, 0x2000):
            program[address] = (address ^ 0xA6) & 0xFF
        model = HD63705V0DeviceModel(program_memory=program)
        counts = {
            "register": 0,
            "ic_test_reserved": 0,
            "ram": 0,
            "eprom": 0,
            "unused": 0,
        }

        for address in range(0x4000):
            region = model.memory_region(address)
            counts[region] += 1
            result = self.read(model, address)
            self.assertEqual(result.program_bus, region == "eprom")
            if region == "eprom":
                self.assertEqual(result.read_data, (address ^ 0xA6) & 0xFF)
            elif region in {"unused", "ic_test_reserved"}:
                # This is a deterministic FPGA normalization, not a claim
                # about the manufacturer-prohibited IC-test range.
                self.assertEqual(result.read_data, 0xFF)

        self.assertEqual(
            counts,
            {
                "register": 19,
                "ic_test_reserved": 13,
                "ram": 192,
                "eprom": 4096,
                "unused": 12064,
            },
        )
        for address in range(0x4000):
            self.assertEqual(
                model.memory_region(address), model.memory_region(address + 0x4000)
            )

        for address in range(0x0040, 0x0100):
            self.write(model, address, (address ^ 0x5A) & 0xFF)
        for address in range(0x0040, 0x0100):
            self.assertEqual(self.read(model, address).read_data, (address ^ 0x5A) & 0xFF)
        model.reset()
        for address in range(0x0040, 0x0100):
            self.assertEqual(self.read(model, address).read_data, (address ^ 0x5A) & 0xFF)

    def test_timer_clock_modes_prescaler_and_rising_external_edge(self) -> None:
        model = HD63705V0DeviceModel()
        self.write(model, 0x08, 0x01)
        self.write(model, 0x09, 0x00)
        result = self.cycle(model)
        self.assertEqual(result.state["TDR"], 0x00)
        self.assertTrue(result.timer_irq)

        self.write(model, 0x09, 0x30)  # external rising events, divide by one
        self.write(model, 0x08, 0x02)
        self.cycle(model, timer=False)
        self.assertEqual(model.state.timer_data, 0x02)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=False)
        result = self.cycle(model, timer=True)
        self.assertEqual(result.state["TDR"], 0x00)
        self.assertTrue(result.timer_irq)

        self.write(model, 0x09, 0x19, timer=True)  # gated E, divide by two, reset PSC
        self.write(model, 0x08, 0x02, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x00)

    def test_interrupt_priority_wait_vector_and_request_clearing(self) -> None:
        model = HD63705V0DeviceModel()
        model.state.timer_request = True
        model.state.timer_mask = False
        result = self.cycle(model, waiting=True)
        self.assertEqual(result.irq_vector, VECTOR_WAIT_TIMER)

        model.state.int2_request = True
        model.state.int2_mask = False
        result = self.cycle(model, waiting=True)
        self.assertEqual(result.irq_vector, VECTOR_TIMER_INT2)

        self.write(model, 0x0A, 0x20, int_n=True, int2_n=True)
        result = self.cycle(model, int_n=False, int2_n=True)
        self.assertTrue(result.int_irq)
        self.assertEqual(result.irq_vector, VECTOR_INT)
        result = self.read(model, VECTOR_INT, int_n=False)
        self.assertTrue(result.int_irq)  # level-and-edge sensing retains low level
        result = self.cycle(model, int_n=True)
        self.assertFalse(result.int_irq)

        model.state.int2_request = False
        model.state.timer_request = False
        model.state.sci_request = True
        model.state.sci_mask = False
        self.assertEqual(self.cycle(model).irq_vector, VECTOR_SCI_TIMER2)

    def test_synchronous_sci_external_transfer_and_pin_overrides(self) -> None:
        model = HD63705V0DeviceModel()
        self.write(model, 0x10, 0xF0, port_d=0x7F)  # Tx/Rx, external clock
        self.write(model, 0x11, 0x30, port_d=0x7F)  # clear requests, keep masks
        self.write(model, 0x12, 0xA5, port_d=0x7F)
        outputs = model.port_outputs()
        self.assertEqual(outputs[7] & 0x38, 0x08)  # Tx output; Rx/CK inputs

        received = 0x3C
        transmitted: list[int] = []
        for bit in range(8):
            low = ((received >> bit) & 1) << 4
            result = self.cycle(model, port_d=low)
            transmitted.append(int(result.state["sci_tx"]))
            high = low | 0x20
            self.cycle(model, port_d=high)
        self.assertEqual(transmitted, [(0xA5 >> bit) & 1 for bit in range(8)])
        self.assertEqual(model.state.sci_data, received)
        self.assertTrue(model.state.sci_request)

        self.write(model, 0x11, 0x30, port_d=0x20)
        self.write(model, 0x10, 0xE0, port_d=0x20)  # internal fastest clock
        for _ in range(4):
            self.cycle(model, port_d=0x20)
            if model.state.timer2_request:
                break
        self.assertTrue(model.state.timer2_request)
        self.assertEqual(model.port_outputs()[7] & 0x20, 0x20)

    def test_stop_follows_figure_2_18_normalization_and_only_external_sources_wake(self) -> None:
        model = HD63705V0DeviceModel()
        model.state.timer_data = 0x12
        model.state.timer_request = True
        model.state.timer_mask = False
        model.state.sci_request = True
        model.state.timer2_request = True
        model.state.sci_mask = False
        model.state.timer2_mask = False
        result = self.cycle(model, stopped=True)
        self.assertEqual(result.state["TDR"], 0xF0)
        self.assertEqual(result.state["TCR"] & 0xC0, 0x40)
        self.assertEqual(result.state["SSR"] & 0xF0, 0x30)
        self.assertFalse(result.irq_request)

        result = self.cycle(model, stopped=True, int_n=False)
        self.assertTrue(result.irq_request)
        self.assertEqual(result.irq_vector, VECTOR_INT)

        model = HD63705V0DeviceModel()
        self.write(model, 0x0A, 0x00, int2_n=True)
        result = self.cycle(model, stopped=True, int2_n=False)
        self.assertTrue(result.int2_irq)
        self.assertTrue(result.irq_request)
        self.assertEqual(result.irq_vector, VECTOR_TIMER_INT2)


if __name__ == "__main__":
    unittest.main()
