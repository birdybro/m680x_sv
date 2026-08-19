from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import unittest

from tools.fetch_references import load_manifest
from tools import validate_devices, validate_peripherals


ROOT = Path(__file__).resolve().parents[1]


class PeripheralSpecificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = json.loads((ROOT / "spec/peripherals/mc68705p5.json").read_text())
        self.devices = validate_devices._load_json(ROOT / "spec/devices.yml")
        self.references = load_manifest(ROOT / "docs/references.yml")

    def test_repository_peripheral_specification_is_valid(self) -> None:
        validate_peripherals.validate_peripheral(self.spec, self.devices, self.references)

    def test_overlapping_memory_regions_are_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["memory_regions"][1]["start"] = "00F"
        with self.assertRaisesRegex(validate_peripherals.PeripheralSpecError, "overlap"):
            validate_peripherals.validate_peripheral(broken, self.devices, self.references)

    def test_unknown_reference_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["registers"][0]["reference"]["id"] = "unknown"
        with self.assertRaisesRegex(validate_peripherals.PeripheralSpecError, "invalid reference"):
            validate_peripherals.validate_peripheral(broken, self.devices, self.references)


if __name__ == "__main__":
    unittest.main()
