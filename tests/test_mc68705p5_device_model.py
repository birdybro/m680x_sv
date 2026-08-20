from __future__ import annotations

import unittest

from model.common import Memory
from model.mc68705p5_device import (
    EPROM_CONTROL_DEFINED_STATES,
    MC68705P5CycleInputs,
    MC68705P5DeviceModel,
    MC68705P5EPROMControlInputs,
    VECTOR_BOOTSTRAP,
    VECTOR_EXTERNAL,
    VECTOR_RESET,
    VECTOR_TIMER,
    eprom_control,
)


class MC68705P5DeviceModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: MC68705P5DeviceModel, **values: int | bool):
        return model.cycle(MC68705P5CycleInputs(**values))

    @classmethod
    def write(cls, model: MC68705P5DeviceModel, address: int, data: int, **values):
        return cls.cycle(model, address=address, valid=True, write=True, data=data, **values)

    @classmethod
    def read(cls, model: MC68705P5DeviceModel, address: int, **values):
        return cls.cycle(model, address=address, valid=True, write=False, **values)

    def test_pcr_programming_table_is_exact(self) -> None:
        states = {
            (True, False, False): "program",
            (False, False, False): "controls_disconnected",
            (True, True, False): "latch_address_data",
            (False, True, False): "controls_disconnected",
            (True, False, True): "invalid",
            (False, False, True): "invalid",
            (True, True, True): "high_voltage_on_vpp",
            (False, True, True): "operating",
        }
        self.assertEqual(set(states.values()), set(EPROM_CONTROL_DEFINED_STATES))
        for (vpp, pge, ple), expected in states.items():
            control = eprom_control(
                MC68705P5EPROMControlInputs(vpp_present=vpp, pge=pge, ple=ple)
            )
            self.assertEqual(control.state, expected)
            if expected == "invalid":
                self.assertIsNone(control.read_enabled)
                self.assertIsNone(control.latch_enabled)
                self.assertIsNone(control.program_enabled)
            else:
                self.assertEqual(control.read_enabled, not vpp or ple)
                self.assertEqual(control.latch_enabled, vpp and not ple)
                self.assertEqual(
                    control.program_enabled, vpp and not ple and not pge
                )

    def test_all_software_pcr_writes_obey_interlock(self) -> None:
        for vpp in (False, True):
            for data in range(4):
                program = Memory()
                program[0x080] = 0xA5
                model = MC68705P5DeviceModel(program_memory=program)
                result = self.write(model, 0x00B, data, vpp_present=vpp)
                ple = bool(data & 0x01)
                pge = bool(data & 0x02) or ple
                control = eprom_control(
                    MC68705P5EPROMControlInputs(
                        vpp_present=vpp, pge=pge, ple=ple
                    )
                )
                self.assertNotEqual(control.state, "invalid")
                self.assertEqual(result.eprom_latch_enable, control.latch_enabled)
                self.assertEqual(result.eprom_program_enable, control.program_enabled)
                self.assertEqual(
                    self.read(model, 0x00B, vpp_present=vpp).read_data,
                    0xF8 | (int(not vpp) << 2) | (int(pge) << 1) | int(ple),
                )
                read = self.read(model, 0x080, vpp_present=vpp)
                self.assertEqual(read.program_read, control.read_enabled)
                self.assertEqual(read.read_data, 0xA5 if control.read_enabled else 0xFF)

    def test_programming_address_decode_is_exhaustive(self) -> None:
        programmable = 0
        for address in range(0x800):
            model = MC68705P5DeviceModel()
            self.write(model, 0x00B, 0x02, vpp_present=True)
            result = self.write(model, address, 0x5A, vpp_present=True)
            if model.eprom_is_programmable(address):
                programmable += 1
                self.assertEqual(result.state["EPROM_ADDRESS"], address)
                self.assertEqual(result.state["EPROM_DATA"], 0x5A)
            else:
                self.assertEqual(result.state["EPROM_ADDRESS"], 0)
                self.assertEqual(result.state["EPROM_DATA"], 0)
        # 1804 user bytes plus the separately addressed mask-option byte.
        self.assertEqual(programmable, 1805)

    def test_memory_gpio_and_reset_preserve_ram(self) -> None:
        program = Memory()
        program[0x080] = 0xA5
        program[0x785] = 0x5A
        model = MC68705P5DeviceModel(program_memory=program)

        self.assertEqual(self.read(model, 0x080).read_data, 0xA5)
        self.assertEqual(self.read(model, 0x785).read_data, 0x5A)
        self.assertFalse(self.read(model, 0x784).program_read)
        self.assertEqual(self.read(model, 0x003).read_data, 0xFF)
        self.write(model, 0x000, 0xA5)
        self.write(model, 0x004, 0xF0)
        self.assertEqual(self.read(model, 0x000, port_a=0x3C).read_data, 0xAC)
        self.assertEqual(self.read(model, 0x004).read_data, 0xFF)
        self.write(model, 0x002, 0x05)
        self.write(model, 0x006, 0x03)
        self.assertEqual(self.read(model, 0x002, port_c=0x0A).read_data, 0xF9)
        self.assertEqual(model.port_outputs(), (0xA5, 0xF0, 0, 0, 5, 3))

        self.write(model, 0x010, 0x12)
        self.write(model, 0x07F, 0x34)
        model.state.timer_previous = True
        model.state.int_previous = False
        model.reset()
        self.assertEqual(model.state.timer_data, 0xFF)
        self.assertEqual(model.state.timer_prescaler, 0x7F)
        self.assertFalse(model.state.timer_previous)
        self.assertTrue(model.state.int_previous)
        self.assertEqual(self.read(model, 0x010).read_data, 0x12)
        self.assertEqual(self.read(model, 0x07F).read_data, 0x34)

    def test_all_timer_sources_and_prescaler(self) -> None:
        model = MC68705P5DeviceModel()
        self.write(model, 0x009, 0x00)  # internal, divide by one
        self.write(model, 0x008, 0x02)
        self.cycle(model)
        self.assertEqual(model.state.timer_data, 0x01)
        result = self.cycle(model)
        self.assertEqual(result.state["TDR"], 0x00)
        self.assertTrue(result.timer_irq)

        self.write(model, 0x009, 0x50)  # gated internal, divide by one
        self.write(model, 0x008, 0x02, timer=False)
        self.cycle(model, timer=False)
        self.assertEqual(model.state.timer_data, 0x02)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)

        self.write(model, 0x009, 0x60, timer=True)  # disabled
        self.write(model, 0x008, 0x02, timer=True)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x02)

        self.write(model, 0x009, 0x70, timer=True)  # positive transitions
        self.cycle(model, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)

        self.write(model, 0x009, 0x09, timer=False)  # internal /2 and PSC
        self.write(model, 0x008, 0x02)
        self.cycle(model)
        self.assertEqual(model.state.timer_data, 0x02)
        self.cycle(model)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model)
        self.assertEqual(model.state.timer_data, 0x00)

    def test_mor_controlled_timer_is_read_only_except_request_and_mask(self) -> None:
        # TOPT, external-clock source, divide by four.
        model = MC68705P5DeviceModel(mask_option=0x62)
        self.assertEqual(self.read(model, 0x009, timer=False).read_data, 0x7F)
        self.write(model, 0x009, 0x00, timer=False)
        self.assertEqual(self.read(model, 0x009, timer=False).read_data, 0x3F)
        self.write(model, 0x008, 0x02, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x01)
        self.cycle(model, timer=False)
        self.cycle(model, timer=True)
        self.assertEqual(model.state.timer_data, 0x00)

    def test_interrupt_latching_priority_and_vector_acknowledge(self) -> None:
        model = MC68705P5DeviceModel()
        model.state.timer_request = True
        model.state.timer_mask = False
        result = self.cycle(model)
        self.assertTrue(result.irq_request)
        self.assertEqual(result.irq_vector, VECTOR_TIMER)

        result = self.cycle(model, int_n=False)
        self.assertTrue(result.external_irq)
        self.assertEqual(result.irq_vector, VECTOR_EXTERNAL)
        result = self.read(model, VECTOR_EXTERNAL, int_n=False)
        self.assertFalse(result.external_irq)
        self.assertEqual(result.irq_vector, VECTOR_TIMER)
        self.assertTrue(result.irq_request)
        self.cycle(model, int_n=True)
        self.cycle(model, int_n=False)
        self.assertTrue(model.external_irq)

    def test_bootstrap_vector_secure_option_and_programming_latches(self) -> None:
        program = Memory()
        program[VECTOR_RESET] = 0x12
        program[VECTOR_BOOTSTRAP] = 0x34
        program[0x080] = 0xA5
        model = MC68705P5DeviceModel(program_memory=program)
        normal = self.read(model, VECTOR_RESET)
        self.assertEqual(normal.program_address, VECTOR_RESET)
        self.assertEqual(normal.read_data, 0x12)
        model = MC68705P5DeviceModel(program_memory=program)
        bootstrap = self.read(model, VECTOR_RESET, bootstrap_voltage=True)
        self.assertEqual(bootstrap.program_address, VECTOR_BOOTSTRAP)
        self.assertEqual(bootstrap.read_data, 0x34)
        self.assertTrue(bootstrap.bootstrap_mode)
        bootstrap_low = self.read(model, VECTOR_RESET + 1, bootstrap_voltage=False)
        self.assertEqual(bootstrap_low.program_address, VECTOR_BOOTSTRAP + 1)
        self.assertTrue(bootstrap_low.bootstrap_mode)
        ordinary = self.read(model, VECTOR_RESET, bootstrap_voltage=True)
        self.assertEqual(ordinary.program_address, VECTOR_RESET)

        secure = MC68705P5DeviceModel(mask_option=0x08, program_memory=program)
        secure_result = self.read(secure, VECTOR_RESET, bootstrap_voltage=True)
        self.assertEqual(secure_result.program_address, VECTOR_RESET)
        self.assertEqual(secure_result.read_data, 0x12)
        self.assertFalse(secure_result.bootstrap_mode)

        # VPP absent interlocks low PCR bits away from the EPROM array.
        self.write(model, 0x00B, 0x00)
        self.assertEqual(self.read(model, 0x00B).read_data, 0xFC)
        self.assertTrue(self.read(model, 0x080).program_read)
        self.assertEqual(self.read(model, 0x080).read_data, 0xA5)

        self.write(model, 0x00B, 0x02, vpp_present=True)  # latch mode, PGE high
        latched = self.write(model, 0x080, 0x5A, vpp_present=True)
        self.assertEqual(latched.state["EPROM_ADDRESS"], 0x080)
        self.assertEqual(latched.state["EPROM_DATA"], 0x5A)
        self.assertTrue(latched.eprom_latch_enable)
        self.assertFalse(latched.eprom_program_enable)
        self.assertFalse(self.read(model, 0x080, vpp_present=True).program_read)
        self.write(model, 0x00B, 0x00, vpp_present=True)
        programmed = self.cycle(model, vpp_present=True)
        self.assertTrue(programmed.eprom_program_enable)


if __name__ == "__main__":
    unittest.main()
