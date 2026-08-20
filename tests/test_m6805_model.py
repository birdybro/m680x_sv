from __future__ import annotations

import unittest

from model.common import Memory, UndefinedBehavior
from model.m6805 import M6805Model, M6805State


def _fixture(architecture: str, opcode: int) -> M6805Model:
    memory = Memory()
    memory.load(0x1000, [opcode, 0x10, 0x20, 0x30])
    for address in (0x0010, 0x0020, 0x0030, 0x0031, 0x1020, 0x1040):
        memory[address] = (address ^ 0xA6) & 0xFF
    memory.load(0xFFFA, [0x21, 0x00, 0x22, 0x00, 0x23, 0x00])
    for offset, value in enumerate((0xE0, 0x12, 0x20, 0x10, 0x04), start=1):
        memory[0x70 + offset] = value
    state = M6805State(a=0x12, x=0x20, sp=0x70, pc=0x1000, ccr=0)
    return M6805Model(architecture, memory=memory, state=state)


class M6805ModelTests(unittest.TestCase):
    def test_every_documented_encoding_executes(self) -> None:
        counts: dict[str, int] = {}
        for architecture in ("m6805", "hd6305"):
            template = M6805Model(architecture)
            count = 0
            for record in template.spec["opcodes"]:
                if record["classification"] != "documented_instruction":
                    continue
                model = _fixture(architecture, record["opcode"])
                trace = model.step()
                self.assertEqual(trace.opcode, record["opcode"])
                self.assertEqual(trace.mnemonic, record["mnemonic"])
                self.assertEqual(trace.documented_cycles, record["cycles"])
                self.assertEqual(trace.accesses[0].purpose, "opcode")
                count += 1
            counts[architecture] = count
        self.assertEqual(counts, {"m6805": 207, "hd6305": 210})

    def test_undefined_and_cmos_only_opcodes_are_not_executed_as_hmos(self) -> None:
        for opcode in (0x8D, 0x8E, 0x8F):
            model = _fixture("m6805", opcode)
            with self.assertRaises(UndefinedBehavior):
                model.step()
            self.assertEqual(model.state.pc, 0x1001)

    def test_all_indexed_forms_and_wraparound(self) -> None:
        no_offset = _fixture("m6805", 0xF6)  # LDA ,X
        no_offset.memory[0x20] = 0x11
        no_offset.step()
        self.assertEqual(no_offset.state.a, 0x11)

        offset8 = _fixture("m6805", 0xE6)  # LDA offset8,X
        offset8.memory[0x30] = 0x22
        offset8.step()
        self.assertEqual(offset8.state.a, 0x22)

        offset16 = _fixture("m6805", 0xD6)  # LDA offset16,X
        offset16.memory[0x1040] = 0x33
        offset16.step()
        self.assertEqual(offset16.state.a, 0x33)

        wrapped = _fixture("m6805", 0xE6)
        wrapped.state.x = 0xF8
        wrapped.memory[0x0108] = 0x44
        wrapped.step()
        self.assertEqual(wrapped.state.a, 0x44)

    def test_bit_modify_and_test_branch_copy_tested_bit_to_c(self) -> None:
        set_bit = _fixture("m6805", 0x16)  # BSET3
        set_bit.memory[0x10] = 0x01
        set_bit.step()
        self.assertEqual(set_bit.memory[0x10], 0x09)

        clear_bit = _fixture("m6805", 0x17)  # BCLR3
        clear_bit.memory[0x10] = 0xFF
        clear_bit.step()
        self.assertEqual(clear_bit.memory[0x10], 0xF7)

        branch_set = _fixture("m6805", 0x06)  # BRSET3
        branch_set.memory.load(0x1001, [0x10, 0x7F])
        branch_set.memory[0x10] = 0x08
        branch_set.step()
        self.assertEqual(branch_set.state.pc, 0x1082)
        self.assertTrue(branch_set.flag("C"))

        branch_clear = _fixture("m6805", 0x07)  # BRCLR3
        branch_clear.memory.load(0x1001, [0x10, 0x80])
        branch_clear.memory[0x10] = 0x00
        branch_clear.step()
        self.assertEqual(branch_clear.state.pc, 0x0F83)
        self.assertFalse(branch_clear.flag("C"))

    def test_branch_conditions_include_half_carry_mask_and_irq_pin(self) -> None:
        branches = {
            0x20: lambda h, i, n, z, c, irq_n: True,
            0x21: lambda h, i, n, z, c, irq_n: False,
            0x22: lambda h, i, n, z, c, irq_n: not c and not z,
            0x23: lambda h, i, n, z, c, irq_n: c or z,
            0x24: lambda h, i, n, z, c, irq_n: not c,
            0x25: lambda h, i, n, z, c, irq_n: c,
            0x26: lambda h, i, n, z, c, irq_n: not z,
            0x27: lambda h, i, n, z, c, irq_n: z,
            0x28: lambda h, i, n, z, c, irq_n: not h,
            0x29: lambda h, i, n, z, c, irq_n: h,
            0x2A: lambda h, i, n, z, c, irq_n: not n,
            0x2B: lambda h, i, n, z, c, irq_n: n,
            0x2C: lambda h, i, n, z, c, irq_n: not i,
            0x2D: lambda h, i, n, z, c, irq_n: i,
            0x2E: lambda h, i, n, z, c, irq_n: not irq_n,
            0x2F: lambda h, i, n, z, c, irq_n: irq_n,
        }
        for opcode, condition in branches.items():
            for ccr in range(0x20):
                for irq_n in (False, True):
                    model = _fixture("m6805", opcode)
                    model.state.ccr = ccr
                    model.irq_n = irq_n
                    flags = tuple(model.flag(name) for name in ("H", "I", "N", "Z", "C"))
                    taken = condition(*flags, irq_n)
                    model.step()
                    self.assertEqual(model.state.pc, 0x1012 if taken else 0x1002)

    def test_jsr_rts_and_swi_rti_stack_order(self) -> None:
        call = _fixture("m6805", 0xCD)
        call.step()
        self.assertEqual(call.state.pc, 0x1020)
        self.assertEqual(call.state.sp, 0x6E)
        self.assertEqual(call.memory[0x70], 0x03)
        self.assertEqual(call.memory[0x6F], 0x10)
        call.memory[0x1020] = 0x81
        call.step()
        self.assertEqual(call.state.pc, 0x1003)

        interrupt = _fixture("m6805", 0x83)
        interrupt.state.ccr = 0x11
        interrupt.memory.load(0xFFFC, [0x22, 0x00])
        trace = interrupt.step()
        self.assertEqual(interrupt.state.pc, 0x2200)
        self.assertEqual(interrupt.state.sp, 0x6B)
        self.assertEqual(
            [(access.kind, access.address, access.data) for access in trace.accesses[:-1]],
            [
                ("read", 0x1000, 0x83),
                ("read", 0x1001, 0x10),
                ("write", 0x0070, 0x01),
                ("write", 0x006F, 0x10),
                ("write", 0x006E, 0x20),
                ("write", 0x006D, 0x12),
                ("write", 0x006C, 0xF1),
                ("read", 0x006B, 0x00),
                ("read", 0xFFFC, 0x22),
                ("read", 0xFFFD, 0x00),
            ],
        )
        self.assertEqual(
            (trace.accesses[-1].kind, trace.accesses[-1].address),
            ("read", 0x2200),
        )
        self.assertTrue(trace.accesses[-1].data_defined)
        self.assertEqual(
            [interrupt.memory[address] for address in range(0x6C, 0x71)],
            [0xF1, 0x12, 0x20, 0x10, 0x01],
        )
        interrupt.memory[0x2200] = 0x80
        interrupt.step()
        self.assertEqual(
            interrupt.state.snapshot(),
            M6805State(a=0x12, x=0x20, sp=0x70, pc=0x1001, ccr=0x11).snapshot(),
        )

    def test_m6805_hardware_irq_cycle_table_accesses(self) -> None:
        model = _fixture("m6805", 0x9D)
        self.assertTrue(model.service_irq())
        self.assertEqual(model.state.pc, 0x2100)
        self.assertEqual(
            [(access.kind, access.address, access.data) for access in model.bus_accesses[:-1]],
            [
                ("read", 0x1000, 0x9D),
                ("read", 0x1000, 0x9D),
                ("write", 0x0070, 0x00),
                ("write", 0x006F, 0x10),
                ("write", 0x006E, 0x20),
                ("write", 0x006D, 0x12),
                ("write", 0x006C, 0xE0),
                ("read", 0x006B, 0x00),
                ("read", 0xFFFA, 0x21),
                ("read", 0xFFFB, 0x00),
            ],
        )
        self.assertEqual(
            (model.bus_accesses[-1].kind, model.bus_accesses[-1].address),
            ("read", 0xFFFC),
        )
        self.assertFalse(model.bus_accesses[-1].data_defined)

    def test_m6805_table_g2_inherent_relative_and_return_traces(self) -> None:
        expected = {
            0x9D: [0x1000, 0x1001],  # NOP
            0x40: [0x1000, 0x1001, 0x1002, 0x1002],  # NEGA
            0x20: [0x1000, 0x1001, 0x1002, 0x1002],  # BRA
            0xAD: [0x1000, 0x1001, 0x1002, 0x1002, 0x1012, 0x0070, 0x006F, 0x006E],  # BSR
            0x81: [0x1000, 0x1001, 0x0070, 0x0071, 0x0072, 0x0073],  # RTS
            0x80: [0x1000, 0x1001, 0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076],  # RTI
        }
        for opcode, addresses in expected.items():
            with self.subTest(opcode=f"{opcode:02X}"):
                model = _fixture("m6805", opcode)
                trace = model.step()
                self.assertEqual(len(trace.accesses), trace.documented_cycles)
                self.assertEqual([access.address for access in trace.accesses], addresses)

        bsr = _fixture("m6805", 0xAD)
        trace = bsr.step()
        self.assertEqual(
            [access.kind for access in trace.accesses],
            ["read"] * 5 + ["write", "write", "read"],
        )
        self.assertEqual(bsr.state.pc, 0x1012)

    def test_hd6305_low_power_and_irq_entry(self) -> None:
        for opcode, state_name in ((0x8E, "stopped"), (0x8F, "waiting")):
            model = _fixture("hd6305", opcode)
            model.memory.load(0xFFFA, [0x24, 0x00])
            model.set_flag("I", True)
            model.step()
            self.assertTrue(getattr(model.state, state_name))
            self.assertFalse(model.flag("I"))
            self.assertTrue(model.service_irq())
            self.assertEqual(model.state.pc, 0x2400)
            self.assertFalse(model.state.waiting)
            self.assertFalse(model.state.stopped)
            self.assertTrue(model.flag("I"))
            self.assertEqual(model.state.sp, 0x6B)

    def test_hd6305_pending_irq_prevents_wait_and_stop_entry(self) -> None:
        for opcode in (0x8E, 0x8F):
            model = _fixture("hd6305", opcode)
            model.memory.load(0xFFFA, [0x24, 0x00])
            model.set_flag("I", True)
            model.irq_n = False
            trace = model.step()
            self.assertEqual(trace.documented_cycles, 4)
            self.assertFalse(model.state.waiting)
            self.assertFalse(model.state.stopped)
            self.assertFalse(model.flag("I"))
            self.assertTrue(model.service_irq())
            self.assertEqual(model.state.pc, 0x2400)
            self.assertEqual(model.state.sp, 0x6B)
            self.assertEqual(
                [model.memory[address] for address in range(0x6C, 0x71)],
                [0xE0, 0x12, 0x20, 0x10, 0x01],
            )

    def test_five_bit_stack_wraps_within_0060_to_007f(self) -> None:
        model = _fixture("m6805", 0xCD)
        model.state.sp = 0x60
        model.step()
        self.assertEqual(model.memory[0x60], 0x03)
        self.assertEqual(model.memory[0x7F], 0x10)
        self.assertEqual(model.state.sp, 0x7E)

    def test_hd6305_executes_instruction_after_cli_before_irq(self) -> None:
        model = _fixture("hd6305", 0x9A)
        model.memory[0x1001] = 0x9D
        model.memory.load(0xFFFA, [0x25, 0x00])
        model.set_flag("I", True)
        model.step()
        self.assertFalse(model.service_irq())
        model.step()
        self.assertEqual(model.state.pc, 0x1002)
        self.assertTrue(model.service_irq())
        self.assertEqual(model.state.pc, 0x2500)

    def test_reset_rsp_and_hd6305_daa(self) -> None:
        reset = _fixture("m6805", 0x9C)
        reset.memory.load(0xFFFE, [0xAB, 0xCD])
        reset.reset()
        self.assertEqual(reset.state.pc, 0xABCD)
        self.assertEqual(reset.state.sp, 0x7F)
        self.assertTrue(reset.flag("I"))
        self.assertEqual(
            [(access.kind, access.address) for access in reset.bus_accesses],
            [("read", 0xFFFE)] * 6 + [("read", 0xFFFF), ("read", 0x0000)],
        )
        self.assertTrue(all(access.data_defined for access in reset.bus_accesses[:-1]))
        self.assertFalse(reset.bus_accesses[-1].data_defined)
        reset.memory[0xABCD] = 0x9C
        reset.state.sp = 0x22
        reset.step()
        self.assertEqual(reset.state.sp, 0x7F)

        daa = _fixture("hd6305", 0x8D)
        daa.state.a = 0x9A
        daa.set_flag("H", False)
        daa.set_flag("C", False)
        daa.step()
        self.assertEqual(daa.state.a, 0x00)
        self.assertTrue(daa.flag("Z"))
        self.assertTrue(daa.flag("C"))


if __name__ == "__main__":
    unittest.main()
