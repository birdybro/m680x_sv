from __future__ import annotations

import unittest

from model.common import Memory, UndefinedBehavior
from model.m6800 import M6800Model, M6800State


def _fixture(architecture: str, opcode: int) -> M6800Model:
    memory = Memory()
    memory.load(0x1000, [opcode, 0x10, 0x20, 0x30])
    for address in (0x0010, 0x0011, 0x0020, 0x0021, 0x1020, 0x1021, 0x2010, 0x2011):
        memory[address] = (address ^ 0x53) & 0xFF
    memory.load(0xFFFA, [0x30, 0x00, 0x31, 0x00, 0x32, 0x00])
    for offset, value in enumerate((0xC0, 0x34, 0x12, 0x20, 0x00, 0x10, 0x04), start=1):
        memory[0x4000 + offset] = value
    state = M6800State(a=0x12, b=0x34, x=0x2000, sp=0x4000, pc=0x1000, ccr=0)
    return M6800Model(architecture, memory=memory, state=state)


class M6800ModelTests(unittest.TestCase):
    def test_every_documented_encoding_executes(self) -> None:
        counts: dict[str, int] = {}
        for architecture in ("m6800", "m6801", "hd6301"):
            template = M6800Model(architecture)
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
        self.assertEqual(counts, {"m6800": 197, "m6801": 220, "hd6301": 230})

    def test_undefined_opcode_stops_after_fetch(self) -> None:
        model = _fixture("m6800", 0x00)
        with self.assertRaises(UndefinedBehavior):
            model.step()
        self.assertEqual(model.state.pc, 0x1001)

    def test_direct_indexed_extended_and_wraparound_addressing(self) -> None:
        direct = _fixture("m6800", 0x96)  # LDAA direct
        direct.memory[0x10] = 0xA5
        direct.step()
        self.assertEqual(direct.state.a, 0xA5)

        indexed = _fixture("m6800", 0xA6)  # LDAA indexed
        indexed.state.x = 0xFFF8
        indexed.memory[0x0008] = 0x5A
        indexed.step()
        self.assertEqual(indexed.state.a, 0x5A)

        extended = _fixture("m6800", 0xB6)  # LDAA extended
        extended.memory[0x1020] = 0xC3
        extended.step()
        self.assertEqual(extended.state.a, 0xC3)

        wrapped_pc = _fixture("m6800", 0x01)
        wrapped_pc.state.pc = 0xFFFF
        wrapped_pc.memory[0xFFFF] = 0x86  # LDAA immediate
        wrapped_pc.memory[0x0000] = 0x77
        wrapped_pc.step()
        self.assertEqual(wrapped_pc.state.pc, 0x0001)
        self.assertEqual(wrapped_pc.state.a, 0x77)

    def test_all_branch_conditions_and_displacement_extremes(self) -> None:
        branches = {
            0x20: lambda n, z, v, c: True,
            0x21: lambda n, z, v, c: False,
            0x22: lambda n, z, v, c: not c and not z,
            0x23: lambda n, z, v, c: c or z,
            0x24: lambda n, z, v, c: not c,
            0x25: lambda n, z, v, c: c,
            0x26: lambda n, z, v, c: not z,
            0x27: lambda n, z, v, c: z,
            0x28: lambda n, z, v, c: not v,
            0x29: lambda n, z, v, c: v,
            0x2A: lambda n, z, v, c: not n,
            0x2B: lambda n, z, v, c: n,
            0x2C: lambda n, z, v, c: n == v,
            0x2D: lambda n, z, v, c: n != v,
            0x2E: lambda n, z, v, c: not z and n == v,
            0x2F: lambda n, z, v, c: z or n != v,
        }
        for opcode, condition in branches.items():
            for ccr in range(0x40):
                model = _fixture("m6801", opcode)
                model.memory[0x1001] = 0x80
                model.state.ccr = ccr
                n, z, v, c = (model.flag(name) for name in ("N", "Z", "V", "C"))
                taken = condition(n, z, v, c)
                model.step()
                self.assertEqual(model.state.pc, 0x0F82 if taken else 0x1002)

        wrapped = _fixture("m6801", 0x20)
        wrapped.state.pc = 0xFFFE
        wrapped.memory.load(0xFFFE, [0x20, 0x7F])
        wrapped.step()
        self.assertEqual(wrapped.state.pc, 0x007F)

    def test_jsr_rts_stack_byte_order(self) -> None:
        model = _fixture("m6801", 0xBD)
        trace = model.step()
        self.assertEqual(model.state.pc, 0x1020)
        self.assertEqual(model.state.sp, 0x3FFE)
        self.assertEqual(model.memory[0x4000], 0x03)
        self.assertEqual(model.memory[0x3FFF], 0x10)
        self.assertEqual([access.data for access in trace.accesses[-2:]], [0x03, 0x10])

        model.memory[0x1020] = 0x39
        model.step()
        self.assertEqual(model.state.pc, 0x1003)
        self.assertEqual(model.state.sp, 0x4000)

    def test_swi_and_rti_restore_complete_state(self) -> None:
        model = _fixture("m6801", 0x3F)
        model.state.ccr = 0x25
        model.memory.load(0xFFFA, [0x30, 0x00])
        model.step()
        self.assertEqual(model.state.pc, 0x3000)
        self.assertTrue(model.flag("I"))
        self.assertEqual(model.state.sp, 0x3FF9)
        self.assertEqual(
            [model.memory[address] for address in range(0x3FFA, 0x4001)],
            [0xE5, 0x34, 0x12, 0x20, 0x00, 0x10, 0x01],
        )

        model.memory[0x3000] = 0x3B
        model.step()
        self.assertEqual(model.state.snapshot(), M6800State(a=0x12, b=0x34, x=0x2000, sp=0x4000, pc=0x1001, ccr=0x25).snapshot())

    def test_hd6301_immediate_memory_and_exchange_extensions(self) -> None:
        aim = _fixture("hd6301", 0x71)
        aim.memory.load(0x1001, [0x0F, 0x20])
        aim.memory[0x20] = 0xA5
        aim.step()
        self.assertEqual(aim.memory[0x20], 0x05)
        self.assertFalse(aim.flag("N"))
        self.assertFalse(aim.flag("Z"))
        self.assertFalse(aim.flag("V"))

        tim = _fixture("hd6301", 0x7B)
        tim.memory.load(0x1001, [0xF0, 0x20])
        tim.memory[0x20] = 0x85
        tim.step()
        self.assertEqual(tim.memory[0x20], 0x85)
        self.assertTrue(tim.flag("N"))

        xgdx = _fixture("hd6301", 0x18)
        xgdx.step()
        self.assertEqual(xgdx.state.d, 0x2000)
        self.assertEqual(xgdx.state.x, 0x1234)

    def test_hd6301_opcode_and_instruction_address_traps_retry_fetch(self) -> None:
        opcode_trap = _fixture("hd6301", 0x00)
        opcode_trap.memory.load(0xFFEE, [0x12, 0x00])
        trace = opcode_trap.step()
        self.assertEqual(trace.mnemonic, "TRAP")
        self.assertEqual(trace.documented_cycles, 13)
        self.assertEqual(opcode_trap.state.pc, 0x1200)
        self.assertEqual(opcode_trap.state.sp, 0x3FF9)
        self.assertEqual(
            [access.address for access in trace.accesses],
            [0x1000, 0x1001, 0xFFFF, 0xFFFF,
             0x4000, 0x3FFF, 0x3FFE, 0x3FFD, 0x3FFC, 0x3FFB, 0x3FFA,
             0xFFEE, 0xFFEF],
        )
        opcode_trap.memory[0x1200] = 0x3B
        opcode_trap.step()
        self.assertEqual(opcode_trap.state.pc, 0x1000)

        address_trap = _fixture("hd6301", 0x01)
        address_trap.memory.load(0xFFEE, [0x13, 0x00])
        address_trace = address_trap.step(instruction_address_error=True)
        self.assertEqual(address_trace.mnemonic, "TRAP")
        self.assertEqual(address_trap.state.pc, 0x1300)
        self.assertEqual(address_trap.memory[0x4000], 0x00)
        self.assertEqual(address_trap.memory[0x3FFF], 0x10)

    def test_reset_vector_and_trace_serialization(self) -> None:
        model = _fixture("m6800", 0x01)
        model.memory.load(0xFFFE, [0xAB, 0xCD])
        model.reset()
        self.assertEqual(model.state.pc, 0xABCD)
        self.assertTrue(model.flag("I"))
        model.memory[0xABCD] = 0x01
        trace = model.step()
        serialized = trace.as_dict()
        self.assertEqual(serialized["pc"], 0xABCD)
        self.assertEqual(serialized["state_after"]["PC"], 0xABCE)
        self.assertEqual(serialized["accesses"][0]["address"], 0xABCD)

    def test_irq_masking_and_wai_does_not_stack_twice(self) -> None:
        masked = _fixture("m6801", 0x01)
        masked.set_flag("I", True)
        self.assertFalse(masked.service_interrupt("irq"))
        self.assertEqual(masked.state.sp, 0x4000)

        model = _fixture("m6801", 0x3E)
        model.memory.load(0xFFF8, [0x22, 0x00])
        model.step()
        self.assertTrue(model.state.waiting)
        stacked_sp = model.state.sp
        self.assertTrue(model.service_interrupt("irq"))
        self.assertFalse(model.state.waiting)
        self.assertEqual(model.state.sp, stacked_sp)
        self.assertEqual(model.state.pc, 0x2200)
        self.assertTrue(model.flag("I"))

    def test_nmi_is_unmasked_and_stacks_running_state(self) -> None:
        model = _fixture("m6800", 0x01)
        model.set_flag("I", True)
        model.memory.load(0xFFFC, [0x23, 0x45])
        self.assertTrue(model.service_interrupt("nmi"))
        self.assertEqual(model.state.pc, 0x2345)
        self.assertEqual(model.state.sp, 0x3FF9)
        model.memory[0x2345] = 0x3B
        model.step()
        self.assertEqual(model.state.pc, 0x1000)
        self.assertEqual(model.state.sp, 0x4000)

    def test_m6801_and_hd6301_defer_maskable_irq_after_cli(self) -> None:
        for architecture, following_nops in (("m6801", 1), ("hd6301", 2)):
            model = _fixture(architecture, 0x0E)
            model.memory.load(0x1001, [0x01, 0x01, 0x01])
            model.memory.load(0xFFF8, [0x24, 0x00])
            model.set_flag("I", True)
            model.step()
            self.assertFalse(model.flag("I"), architecture)
            self.assertFalse(model.service_interrupt("irq"), architecture)
            for index in range(following_nops):
                model.step()
                if index + 1 < following_nops:
                    self.assertFalse(model.service_interrupt("irq"), architecture)
            self.assertTrue(model.service_interrupt("irq"), architecture)
            self.assertEqual(model.state.pc, 0x2400)

    def test_hd6301_masked_irq_releases_sleep_without_vectoring(self) -> None:
        model = _fixture("hd6301", 0x1A)
        model.set_flag("I", True)
        model.step()
        self.assertTrue(model.state.sleeping)
        stacked_sp = model.state.sp
        resume_pc = model.state.pc

        self.assertFalse(model.service_interrupt("irq"))
        self.assertFalse(model.state.sleeping)
        self.assertEqual(model.state.sp, stacked_sp)
        self.assertEqual(model.state.pc, resume_pc)

        model.memory[resume_pc] = 0x01
        model.step()
        self.assertEqual(model.state.pc, (resume_pc + 1) & 0xFFFF)


if __name__ == "__main__":
    unittest.main()
