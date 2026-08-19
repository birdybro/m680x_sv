"""Independent architectural model for M6805/HD6305 lineages."""

from __future__ import annotations

from dataclasses import dataclass

from model import alu
from model.common import BusAccess, InstructionTrace, Memory, UndefinedBehavior, load_opcode_spec


ARCHITECTURES = {"m6805", "hd6305"}
FLAG_BITS = {"H": 4, "I": 3, "N": 2, "Z": 1, "C": 0}
DATA_OPS = {"SUB", "CMP", "SBC", "CPX", "AND", "BIT", "LDA", "STA", "EOR", "ADC", "ORA", "ADD", "JMP", "JSR", "LDX", "STX"}
RMW_OPS = {"NEG", "COM", "LSR", "ROR", "ASR", "ASL", "ROL", "DEC", "INC", "TST", "CLR"}


@dataclass
class M6805State:
    a: int = 0
    x: int = 0
    sp: int = 0x7F
    pc: int = 0
    ccr: int = 0
    waiting: bool = False
    stopped: bool = False

    def snapshot(self) -> dict[str, int | bool]:
        return {
            "A": self.a,
            "X": self.x,
            "SP": self.sp,
            "PC": self.pc,
            "CCR": self.ccr & 0x1F,
            "waiting": self.waiting,
            "stopped": self.stopped,
        }


class M6805Model:
    """Instruction-level model for the M6805 and Hitachi HD6305 ISAs."""

    def __init__(
        self,
        architecture: str = "m6805",
        *,
        memory: Memory | None = None,
        state: M6805State | None = None,
        stack_bits: int = 5,
    ) -> None:
        if architecture not in ARCHITECTURES:
            raise ValueError(f"unsupported M6805-lineage architecture: {architecture}")
        self.architecture = architecture
        self.spec = load_opcode_spec(architecture)
        if not isinstance(stack_bits, int) or not 1 <= stack_bits <= 7:
            raise ValueError("stack_bits must be between 1 and 7")
        self.stack_bits = stack_bits
        self.stack_mask = (1 << stack_bits) - 1
        self.stack_base = 0x80 - (1 << stack_bits)
        self.memory = memory if memory is not None else Memory()
        self.state = state if state is not None else M6805State()
        self.irq_n = True
        self.instruction_count = 0
        self._irq_defer_instructions = 0
        self.last_trace: InstructionTrace | None = None
        self._accesses: list[BusAccess] = []

    def flag(self, name: str) -> bool:
        return bool(self.state.ccr & (1 << FLAG_BITS[name]))

    def set_flag(self, name: str, value: int | bool) -> None:
        mask = 1 << FLAG_BITS[name]
        if value:
            self.state.ccr |= mask
        else:
            self.state.ccr &= ~mask
        self.state.ccr &= 0x1F

    def packed_ccr(self) -> int:
        return 0xE0 | (self.state.ccr & 0x1F)

    def reset(self) -> None:
        self.state = M6805State()
        self.set_flag("I", True)
        self._irq_defer_instructions = 0
        self._accesses = []
        self.state.pc = self._read16(0xFFFE, "reset vector")
        self.last_trace = None

    def service_irq(self) -> bool:
        """Accept the external maskable interrupt at an instruction boundary."""

        if self.flag("I") or self._irq_defer_instructions:
            return False
        self._accesses = []
        self.state.waiting = False
        self.state.stopped = False
        self._stack_complete_state()
        self.set_flag("I", True)
        self.state.pc = self._read16(0xFFFA, "IRQ vector")
        self._validate_state()
        return True

    def step(self) -> InstructionTrace:
        if self.state.waiting or self.state.stopped:
            raise RuntimeError("processor is in a low-power state; service an interrupt or reset")
        before = self.state.snapshot()
        defer_before = self._irq_defer_instructions
        start_pc = self.state.pc
        self._accesses = []
        opcode = self._fetch8("opcode")
        record = self.spec["opcodes"][opcode]
        if record["classification"] != "documented_instruction":
            raise UndefinedBehavior(
                f"{self.architecture} opcode {opcode:02X} is {record['classification']}"
            )
        trace = InstructionTrace(
            instruction=self.instruction_count,
            pc=start_pc,
            opcode=opcode,
            mnemonic=record["mnemonic"],
            architecture=self.architecture,
            documented_cycles=record["cycles"],
            state_before=before,
            undefined_flags=list(record["flags_undefined"]),
        )
        operand, address, displacement = self._decode_operand(record)
        trace.effective_address = address
        self._execute(record, operand, address, displacement)
        if defer_before:
            self._irq_defer_instructions = defer_before - 1
        if record["mnemonic"] == "CLI" and self.architecture == "hd6305":
            self._irq_defer_instructions = 1
        elif record["mnemonic"] in {"SEI", "STOP", "WAIT"}:
            self._irq_defer_instructions = 0
        self._validate_state()
        trace.state_after = self.state.snapshot()
        trace.accesses = list(self._accesses)
        self.instruction_count += 1
        self.last_trace = trace
        return trace

    def _validate_state(self) -> None:
        self.state.a &= 0xFF
        self.state.x &= 0xFF
        self.state.sp = self.stack_base | (self.state.sp & self.stack_mask)
        self.state.pc &= 0xFFFF
        self.state.ccr &= 0x1F

    def _read8(self, address: int, purpose: str) -> int:
        address &= 0xFFFF
        value = self.memory[address]
        self._accesses.append(BusAccess("read", address, value, purpose))
        return value

    def _write8(self, address: int, value: int, purpose: str) -> None:
        address &= 0xFFFF
        value &= 0xFF
        self.memory[address] = value
        self._accesses.append(BusAccess("write", address, value, purpose))

    def _read16(self, address: int, purpose: str) -> int:
        high = self._read8(address, f"{purpose} high")
        low = self._read8(address + 1, f"{purpose} low")
        return (high << 8) | low

    def _fetch8(self, purpose: str) -> int:
        value = self._read8(self.state.pc, purpose)
        self.state.pc = (self.state.pc + 1) & 0xFFFF
        return value

    def _fetch16(self, purpose: str) -> int:
        high = self._fetch8(f"{purpose} high")
        low = self._fetch8(f"{purpose} low")
        return (high << 8) | low

    def _push8(self, value: int, purpose: str) -> None:
        self._write8(self.state.sp, value, purpose)
        self.state.sp = self.stack_base | ((self.state.sp - 1) & self.stack_mask)

    def _pull8(self, purpose: str) -> int:
        self.state.sp = self.stack_base | ((self.state.sp + 1) & self.stack_mask)
        return self._read8(self.state.sp, purpose)

    def _push_return_pc(self) -> None:
        self._push8(self.state.pc & 0xFF, "return PC low")
        self._push8(self.state.pc >> 8, "return PC high")

    def _pull_pc(self) -> None:
        high = self._pull8("return PC high")
        low = self._pull8("return PC low")
        self.state.pc = (high << 8) | low

    @staticmethod
    def _signed(byte: int) -> int:
        return byte - 0x100 if byte & 0x80 else byte

    def _decode_operand(self, record: dict) -> tuple[int | None, int | None, int | None]:
        mnemonic = record["mnemonic"]
        mode = record["addressing_mode"]
        if mode == "bit-test-branch-direct":
            address = self._fetch8("direct bit address")
            displacement = self._signed(self._fetch8("relative displacement"))
            return self._read8(address, "bit-test operand"), address, displacement
        if mode == "bit-set-clear-direct":
            address = self._fetch8("direct bit address")
            return self._read8(address, "bit-modify operand"), address, None
        if mode in {"inherent", "accumulator-a", "index-register-x"}:
            return None, None, None
        if mode == "relative":
            return None, None, self._signed(self._fetch8("relative displacement"))
        if mode == "immediate-8":
            return self._fetch8("immediate operand"), None, None
        if mode == "direct":
            address = self._fetch8("direct address")
        elif mode == "extended":
            address = self._fetch16("extended address")
        elif mode == "indexed-no-offset":
            address = self.state.x
        elif mode == "indexed-unsigned-8":
            address = (self.state.x + self._fetch8("indexed 8-bit offset")) & 0xFFFF
        elif mode == "indexed-unsigned-16":
            address = (self.state.x + self._fetch16("indexed 16-bit offset")) & 0xFFFF
        else:
            raise AssertionError(f"unsupported M6805 addressing mode {mode}")
        if mnemonic in {"STA", "STX", "JMP", "JSR"}:
            return None, address, None
        if mnemonic == "CLR":
            return None, address, None
        return self._read8(address, "effective operand"), address, None

    def _merge_flags(self, result: alu.ALUResult | alu.DAAResult, record: dict) -> None:
        for name in record["flags_affected"]:
            if name not in result.flags:
                raise AssertionError(f"{record['mnemonic']} did not produce documented flag {name}")
            self.set_flag(name, result.flags[name])

    def _execute(
        self,
        record: dict,
        operand: int | None,
        address: int | None,
        displacement: int | None,
    ) -> None:
        mnemonic = record["mnemonic"]
        rmw = (
            mnemonic[:-1]
            if mnemonic[-1:] in {"A", "X"} and mnemonic[:-1] in RMW_OPS
            else mnemonic
        )
        if mnemonic.startswith(("BRSET", "BRCLR")):
            assert operand is not None and displacement is not None
            bit = int(mnemonic[-1])
            bit_set = bool(operand & (1 << bit))
            self.set_flag("C", bit_set)
            if bit_set == mnemonic.startswith("BRSET"):
                self.state.pc = (self.state.pc + displacement) & 0xFFFF
            return
        if mnemonic.startswith(("BSET", "BCLR")):
            assert operand is not None and address is not None
            bit = int(mnemonic[-1])
            if mnemonic.startswith("BSET"):
                value = operand | (1 << bit)
            else:
                value = operand & ~(1 << bit)
            self._write8(address, value, "bit-modify result")
            return

        if mnemonic in DATA_OPS:
            left = self.state.x if mnemonic == "CPX" else self.state.a
            if mnemonic in {"STA", "STX"}:
                value = self.state.a if mnemonic == "STA" else self.state.x
                assert address is not None
                self._write8(address, value, f"store {mnemonic[-1]}")
                result = alu.and8(value, 0xFF)
            elif mnemonic in {"JMP", "JSR"}:
                assert address is not None
                if mnemonic == "JSR":
                    self._push_return_pc()
                self.state.pc = address
                return
            else:
                assert operand is not None
                if mnemonic in {"ADD", "ADC"}:
                    result = alu.add8(left, operand, self.flag("C") if mnemonic == "ADC" else 0)
                elif mnemonic in {"SUB", "SBC", "CMP", "CPX"}:
                    result = alu.sub8(left, operand, self.flag("C") if mnemonic == "SBC" else 0)
                elif mnemonic in {"AND", "BIT"}:
                    result = alu.and8(left, operand)
                elif mnemonic == "EOR":
                    result = alu.xor8(left, operand)
                elif mnemonic == "ORA":
                    result = alu.or8(left, operand)
                elif mnemonic in {"LDA", "LDX"}:
                    result = alu.and8(operand, 0xFF)
                else:
                    raise AssertionError(mnemonic)
                if mnemonic not in {"CMP", "CPX", "BIT"}:
                    if mnemonic == "LDX":
                        self.state.x = result.value
                    else:
                        self.state.a = result.value
            self._merge_flags(result, record)
            return

        if rmw in RMW_OPS:
            if record["addressing_mode"] == "accumulator-a":
                value = self.state.a
                destination = "A"
            elif record["addressing_mode"] == "index-register-x":
                value = self.state.x
                destination = "X"
            else:
                value = 0 if rmw == "CLR" else operand
                assert value is not None and address is not None
                destination = "memory"
            operation = {
                "NEG": alu.neg8,
                "COM": alu.com8,
                "LSR": alu.lsr8,
                "ASR": alu.asr8,
                "ASL": alu.asl8,
                "DEC": alu.dec8,
                "INC": alu.inc8,
                "TST": alu.tst8,
                "CLR": lambda _value: alu.clr8(),
            }.get(rmw)
            if rmw == "ROR":
                result = alu.ror8(value, self.flag("C"))
            elif rmw == "ROL":
                result = alu.rol8(value, self.flag("C"))
            else:
                assert operation is not None
                result = operation(value)
            if rmw != "TST":
                if destination == "A":
                    self.state.a = result.value
                elif destination == "X":
                    self.state.x = result.value
                else:
                    assert address is not None
                    self._write8(address, result.value, "read-modify-write result")
            self._merge_flags(result, record)
            return

        if mnemonic in {"BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ", "BHCC", "BHCS", "BPL", "BMI", "BMC", "BMS", "BIL", "BIH"}:
            assert displacement is not None
            if self._branch_taken(mnemonic):
                self.state.pc = (self.state.pc + displacement) & 0xFFFF
        elif mnemonic == "BSR":
            assert displacement is not None
            self._push_return_pc()
            self.state.pc = (self.state.pc + displacement) & 0xFFFF
        elif mnemonic == "RTS":
            self._pull_pc()
        elif mnemonic == "RTI":
            self.state.ccr = self._pull8("stacked CCR") & 0x1F
            self.state.a = self._pull8("stacked A")
            self.state.x = self._pull8("stacked X")
            self._pull_pc()
        elif mnemonic == "SWI":
            self._stack_complete_state()
            self.set_flag("I", True)
            self.state.pc = self._read16(0xFFFC, "SWI vector")
        elif mnemonic == "TAX":
            self.state.x = self.state.a
        elif mnemonic == "TXA":
            self.state.a = self.state.x
        elif mnemonic == "RSP":
            self.state.sp = 0x7F
        elif mnemonic in {"CLC", "SEC", "CLI", "SEI"}:
            self.set_flag(mnemonic[-1], mnemonic.startswith("SE"))
        elif mnemonic == "DAA":
            result = alu.daa8(self.state.a, self.flag("H"), self.flag("C"))
            if not result.defined:
                raise UndefinedBehavior("DAA input state is outside the manufacturer table")
            self.state.a = result.value
            self._merge_flags(result, record)
        elif mnemonic in {"STOP", "WAIT"}:
            self.set_flag("I", False)
            if mnemonic == "STOP":
                self.state.stopped = True
            else:
                self.state.waiting = True
        elif mnemonic == "NOP":
            pass
        else:
            raise AssertionError(f"unimplemented documented instruction {mnemonic}")

    def _stack_complete_state(self) -> None:
        self._push8(self.state.pc & 0xFF, "stacked PC low")
        self._push8(self.state.pc >> 8, "stacked PC high")
        self._push8(self.state.x, "stacked X")
        self._push8(self.state.a, "stacked A")
        self._push8(self.packed_ccr(), "stacked CCR")

    def _branch_taken(self, mnemonic: str) -> bool:
        h, i, n, z, c = (self.flag(name) for name in ("H", "I", "N", "Z", "C"))
        return {
            "BRA": True,
            "BRN": False,
            "BHI": not c and not z,
            "BLS": c or z,
            "BCC": not c,
            "BCS": c,
            "BNE": not z,
            "BEQ": z,
            "BHCC": not h,
            "BHCS": h,
            "BPL": not n,
            "BMI": n,
            "BMC": not i,
            "BMS": i,
            "BIL": not self.irq_n,
            "BIH": self.irq_n,
        }[mnemonic]
