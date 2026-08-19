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

    def test_repository_opcode_directory_is_valid(self) -> None:
        files, documented = validate_opcodes.validate_directory(
            ROOT / "spec" / "opcodes", self.references
        )
        self.assertEqual(files, 2)
        self.assertEqual(documented, 417)
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.m6800["opcodes"]),
            197,
        )
        self.assertEqual(
            sum(record["classification"] == "documented_instruction" for record in self.m6801["opcodes"]),
            220,
        )

    def test_all_values_are_explicitly_classified(self) -> None:
        for spec in (self.m6800, self.m6801):
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
