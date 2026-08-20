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

    def test_complete_claims_are_narrow_and_evidenced(self) -> None:
        complete = {
            (device["id"], dimension)
            for device in self.spec["devices"]
            if device["release_target"] == "v1"
            for dimension, status in device["status"].items()
            if status == "COMPLETE"
        }
        self.assertEqual(complete, {("mc68705p5", "internal_memory")})
        for evidence_path in (
            "model/mc68705p5_device.py",
            "sim/tb_mc68705p5_peripheral_diff.sv",
            "spec/peripherals/mc68705p5.json",
            "spec/interfaces/mc68705p5_mcu.json",
        ):
            self.assertTrue((ROOT / evidence_path).is_file(), evidence_path)

    def test_partial_claims_match_committed_implementation_evidence(self) -> None:
        devices = {device["id"]: device for device in self.spec["devices"]}
        for device in devices.values():
            self.assertEqual(device["status"]["cpu_core"], "PARTIAL")
            self.assertEqual(device["status"]["architectural_tests"], "PARTIAL")
            self.assertEqual(device["status"]["cycle_count_tests"], "PARTIAL")
            self.assertEqual(device["status"]["bus_trace_tests"], "PARTIAL")
        p5 = devices["mc68705p5"]["status"]
        for dimension in ("device_wrapper", "gpio", "timer"):
            self.assertEqual(p5[dimension], "PARTIAL")
        self.assertEqual(p5["internal_memory"], "COMPLETE")
        self.assertEqual(devices["mc6800"]["status"]["device_wrapper"], "PARTIAL")
        mc6801 = devices["mc6801"]["status"]
        for dimension in ("device_wrapper", "internal_memory", "gpio", "timer", "serial"):
            self.assertEqual(mc6801[dimension], "PARTIAL")
        mc6803 = devices["mc6803"]["status"]
        for dimension in ("device_wrapper", "internal_memory", "gpio", "timer", "serial"):
            self.assertEqual(mc6803[dimension], "PARTIAL")
        hd6303r = devices["hd6303r"]["status"]
        for dimension in (
            "device_wrapper", "internal_memory", "gpio", "timer", "serial"
        ):
            self.assertEqual(hd6303r[dimension], "PARTIAL")
        hd6301v1 = devices["hd6301v1"]["status"]
        for dimension in (
            "device_wrapper", "internal_memory", "gpio", "timer", "serial"
        ):
            self.assertEqual(hd6301v1[dimension], "PARTIAL")
        hd63701v0 = devices["hd63701v0"]["status"]
        for dimension in (
            "device_wrapper", "internal_memory", "gpio", "timer", "serial"
        ):
            self.assertEqual(hd63701v0[dimension], "PARTIAL")
        hd63705v0 = devices["hd63705v0"]["status"]
        for dimension in (
            "device_wrapper", "internal_memory", "gpio", "timer", "serial"
        ):
            self.assertEqual(hd63705v0[dimension], "PARTIAL")
        for evidence_path in (
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
        ):
            self.assertTrue((ROOT / evidence_path).is_file(), evidence_path)
        implemented_full_mcus = {
            "mc6801", "mc6803", "mc68705p5", "hd6301v1", "hd6303r",
            "hd63701v0", "hd63705v0",
        }
        for device_id, device in devices.items():
            if (
                device_id not in implemented_full_mcus
                and device["implementation_scope"] == "FULL_MCU"
            ):
                self.assertEqual(device["status"]["device_wrapper"], "NOT_IMPLEMENTED")

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
