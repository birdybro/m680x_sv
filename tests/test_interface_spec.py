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
        self.mc6800_phased_bus_spec = json.loads(
            (ROOT / "spec/interfaces/mc6800_phased_bus.json").read_text()
        )
        self.hd6303r_bus_spec = json.loads(
            (ROOT / "spec/interfaces/hd6303r_phased_bus.json").read_text()
        )
        self.hd6301v1_bus_spec = json.loads(
            (ROOT / "spec/interfaces/hd6301v1_phased_bus.json").read_text()
        )
        self.hd63701v0_bus_spec = json.loads(
            (ROOT / "spec/interfaces/hd63701v0_phased_bus.json").read_text()
        )
        self.hd63701v0_prom_spec = json.loads(
            (ROOT / "spec/interfaces/hd63701v0_prom.json").read_text()
        )
        self.hd63705v0_spec = json.loads(
            (ROOT / "spec/interfaces/hd63705v0_mcu.json").read_text()
        )
        self.mc68705p5_spec = json.loads(
            (ROOT / "spec/interfaces/mc68705p5_mcu.json").read_text()
        )
        self.hd6303r_modes_spec = json.loads(
            (ROOT / "spec/interfaces/hd6303r_modes.json").read_text()
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

    def test_mc6800_phased_bus_requires_both_projected_clocks(self) -> None:
        broken = deepcopy(self.mc6800_phased_bus_spec)
        broken["signals"] = [
            signal for signal in broken["signals"] if signal["name"] != "phi2_o"
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

    def test_hd6301v1_phased_bus_requires_mode7_strobe_input(self) -> None:
        broken = deepcopy(self.hd6301v1_bus_spec)
        broken["signals"] = [
            signal for signal in broken["signals"] if signal["name"] != "sc1_i"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_hd63701v0_phased_bus_requires_port2_reset_projection(self) -> None:
        broken = deepcopy(self.hd63701v0_bus_spec)
        broken["signals"] = [
            signal for signal in broken["signals"]
            if signal["name"] != "port2_oe_o"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_hd63701v0_prom_requires_program_request(self) -> None:
        broken = deepcopy(self.hd63701v0_prom_spec)
        broken["signals"] = [
            signal for signal in broken["signals"]
            if signal["name"] != "prom_program_o"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_hd63705v0_requires_ordinary_read_voltage_qualification(self) -> None:
        broken = deepcopy(self.hd63705v0_spec)
        broken["signals"] = [
            signal for signal in broken["signals"]
            if signal["name"] != "eprom_read_voltage_i"
        ]
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "missing required"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)

    def test_documented_phased_bus_timing_claims_are_complete(self) -> None:
        self.assertEqual(
            self.mc6801_bus_spec["implementation_status"][
                "wai_interrupt_response_latency"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd6303r_bus_spec["implementation_status"][
                "three_cycle_reset_bus_release"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd6301v1_bus_spec["implementation_status"][
                "all_seven_legal_mode_pin_roles"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd6303r_modes_spec["implementation_status"][
                "physical_reset_entry_waveform"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63701v0_bus_spec["implementation_status"][
                "all_six_legal_mode_pin_roles"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63701v0_prom_spec["implementation_status"][
                "table_3_1_digital_states"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63705v0_spec["implementation_status"][
                "eprom_programming_digital_controls"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63705v0_spec["implementation_status"]["single_chip_memory"],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63705v0_spec["implementation_status"]["primary_timer"],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63705v0_spec["implementation_status"]["gpio"],
            "COMPLETE",
        )
        self.assertEqual(
            self.hd63705v0_spec["implementation_status"][
                "synchronous_sci_timer2"
            ],
            "COMPLETE",
        )
        self.assertEqual(
            self.mc68705p5_spec["implementation_status"]["timer_function"],
            "COMPLETE",
        )

    def test_unknown_reference_is_rejected(self) -> None:
        broken = deepcopy(self.spec)
        broken["references"][0]["id"] = "unknown"
        with self.assertRaisesRegex(validate_interfaces.InterfaceSpecError, "invalid interface reference"):
            validate_interfaces.validate_interface(broken, self.devices, self.references)


if __name__ == "__main__":
    unittest.main()
