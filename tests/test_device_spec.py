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

    def test_v1_claims_have_release_terminal_status(self) -> None:
        devices = {device["id"]: device for device in self.spec["devices"]}
        for device in devices.values():
            self.assertNotIn("PARTIAL", device["status"].values())
            self.assertNotIn("NOT_IMPLEMENTED", device["status"].values())
            for dimension in ("cpu_core", "architectural_tests", "cycle_count_tests"):
                self.assertEqual(device["status"][dimension], "COMPLETE")
        for device_id in ("mc6800", "m6805_cpu", "mc68705p5"):
            self.assertEqual(devices[device_id]["status"]["bus_trace_tests"], "COMPLETE")
        for device_id in (
            "mc6801", "mc6803", "hd6301v1", "hd6303r", "hd63701v0", "hd63705v0"
        ):
            self.assertEqual(
                devices[device_id]["status"]["bus_trace_tests"],
                "UNDEFINED_BY_DOCUMENTATION",
            )
        for device in devices.values():
            if device["implementation_scope"] == "FULL_MCU":
                for dimension in (
                    "device_wrapper", "internal_memory", "gpio", "timer", "low_power"
                ):
                    self.assertIn(
                        device["status"][dimension], {"COMPLETE", "NOT_APPLICABLE"}
                    )

    def test_release_claims_have_committed_implementation_evidence(self) -> None:
        for evidence_path in (
            "rtl/m6800/m6800_core.sv",
            "rtl/m6805/m6805_core.sv",
            "rtl/m6801/mc6801_mcu.sv",
            "rtl/m6801/mc6801_bus_wrapper.sv",
            "rtl/hd6301/hd6303r_bus_wrapper.sv",
            "rtl/hd6301/hd6301v1_bus_wrapper.sv",
            "rtl/hd6301/hd6301v1_mcu.sv",
            "rtl/hd6301/hd6303r_mcu.sv",
            "rtl/hd6301/hd63701v0_mcu.sv",
            "rtl/hd6301/hd63701v0_bus_wrapper.sv",
            "rtl/hd6305/hd63705v0_mcu.sv",
            "sim/tb_mc6801_mcu.sv",
            "sim/tb_hd6301v1_mcu.sv",
            "sim/tb_hd6303r_mcu.sv",
            "sim/tb_hd63701v0_mcu.sv",
            "sim/tb_hd63701v0_prom.sv",
            "sim/tb_hd63705v0_mcu.sv",
            "model/hd6301v1_device.py",
            "model/hd6301v1_bus.py",
            "model/hd63701v0_device.py",
            "model/hd63701v0_bus.py",
            "model/hd63701v0_prom.py",
            "model/hd63705v0_device.py",
            "model/mc68705p5_device.py",
            "model/mc6801_bus.py",
            "model/mc6800_phase.py",
            "model/hd6303r_bus.py",
            "spec/peripherals/mc6801.json",
            "spec/peripherals/mc6803.json",
            "spec/peripherals/hd6301v1.json",
            "spec/peripherals/hd6303r.json",
            "spec/peripherals/hd63701v0.json",
            "spec/peripherals/hd63705v0.json",
            "spec/interfaces/hd6301v1_mode7.json",
            "spec/interfaces/hd6301v1_phased_bus.json",
            "spec/interfaces/hd63701v0_modes.json",
            "spec/interfaces/hd63701v0_phased_bus.json",
            "spec/interfaces/hd63701v0_prom.json",
            "spec/interfaces/hd63705v0_mcu.json",
            "spec/interfaces/mc6801_phased_bus.json",
            "spec/interfaces/mc6800_phased_bus.json",
            "spec/interfaces/hd6303r_phased_bus.json",
            "sim/tb_mc68705p5_peripheral_diff.sv",
            "sim/tb_mc68705p5_mask_timer.sv",
            "sim/tb_hd63705_peripheral_diff.sv",
            "formal/hd63705v0_mcu_formal.sv",
        ):
            self.assertTrue((ROOT / evidence_path).is_file(), evidence_path)

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

    def test_v1_partial_status_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["devices"][0]["status"]["cpu_core"] = "PARTIAL"
        with self.assertRaisesRegex(
            validate_devices.DeviceSpecError, "non-terminal implementation status"
        ):
            validate_devices.validate_devices(broken, self.references)

    def test_unknown_reference_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["devices"][0]["references"][0]["id"] = "not-a-reference"
        with self.assertRaisesRegex(validate_devices.DeviceSpecError, "unknown reference"):
            validate_devices.validate_devices(broken, self.references)


if __name__ == "__main__":
    unittest.main()
