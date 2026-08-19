from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import unittest

from tools import validate_devices
from tools.fetch_references import load_manifest


ROOT = Path(__file__).resolve().parents[1]


class DeviceSpecificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = validate_devices._load_json(ROOT / "spec" / "devices.yml")
        self.references = load_manifest(ROOT / "docs" / "references.yml")

    def test_repository_device_specification_is_valid(self) -> None:
        validate_devices.validate_devices(self.spec, self.references)

    def test_all_current_v1_support_claims_are_honest(self) -> None:
        for device in self.spec["devices"]:
            if device["release_target"] != "v1":
                continue
            self.assertNotIn("COMPLETE", device["status"].values(), device["id"])
            self.assertNotIn("PARTIAL", device["status"].values(), device["id"])

    def test_unknown_architecture_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["devices"][0]["architecture"] = "invented"
        with self.assertRaisesRegex(validate_devices.DeviceSpecError, "unknown architecture"):
            validate_devices.validate_devices(broken, self.references)

    def test_missing_status_dimension_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        del broken["devices"][0]["status"]["bus_trace_tests"]
        with self.assertRaisesRegex(validate_devices.DeviceSpecError, "status fields"):
            validate_devices.validate_devices(broken, self.references)

    def test_unknown_reference_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["devices"][0]["references"][0]["id"] = "not-a-reference"
        with self.assertRaisesRegex(validate_devices.DeviceSpecError, "unknown reference"):
            validate_devices.validate_devices(broken, self.references)


if __name__ == "__main__":
    unittest.main()
