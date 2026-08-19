"""Independent architectural model for M6800/MC6801/HD6301 lineages."""

from __future__ import annotations

from dataclasses import dataclass

from model import alu
from model.common import BusAccess, InstructionTrace, Memory, UndefinedBehavior, load_opcode_spec


ARCHITECTURES = {"m6800", "m6801", "hd6301"}
FLAG_BITS = {"H": 5, "I": 4, "N": 3, "Z": 2, "V": 1, "C": 0}
DATA_BASES = {"SUB", "CMP", "SBC", "AND", "BIT", "LDA", "STA", "EOR", "ADC", "ORA", "ADD"}
RMW_BASES = {"NEG", "COM", "LSR", "ROR", "ASR", "ASL", "ROL", "DEC", "INC", "TST", "CLR"}
WORD_READS = {"CPX", "LDS", "LDX", "LDD", "ADDD", "SUBD"}
WORD_STORES = {"STS", "STX", "STD"}


@dataclass
class M6800State:
    a: int = 0
    b: int = 0
    x: int = 0
    sp: int = 0
    pc: int = 0
    ccr: int = 0
    waiting: bool = False
    sleeping: bool = False

    @property
    def d(self) -> int:
        return (self.a << 8) | self.b

    @d.setter
    def d(self, value: int) -> None:
        self.a = (value >> 8) & 0xFF
        self.b = value & 0xFF

    def snapshot(self) -> dict[str, int | bool]:
        return {
            "A": self.a,
            "B": self.b,
            "X": self.x,
            "SP": self.sp,
            "PC": self.pc,
            "CCR": self.ccr & 0x3F,
            "waiting": self.waiting,
            "sleeping": self.sleeping,
        }


class M6800Model:
    """Instruction-level architectural model driven by factual opcode records."""

    def __init__(
        self,
        architecture: str = "m6800",
        *,
        memory: Memory | None = None,
        state: M6800State | None = None,
    ) -> None:
        if architecture not in ARCHITECTURES:
            raise ValueError(f"unsupported M6800-lineage architecture: {architecture}")
        self.architecture = architecture
        self.spec = load_opcode_spec(architecture)
        self.memory = memory if memory is not None else Memory()
        self.state = state if state is not None else M6800State()
        self.instruction_count = 0
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
        self.state.ccr &= 0x3F

    def packed_ccr(self) -> int:
        return 0xC0 | (self.state.ccr & 0x3F)

    def reset(self) -> None:
        self.state.a = 0
        self.state.b = 0
        self.state.x = 0
        self.state.sp = 0
        self.state.ccr = 0
        self.set_flag("I", True)
        self.state.waiting = False
        self.state.sleeping = False
        self._accesses = []
        self.state.pc = self._read16(0xFFFE, "reset vector")
        self.last_trace = None

    def service_interrupt(self, source: str) -> bool:
        """Accept an instruction-boundary NMI or external IRQ when permitted."""

        if source not in {"nmi", "irq"}:
            raise ValueError("source must be 'nmi' or 'irq'")
        if source == "irq" and self.flag("I"):
            return False
        self._accesses = []
        if not self.state.waiting:
            self._stack_complete_state()
        self.state.waiting = False
        self.state.sleeping = False
        self.set_flag("I", True)
        vector = 0xFFFC if source == "nmi" else 0xFFF8
        self.state.pc = self._read16(vector, f"{source.upper()} vector")
        self._validate_state()
        return True

    def step(self) -> InstructionTrace:
        if self.state.waiting or self.state.sleeping:
            raise RuntimeError("processor is in a low-power state; service an interrupt or reset")
        before = self.state.snapshot()
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
        operand, effective_address = self._decode_operand(record)
        trace.effective_address = effective_address
        self._execute(record, operand, effective_address)
        self._validate_state()
        trace.state_after = self.state.snapshot()
        trace.accesses = list(self._accesses)
        self.instruction_count += 1
        self.last_trace = trace
        return trace

    def _validate_state(self) -> None:
        self.state.a &= 0xFF
        self.state.b &= 0xFF
        self.state.x &= 0xFFFF
        self.state.sp &= 0xFFFF
        self.state.pc &= 0xFFFF
        self.state.ccr &= 0x3F

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

    def _write16(self, address: int, value: int, purpose: str) -> None:
        self._write8(address, value >> 8, f"{purpose} high")
        self._write8(address + 1, value, f"{purpose} low")

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
        self.state.sp = (self.state.sp - 1) & 0xFFFF

    def _pull8(self, purpose: str) -> int:
        self.state.sp = (self.state.sp + 1) & 0xFFFF
        return self._read8(self.state.sp, purpose)

    def _push_return_pc(self) -> None:
        self._push8(self.state.pc & 0xFF, "return PC low")
        self._push8(self.state.pc >> 8, "return PC high")

    def _pull_pc(self) -> None:
        high = self._pull8("return PC high")
        low = self._pull8("return PC low")
        self.state.pc = (high << 8) | low

    def _decode_operand(self, record: dict) -> tuple[int | None, int | None]:
        mnemonic = record["mnemonic"]
        mode = record["addressing_mode"]
        if mnemonic in {"AIM", "OIM", "EIM", "TIM"}:
            immediate = self._fetch8("immediate mask")
            address_byte = self._fetch8("address modifier")
            address = address_byte if mode == "direct" else (self.state.x + address_byte) & 0xFFFF
            value = self._read8(address, "effective operand")
            return (immediate << 8) | value, address
        if mode in {"inherent", "accumulator-a", "accumulator-b"}:
            return None, None
        if mode == "relative":
            displacement = self._fetch8("relative displacement")
            return displacement - 0x100 if displacement & 0x80 else displacement, None
        if mode == "immediate-8":
            return self._fetch8("immediate operand"), None
        if mode == "immediate-16":
            return self._fetch16("immediate operand"), None
        if mode == "direct":
            address = self._fetch8("direct address")
        elif mode == "indexed-unsigned-8":
            address = (self.state.x + self._fetch8("indexed offset")) & 0xFFFF
        elif mode == "extended":
            address = self._fetch16("extended address")
        else:
            raise AssertionError(f"unsupported M6800 addressing mode {mode}")
        if mnemonic in {"JMP", "JSR"} or mnemonic in WORD_STORES or mnemonic.startswith("STA"):
            return None, address
        root, _ = self._data_operation(mnemonic)
        if root == "CLR":
            return None, address
        if mnemonic in WORD_READS:
            return self._read16(address, "effective operand"), address
        return self._read8(address, "effective operand"), address

    @staticmethod
    def _data_operation(mnemonic: str) -> tuple[str, str | None]:
        if len(mnemonic) >= 2 and mnemonic[-1] in {"A", "B"} and mnemonic[:-1] in DATA_BASES | RMW_BASES:
            return mnemonic[:-1], mnemonic[-1]
        return mnemonic, None

    def _merge_flags(self, result: alu.ALUResult | alu.DAAResult, record: dict) -> None:
        for name in record["flags_affected"]:
            if name not in result.flags:
                raise AssertionError(f"{record['mnemonic']} did not produce documented flag {name}")
            self.set_flag(name, result.flags[name])

    def _accumulator_value(self, name: str) -> int:
        return self.state.a if name == "A" else self.state.b

    def _set_accumulator_value(self, name: str, value: int) -> None:
        if name == "A":
            self.state.a = value & 0xFF
        else:
            self.state.b = value & 0xFF

    def _execute(self, record: dict, operand: int | None, address: int | None) -> None:
        mnemonic = record["mnemonic"]
        root, accumulator = self._data_operation(mnemonic)

        if root in DATA_BASES:
            assert accumulator is not None
            left = self._accumulator_value(accumulator)
            if root == "STA":
                result = alu.and8(left, 0xFF)
                assert address is not None
                self._write8(address, left, "store accumulator")
            elif root in {"ADD", "ADC"}:
                assert operand is not None
                result = alu.add8(left, operand, self.flag("C") if root == "ADC" else 0)
            elif root in {"SUB", "SBC", "CMP"}:
                assert operand is not None
                result = alu.sub8(left, operand, self.flag("C") if root == "SBC" else 0)
            elif root in {"AND", "BIT"}:
                assert operand is not None
                result = alu.and8(left, operand)
            elif root == "EOR":
                assert operand is not None
                result = alu.xor8(left, operand)
            elif root == "ORA":
                assert operand is not None
                result = alu.or8(left, operand)
            elif root == "LDA":
                assert operand is not None
                result = alu.and8(operand, 0xFF)
            else:
                raise AssertionError(root)
            if root not in {"CMP", "BIT", "STA"}:
                self._set_accumulator_value(accumulator, result.value)
            self._merge_flags(result, record)
            return

        if root in RMW_BASES:
            if accumulator is not None:
                value = self._accumulator_value(accumulator)
            else:
                value = 0 if root == "CLR" else operand
                assert value is not None and address is not None
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
            }.get(root)
            if root == "ROR":
                result = alu.ror8(value, self.flag("C"))
            elif root == "ROL":
                result = alu.rol8(value, self.flag("C"))
            else:
                assert operation is not None
                result = operation(value)
            if root != "TST":
                if accumulator is not None:
                    self._set_accumulator_value(accumulator, result.value)
                else:
                    assert address is not None
                    self._write8(address, result.value, "read-modify-write result")
            self._merge_flags(result, record)
            return

        if mnemonic in {"ADDD", "SUBD"}:
            assert operand is not None
            result = alu.add16(self.state.d, operand) if mnemonic == "ADDD" else alu.sub16(self.state.d, operand)
            self.state.d = result.value
            self._merge_flags(result, record)
        elif mnemonic == "CPX":
            assert operand is not None
            self._merge_flags(alu.sub16(self.state.x, operand), record)
        elif mnemonic in {"LDD", "LDX", "LDS"}:
            assert operand is not None
            if mnemonic == "LDD":
                self.state.d = operand
            elif mnemonic == "LDX":
                self.state.x = operand
            else:
                self.state.sp = operand
            result = alu.ALUResult(operand, {"N": bool(operand & 0x8000), "Z": operand == 0, "V": False})
            self._merge_flags(result, record)
        elif mnemonic in {"STD", "STX", "STS"}:
            assert address is not None
            value = {"STD": self.state.d, "STX": self.state.x, "STS": self.state.sp}[mnemonic]
            self._write16(address, value, f"store {mnemonic[2:]}")
            result = alu.ALUResult(value, {"N": bool(value & 0x8000), "Z": value == 0, "V": False})
            self._merge_flags(result, record)
        elif mnemonic in {"AIM", "OIM", "EIM", "TIM"}:
            assert operand is not None and address is not None
            immediate, memory_value = operand >> 8, operand & 0xFF
            if mnemonic in {"AIM", "TIM"}:
                result = alu.and8(memory_value, immediate)
            elif mnemonic == "OIM":
                result = alu.or8(memory_value, immediate)
            else:
                result = alu.xor8(memory_value, immediate)
            if mnemonic != "TIM":
                self._write8(address, result.value, f"{mnemonic} result")
            self._merge_flags(result, record)
        elif mnemonic in {"BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ", "BVC", "BVS", "BPL", "BMI", "BGE", "BLT", "BGT", "BLE"}:
            assert operand is not None
            if self._branch_taken(mnemonic):
                self.state.pc = (self.state.pc + operand) & 0xFFFF
        elif mnemonic == "BSR":
            assert operand is not None
            self._push_return_pc()
            self.state.pc = (self.state.pc + operand) & 0xFFFF
        elif mnemonic == "JMP":
            assert address is not None
            self.state.pc = address
        elif mnemonic == "JSR":
            assert address is not None
            self._push_return_pc()
            self.state.pc = address
        elif mnemonic == "RTS":
            self._pull_pc()
        elif mnemonic == "RTI":
            self.state.ccr = self._pull8("stacked CCR") & 0x3F
            self.state.b = self._pull8("stacked B")
            self.state.a = self._pull8("stacked A")
            high = self._pull8("stacked X high")
            low = self._pull8("stacked X low")
            self.state.x = (high << 8) | low
            self._pull_pc()
        elif mnemonic in {"PSHA", "PSHB"}:
            self._push8(self._accumulator_value(mnemonic[-1]), f"push {mnemonic[-1]}")
        elif mnemonic in {"PULA", "PULB"}:
            self._set_accumulator_value(mnemonic[-1], self._pull8(f"pull {mnemonic[-1]}"))
        elif mnemonic == "PSHX":
            self._push8(self.state.x & 0xFF, "push X low")
            self._push8(self.state.x >> 8, "push X high")
        elif mnemonic == "PULX":
            high = self._pull8("pull X high")
            low = self._pull8("pull X low")
            self.state.x = (high << 8) | low
        elif mnemonic == "SWI":
            self._stack_complete_state()
            self.set_flag("I", True)
            self.state.pc = self._read16(0xFFFA, "SWI vector")
        elif mnemonic == "WAI":
            self._stack_complete_state()
            self.state.waiting = True
        elif mnemonic == "SLP":
            self.state.sleeping = True
        elif mnemonic == "MUL":
            result = alu.mul8(self.state.a, self.state.b)
            self.state.d = result.value
            self._merge_flags(result, record)
        elif mnemonic == "DAA":
            result = alu.daa8(self.state.a, self.flag("H"), self.flag("C"))
            if not result.defined:
                raise UndefinedBehavior("DAA input state is outside the manufacturer table")
            self.state.a = result.value
            self._merge_flags(result, record)
        elif mnemonic in {"LSRD", "ASLD"}:
            if mnemonic == "LSRD":
                carry = bool(self.state.d & 1)
                value = self.state.d >> 1
                result = alu.ALUResult(value, {"N": False, "Z": value == 0, "V": carry, "C": carry})
            else:
                carry = bool(self.state.d & 0x8000)
                value = (self.state.d << 1) & 0xFFFF
                negative = bool(value & 0x8000)
                result = alu.ALUResult(value, {"N": negative, "Z": value == 0, "V": negative ^ carry, "C": carry})
            self.state.d = result.value
            self._merge_flags(result, record)
        elif mnemonic in {"ABA", "SBA", "CBA"}:
            result = alu.add8(self.state.a, self.state.b) if mnemonic == "ABA" else alu.sub8(self.state.a, self.state.b)
            if mnemonic != "CBA":
                self.state.a = result.value
            self._merge_flags(result, record)
        elif mnemonic in {"TAB", "TBA"}:
            value = self.state.a if mnemonic == "TAB" else self.state.b
            if mnemonic == "TAB":
                self.state.b = value
            else:
                self.state.a = value
            self._merge_flags(alu.and8(value, 0xFF), record)
        elif mnemonic == "TAP":
            for name, bit in FLAG_BITS.items():
                self.set_flag(name, bool(self.state.a & (1 << bit)))
        elif mnemonic == "TPA":
            self.state.a = self.packed_ccr()
        elif mnemonic in {"CLC", "SEC", "CLI", "SEI", "CLV", "SEV"}:
            flag = mnemonic[-1]
            self.set_flag(flag, mnemonic.startswith("SE"))
        elif mnemonic in {"INX", "DEX"}:
            self.state.x = (self.state.x + (1 if mnemonic == "INX" else -1)) & 0xFFFF
            self.set_flag("Z", self.state.x == 0)
        elif mnemonic == "ABX":
            self.state.x = (self.state.x + self.state.b) & 0xFFFF
        elif mnemonic == "TSX":
            self.state.x = (self.state.sp + 1) & 0xFFFF
        elif mnemonic == "TXS":
            self.state.sp = (self.state.x - 1) & 0xFFFF
        elif mnemonic == "INS":
            self.state.sp = (self.state.sp + 1) & 0xFFFF
        elif mnemonic == "DES":
            self.state.sp = (self.state.sp - 1) & 0xFFFF
        elif mnemonic == "XGDX":
            old_d = self.state.d
            self.state.d = self.state.x
            self.state.x = old_d
        elif mnemonic == "NOP":
            pass
        else:
            raise AssertionError(f"unimplemented documented instruction {mnemonic}")

    def _stack_complete_state(self) -> None:
        self._push8(self.state.pc & 0xFF, "stacked PC low")
        self._push8(self.state.pc >> 8, "stacked PC high")
        self._push8(self.state.x & 0xFF, "stacked X low")
        self._push8(self.state.x >> 8, "stacked X high")
        self._push8(self.state.a, "stacked A")
        self._push8(self.state.b, "stacked B")
        self._push8(self.packed_ccr(), "stacked CCR")

    def _branch_taken(self, mnemonic: str) -> bool:
        n, z, v, c = (self.flag(name) for name in ("N", "Z", "V", "C"))
        return {
            "BRA": True,
            "BRN": False,
            "BHI": not c and not z,
            "BLS": c or z,
            "BCC": not c,
            "BCS": c,
            "BNE": not z,
            "BEQ": z,
            "BVC": not v,
            "BVS": v,
            "BPL": not n,
            "BMI": n,
            "BGE": n == v,
            "BLT": n != v,
            "BGT": not z and n == v,
            "BLE": z or n != v,
        }[mnemonic]
