from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import unittest

from tools import validate_opcodes
from tools.fetch_references import load_manifest


ROOT = Path(__file__).resolve().parents[1]


class OpcodeSpecificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.references = load_manifest(ROOT / "docs" / "references.yml")
        cls.known_references = {item["id"] for item in cls.references["references"]}
        cls.m6800 = validate_opcodes.load_opcode_spec(ROOT / "spec" / "opcodes" / "m6800.json")
        cls.m6801 = validate_opcodes.load_opcode_spec(ROOT / "spec" / "opcodes" / "m6801.json")
        cls.m6805 = validate_opcodes.load_opcode_spec(ROOT / "spec" / "opcodes" / "m6805.json")
        cls.hd6305 = validate_opcodes.load_opcode_spec(ROOT / "spec" / "opcodes" / "hd6305.json")

    def test_repository_opcode_directory_is_valid(self) -> None:
        files, documented = validate_opcodes.validate_directory(
            ROOT / "spec" / "opcodes", self.references
        )
        self.assertEqual(files, 4)
        self.assertEqual(documented, 834)
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.m6800["opcodes"]),
            197,
        )
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.m6801["opcodes"]),
            220,
        )
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.m6805["opcodes"]),
            207,
        )
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.hd6305["opcodes"]),
            210,
        )

    def test_all_values_are_explicitly_classified(self) -> None:
        for spec in (self.m6800, self.m6801, self.m6805, self.hd6305):
            self.assertEqual([record["opcode"] for record in spec["opcodes"]], list(range(256)))
            self.assertTrue(all(record["classification"] for record in spec["opcodes"]))

    def test_architectural_differences_are_preserved(self) -> None:
        self.assertEqual(self.m6800["opcodes"][0x21]["classification"], "undefined_behavior")
        self.assertEqual(self.m6801["opcodes"][0x21]["mnemonic"], "BRN")
        self.assertEqual(self.m6800["opcodes"][0x9D]["classification"], "undefined_behavior")
        self.assertEqual(self.m6801["opcodes"][0x9D]["mnemonic"], "JSR")
        self.assertEqual(self.m6800["opcodes"][0x20]["cycles"], 4)
        self.assertEqual(self.m6801["opcodes"][0x20]["cycles"], 3)
        self.assertNotIn("C", self.m6800["opcodes"][0x8C]["flags_affected"])
        self.assertIn("C", self.m6801["opcodes"][0x8C]["flags_affected"])
        self.assertEqual(self.m6805["opcodes"][0x8D]["classification"], "undefined_behavior")
        self.assertEqual(self.hd6305["opcodes"][0x8D]["mnemonic"], "DAA")
        self.assertEqual(self.m6805["opcodes"][0x8E]["classification"], "undefined_behavior")
        self.assertEqual(self.hd6305["opcodes"][0x8E]["mnemonic"], "STOP")
        self.assertEqual(self.m6805["opcodes"][0x20]["cycles"], 4)
        self.assertEqual(self.hd6305["opcodes"][0x20]["cycles"], 3)

    def test_m6805_bit_test_and_clear_flag_facts(self) -> None:
        for opcode in range(0x10):
            self.assertEqual(self.m6805["opcodes"][opcode]["flags_affected"], ["C"])
            self.assertEqual(
                self.m6805["opcodes"][opcode]["flag_semantics"]["C"],
                "copy of the tested memory bit",
            )
        for spec in (self.m6805, self.hd6305):
            for opcode in (0x3F, 0x4F, 0x5F, 0x6F, 0x7F):
                self.assertEqual(spec["opcodes"][opcode]["flags_affected"], ["N", "Z"])
                self.assertNotIn("C", spec["opcodes"][opcode]["flags_affected"])

    def test_hd6305_cycle_adjustments_match_operation_map(self) -> None:
        expected = {
            0x3D: 4,
            0x6D: 5,
            0x7D: 4,
            0x80: 8,
            0x81: 5,
            0x83: 10,
            0x8D: 2,
            0x8E: 4,
            0x8F: 4,
            0xAD: 5,
            0xB7: 4,
            0xBC: 2,
            0xBD: 5,
            0xDC: 4,
            0xDD: 6,
            0xFC: 2,
            0xFD: 5,
        }
        self.assertEqual(
            {opcode: self.hd6305["opcodes"][opcode]["cycles"] for opcode in expected},
            expected,
        )

    def test_daa_records_manufacturer_undefined_overflow(self) -> None:
        for spec in (self.m6800, self.m6801):
            daa = spec["opcodes"][0x19]
            self.assertEqual(daa["flags_undefined"], ["V"])
            self.assertIn("H", daa["flags_read"])
            self.assertIn("C", daa["flags_read"])
            self.assertIn("A", daa["registers_read"])
            self.assertIn("A", daa["registers_written"])

    def test_clear_does_not_claim_an_architectural_destination_read(self) -> None:
        clra = self.m6800["opcodes"][0x4F]
        clear_extended = self.m6800["opcodes"][0x7F]
        self.assertNotIn("A", clra["registers_read"])
        self.assertIn("A", clra["registers_written"])
        self.assertNotIn("read effective-address byte", clear_extended["memory_operations"])
        self.assertIn("write zero to effective-address byte", clear_extended["memory_operations"])

    def test_wait_and_rti_register_directions_match_stacking(self) -> None:
        wai = self.m6800["opcodes"][0x3E]
        rti = self.m6800["opcodes"][0x3B]
        self.assertIn("CCR", wai["registers_read"])
        self.assertNotIn("CCR", wai["registers_written"])
        self.assertNotIn("CCR", rti["registers_read"])
        self.assertIn("CCR", rti["registers_written"])

    def test_duplicate_opcode_is_rejected(self) -> None:
        broken = deepcopy(self.m6800)
        broken["opcodes"][1]["opcode"] = 0
        broken["opcodes"][1]["opcode_hex"] = "00"
        with self.assertRaisesRegex(validate_opcodes.OpcodeSpecError, "duplicate opcode"):
            validate_opcodes.validate_opcode_spec(broken, self.known_references)

    def test_missing_cycles_are_rejected(self) -> None:
        broken = deepcopy(self.m6801)
        broken["opcodes"][0x01]["cycles"] = None
        with self.assertRaisesRegex(validate_opcodes.OpcodeSpecError, "missing cycles"):
            validate_opcodes.validate_opcode_spec(broken, self.known_references)


if __name__ == "__main__":
    unittest.main()
