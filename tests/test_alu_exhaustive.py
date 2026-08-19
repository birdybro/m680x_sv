from __future__ import annotations

import unittest

from model import alu


def _signed8(value: int) -> int:
    return value - 0x100 if value & 0x80 else value


def _signed16(value: int) -> int:
    return value - 0x10000 if value & 0x8000 else value


def _bcd_values() -> list[tuple[int, int]]:
    return [((tens << 4) | units, tens * 10 + units) for tens in range(10) for units in range(10)]


def _daa_manufacturer_table() -> dict[tuple[int, bool, bool], tuple[int, bool]]:
    rows = (
        (0, range(0x0, 0xA), 0, range(0x0, 0xA), 0x00, 0),
        (0, range(0x0, 0x9), 0, range(0xA, 0x10), 0x06, 0),
        (0, range(0x0, 0xA), 1, range(0x0, 0x4), 0x06, 0),
        (0, range(0xA, 0x10), 0, range(0x0, 0xA), 0x60, 1),
        (0, range(0x9, 0x10), 0, range(0xA, 0x10), 0x66, 1),
        (0, range(0xA, 0x10), 1, range(0x0, 0x4), 0x66, 1),
        (1, range(0x0, 0x3), 0, range(0x0, 0xA), 0x60, 1),
        (1, range(0x0, 0x3), 0, range(0xA, 0x10), 0x66, 1),
        (1, range(0x0, 0x4), 1, range(0x0, 0x4), 0x66, 1),
    )
    table: dict[tuple[int, bool, bool], tuple[int, bool]] = {}
    for carry, high_values, half_carry, low_values, adjustment, carry_out in rows:
        for high in high_values:
            for low in low_values:
                state = ((high << 4) | low, bool(half_carry), bool(carry))
                value = (((high << 4) | low) + adjustment) & 0xFF
                previous = table.setdefault(state, (value, bool(carry_out)))
                if previous != (value, bool(carry_out)):
                    raise AssertionError(f"conflicting DAA manufacturer rows for {state}")
    return table


class ExhaustiveALUTests(unittest.TestCase):
    def test_add_adc_all_operands_and_carry_states(self) -> None:
        for carry in (0, 1):
            for left in range(0x100):
                signed_left = _signed8(left)
                for right in range(0x100):
                    total = left + right + carry
                    value = total & 0xFF
                    signed_total = signed_left + _signed8(right) + carry
                    expected = {
                        "H": (left & 0x0F) + (right & 0x0F) + carry >= 0x10,
                        "N": value >= 0x80,
                        "Z": value == 0,
                        "V": not -128 <= signed_total <= 127,
                        "C": total >= 0x100,
                    }
                    actual = alu.add8(left, right, carry)
                    if actual.value != value or actual.flags != expected:
                        self.fail(
                            f"ADD8 mismatch left={left:02X} right={right:02X} "
                            f"carry={carry}: actual={actual}, expected={value:02X}/{expected}"
                        )

    def test_sub_sbc_cmp_all_operands_and_borrow_states(self) -> None:
        for borrow in (0, 1):
            for left in range(0x100):
                signed_left = _signed8(left)
                for right in range(0x100):
                    difference = left - right - borrow
                    value = difference & 0xFF
                    signed_difference = signed_left - _signed8(right) - borrow
                    expected = {
                        "N": value >= 0x80,
                        "Z": value == 0,
                        "V": not -128 <= signed_difference <= 127,
                        "C": difference < 0,
                    }
                    actual = alu.sub8(left, right, borrow)
                    if actual.value != value or actual.flags != expected:
                        self.fail(
                            f"SUB8 mismatch left={left:02X} right={right:02X} "
                            f"borrow={borrow}: actual={actual}, expected={value:02X}/{expected}"
                        )

    def test_and_or_xor_all_operand_pairs(self) -> None:
        operations = (
            ("AND", alu.and8, lambda left, right: left & right),
            ("OR", alu.or8, lambda left, right: left | right),
            ("XOR", alu.xor8, lambda left, right: left ^ right),
        )
        for name, operation, oracle in operations:
            for left in range(0x100):
                for right in range(0x100):
                    value = oracle(left, right)
                    expected = {"N": value >= 0x80, "Z": value == 0, "V": False}
                    actual = operation(left, right)
                    if actual.value != value or actual.flags != expected:
                        self.fail(
                            f"{name} mismatch left={left:02X} right={right:02X}: "
                            f"actual={actual}, expected={value:02X}/{expected}"
                        )

    def test_unary_shift_and_rotate_all_values(self) -> None:
        for operand in range(0x100):
            unary_expected = {
                alu.neg8: (
                    (-operand) & 0xFF,
                    {
                        "N": bool(((-operand) & 0xFF) & 0x80),
                        "Z": operand == 0,
                        "V": operand == 0x80,
                        "C": operand != 0,
                    },
                ),
                alu.com8: (
                    operand ^ 0xFF,
                    {
                        "N": not bool(operand & 0x80),
                        "Z": operand == 0xFF,
                        "V": False,
                        "C": True,
                    },
                ),
                alu.inc8: (
                    (operand + 1) & 0xFF,
                    {
                        "N": bool(((operand + 1) & 0xFF) & 0x80),
                        "Z": operand == 0xFF,
                        "V": operand == 0x7F,
                    },
                ),
                alu.dec8: (
                    (operand - 1) & 0xFF,
                    {
                        "N": bool(((operand - 1) & 0xFF) & 0x80),
                        "Z": operand == 0x01,
                        "V": operand == 0x80,
                    },
                ),
                alu.tst8: (
                    operand,
                    {"N": bool(operand & 0x80), "Z": operand == 0, "V": False, "C": False},
                ),
            }
            for operation, (value, flags) in unary_expected.items():
                actual = operation(operand)
                if actual.value != value or actual.flags != flags:
                    self.fail(
                        f"{operation.__name__} mismatch operand={operand:02X}: "
                        f"actual={actual}, expected={value:02X}/{flags}"
                    )

            lsr_value = operand >> 1
            lsr_carry = bool(operand & 1)
            lsr_expected = {
                "N": False,
                "Z": lsr_value == 0,
                "V": lsr_carry,
                "C": lsr_carry,
            }
            self.assertEqual(alu.lsr8(operand), alu.ALUResult(lsr_value, lsr_expected))

            asr_value = (operand >> 1) | (operand & 0x80)
            asr_negative = bool(asr_value & 0x80)
            asr_expected = {
                "N": asr_negative,
                "Z": asr_value == 0,
                "V": asr_negative ^ lsr_carry,
                "C": lsr_carry,
            }
            self.assertEqual(alu.asr8(operand), alu.ALUResult(asr_value, asr_expected))

            asl_value = (operand * 2) & 0xFF
            asl_carry = operand >= 0x80
            asl_negative = bool(asl_value & 0x80)
            asl_expected = {
                "N": asl_negative,
                "Z": asl_value == 0,
                "V": asl_negative ^ asl_carry,
                "C": asl_carry,
            }
            self.assertEqual(alu.asl8(operand), alu.ALUResult(asl_value, asl_expected))

            for carry in (0, 1):
                ror_value = (operand >> 1) | (carry << 7)
                ror_carry = bool(operand & 1)
                ror_negative = bool(ror_value & 0x80)
                self.assertEqual(
                    alu.ror8(operand, carry),
                    alu.ALUResult(
                        ror_value,
                        {
                            "N": ror_negative,
                            "Z": ror_value == 0,
                            "V": ror_negative ^ ror_carry,
                            "C": ror_carry,
                        },
                    ),
                )
                rol_value = ((operand * 2) + carry) & 0xFF
                rol_carry = operand >= 0x80
                rol_negative = bool(rol_value & 0x80)
                self.assertEqual(
                    alu.rol8(operand, carry),
                    alu.ALUResult(
                        rol_value,
                        {
                            "N": rol_negative,
                            "Z": rol_value == 0,
                            "V": rol_negative ^ rol_carry,
                            "C": rol_carry,
                        },
                    ),
                )

        self.assertEqual(
            alu.clr8(),
            alu.ALUResult(0, {"N": False, "Z": True, "V": False, "C": False}),
        )

    def test_mul_all_operand_pairs(self) -> None:
        for left in range(0x100):
            for right in range(0x100):
                product = left * right
                actual = alu.mul8(left, right)
                expected = alu.ALUResult(product, {"C": bool(product & 0x80)})
                if actual != expected:
                    self.fail(
                        f"MUL mismatch left={left:02X} right={right:02X}: "
                        f"actual={actual}, expected={expected}"
                    )

    def test_daa_all_documented_bcd_addition_states(self) -> None:
        expected_by_state = _daa_manufacturer_table()
        values = _bcd_values()
        for left_bcd, left_decimal in values:
            for right_bcd, right_decimal in values:
                for carry_in in (0, 1):
                    binary = alu.add8(left_bcd, right_bcd, carry_in)
                    state = (binary.value, binary.flags["H"], binary.flags["C"])
                    decimal_total = left_decimal + right_decimal + carry_in
                    packed = ((decimal_total % 100) // 10 << 4) | (decimal_total % 10)
                    expected = (packed, decimal_total >= 100)
                    self.assertIn(state, expected_by_state)
                    self.assertEqual(expected_by_state[state], expected)

        for accumulator in range(0x100):
            for half_carry in (False, True):
                for carry in (False, True):
                    state = (accumulator, half_carry, carry)
                    actual = alu.daa8(accumulator, half_carry, carry)
                    if state not in expected_by_state:
                        self.assertFalse(actual.defined, f"unexpectedly defined DAA state {state}")
                        continue
                    expected_value, expected_carry = expected_by_state[state]
                    self.assertTrue(actual.defined, f"missing documented DAA state {state}")
                    self.assertEqual(actual.value, expected_value)
                    self.assertEqual(actual.flags["C"], expected_carry)
                    self.assertEqual(actual.flags["N"], bool(expected_value & 0x80))
                    self.assertEqual(actual.flags["Z"], expected_value == 0)

    def test_16_bit_arithmetic_all_left_values_against_boundaries(self) -> None:
        boundaries = (0x0000, 0x0001, 0x007F, 0x0080, 0x00FF, 0x0100, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF)
        for left in range(0x10000):
            for right in boundaries:
                total = left + right
                add_value = total & 0xFFFF
                add_signed = _signed16(left) + _signed16(right)
                self.assertEqual(
                    alu.add16(left, right),
                    alu.ALUResult(
                        add_value,
                        {
                            "N": bool(add_value & 0x8000),
                            "Z": add_value == 0,
                            "V": not -32768 <= add_signed <= 32767,
                            "C": total >= 0x10000,
                        },
                    ),
                )
                difference = left - right
                sub_value = difference & 0xFFFF
                sub_signed = _signed16(left) - _signed16(right)
                self.assertEqual(
                    alu.sub16(left, right),
                    alu.ALUResult(
                        sub_value,
                        {
                            "N": bool(sub_value & 0x8000),
                            "Z": sub_value == 0,
                            "V": not -32768 <= sub_signed <= 32767,
                            "C": difference < 0,
                        },
                    ),
                )

    def test_rejects_out_of_range_inputs(self) -> None:
        for call in (
            lambda: alu.add8(-1, 0),
            lambda: alu.add8(0, 0x100),
            lambda: alu.sub8(0, 0, 2),
            lambda: alu.add16(0x10000, 0),
            lambda: alu.rol8(0, -1),
            lambda: alu.daa8(0, 2, 0),
        ):
            with self.assertRaises(ValueError):
                call()


if __name__ == "__main__":
    unittest.main()
