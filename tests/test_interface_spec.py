from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import unittest

from tools.fetch_references import load_manifest
from tools import validate_devices, validate_interfaces


ROOT = Path(__file__).resolve().parents[1]


class InterfaceSpecificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = json.loads((ROOT / "spec/interfaces/mc6800_bus.json").read_text())
        self.mc6801_bus_spec = json.loads(
            (ROOT / "spec/interfaces/mc6801_phased_bus.json").read_text()
        )
        self.hd6303r_bus_spec = json.loads(
            (ROOT / "spec/interfaces/hd6303r_phased_bus.json").read_text()
        )
        self.devices = validate_devices._load_json(ROOT / "spec/devices.yml")
        self.references = load_manifest(ROOT / "docs/references.yml")

    def test_repository_interface_specification_is_valid(self) -> None:
        validate_interfaces.validate_interface(self.spec, self.devices, self.references)

    def test_duplicate_signal_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["signals"][1]["name"] = broken["signals"][0]["name"]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "duplicate signal"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_missing_required_signal_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["signals"] = [
            signal for signal in broken["signals"] if signal["name"] != "vma_o"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_mc6801_phased_bus_requires_every_pin_role(self) -> None:
        broken = deepcopy(self.mc6801_bus_spec)
        broken["signals"] = [
            signal for signal in broken["signals"] if signal["name"] != "e_o"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_hd6303r_phased_bus_requires_standby_state(self) -> None:
        broken = deepcopy(self.hd6303r_bus_spec)
        broken["signals"] = [
            signal
            for signal in broken["signals"]
            if signal["name"] != "standby_active_o"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_unknown_reference_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["references"][0]["id"] = "unknown"
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "invalid interface reference"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)


if __name__ == "__main__":
    unittest.main()
