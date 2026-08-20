from __future__ import annotations

import unittest

from model.hd63701v0_prom import (
    DEFINED_STATES,
    HD63701V0PromInputs,
    prom_address,
    prom_cycle,
)


class HD63701V0PromModelTests(unittest.TestCase):
    def cycle(self, **values: int | bool):
        inputs: dict[str, int | bool] = {
            "prom_mode": True,
            "program_voltage": False,
            "ce_n": False,
            "oe_n": False,
            "port1": 0x5A,
            "port3": 0xC7,
            "port4_address": 0,
            "irq_a9": False,
            "program_data": 0x96,
        }
        inputs.update(values)
        return prom_cycle(HD63701V0PromInputs(**inputs))

    def test_address_pin_mapping_is_exhaustive(self) -> None:
        for address in range(0x8000):
            port4 = (
                ((address >> 14) & 1) << 1
                | ((address >> 10) & 0xF) << 2
                | ((address >> 8) & 1)
            )
            self.assertEqual(
                prom_address(
                    port1=address & 0xFF,
                    port4_address=port4,
                    irq_a9=bool(address & 0x200),
                ),
                address,
            )
            read_cycle = self.cycle(
                port1=address & 0xFF,
                port4_address=port4,
                irq_a9=bool(address & 0x200),
            )
            internal = address <= 0x0FFF
            self.assertEqual(read_cycle.address, address)
            self.assertEqual(read_cycle.internal_address, internal)
            self.assertEqual(
                read_cycle.storage_address, 0xF000 | (address & 0x0FFF)
            )
            self.assertEqual(read_cycle.storage_read, internal)
            self.assertEqual(read_cycle.data, 0x96 if internal else 0xFF)

            program_cycle = self.cycle(
                program_voltage=True,
                ce_n=False,
                oe_n=True,
                port1=address & 0xFF,
                port4_address=port4,
                irq_a9=bool(address & 0x200),
            )
            self.assertEqual(program_cycle.address, address)
            self.assertEqual(program_cycle.program_request, internal)

    def test_table_3_1_states_are_exact(self) -> None:
        states = {
            (False, False, False): "read",
            (False, False, True): "output_disable",
            (True, False, True): "program",
            (True, True, False): "verify",
            (True, True, True): "program_inhibit",
        }
        self.assertEqual(set(states.values()), set(DEFINED_STATES))
        for (vpp, ce_n, oe_n), expected in states.items():
            cycle = self.cycle(
                program_voltage=vpp, ce_n=ce_n, oe_n=oe_n
            )
            self.assertEqual(cycle.state, expected)
            self.assertEqual(cycle.data_oe, expected in {"read", "verify"})
            self.assertEqual(cycle.storage_read, expected in {"read", "verify"})
            self.assertEqual(cycle.program_request, expected == "program")

    def test_four_kib_boundary_and_erased_extension(self) -> None:
        inside = self.cycle(port1=0xFF, port4_address=0x0D, irq_a9=True)
        self.assertEqual(inside.address, 0x0FFF)
        self.assertEqual(inside.storage_address, 0xFFFF)
        self.assertEqual(inside.data, 0x96)
        self.assertTrue(inside.storage_read)

        outside = self.cycle(port1=0, port4_address=0x10, irq_a9=False)
        self.assertEqual(outside.address, 0x1000)
        self.assertEqual(outside.data, 0xFF)
        self.assertTrue(outside.data_oe)
        self.assertFalse(outside.storage_read)
        programmed_outside = self.cycle(
            program_voltage=True, ce_n=False, oe_n=True,
            port1=0, port4_address=0x10,
        )
        self.assertFalse(programmed_outside.program_request)

    def test_unlisted_controls_are_safe_and_explicitly_undefined(self) -> None:
        for vpp, ce_n, oe_n in (
            (False, True, False),
            (False, True, True),
            (True, False, False),
        ):
            cycle = self.cycle(
                program_voltage=vpp, ce_n=ce_n, oe_n=oe_n
            )
            self.assertEqual(cycle.state, "undefined_by_documentation")
            self.assertFalse(cycle.data_oe)
            self.assertFalse(cycle.storage_read)
            self.assertFalse(cycle.program_request)


if __name__ == "__main__":
    unittest.main()
