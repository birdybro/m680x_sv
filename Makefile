PYTHON ?= python3
VERILATOR ?= verilator
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yowasp-yosys

.PHONY: help refs refs-check spec-build spec-check lint lint-rtl test test-model test-m6800 test-m6800-rtl test-m6800-opcodes test-wai-bus test-mc6801-wai-response test-mc6800-wrapper test-mc6800-phased-wrapper test-m6801 test-m6801-opcodes test-mc6801-mcu test-mc6801-modes test-mc6801-bus-wrapper test-mc6801-sci-external test-mc6801-sci-biphase test-mc6801-peripheral-diff test-mc6803 test-m6805 test-m6805-rtl test-m6805-opcodes test-hitachi test-hd6301-opcodes test-hd6301-trap test-hd6301v1 test-hd6301v1-modes test-hd6303r test-hd6303r-modes test-hd6303r-bus-wrapper test-hd63701v0 test-hd63701v0-modes test-hd6305-opcodes test-hd63705v0 test-hd63705-peripheral-diff test-alu test-alu-rtl test-cycle test-interrupts test-interrupt-delay test-peripherals test-mc68705p5 test-mc68705p5-peripheral-diff test-random test-random-m6800 test-random-m6801 test-random-hd6301 test-random-m6805 test-random-hd6305 test-iverilog formal synth quick ci clean
.PHONY: test-hd6301v1-bus-wrapper test-hd63701v0-bus-wrapper

help:
	@echo "m680x_sv developer targets"
	@echo "  refs        download/verify ignored primary-reference cache"
	@echo "  refs-check  validate reference metadata without network access"
	@echo "  spec-check  validate architecture and device specifications"
	@echo "  spec-build  regenerate expanded opcode specification artifacts"
	@echo "  lint        run source and policy consistency checks"
	@echo "  lint-rtl    run strict warning-free RTL lint"
	@echo "  test        run current automated tests"
	@echo "  test-model  run both independent architectural model paths"
	@echo "  test-m6800  run M6800-lineage model regressions"
	@echo "  test-m6800-rtl run the compiled M6800 core regression"
	@echo "  test-m6800-opcodes compare all documented M6800 encodings to the model"
	@echo "  test-wai-bus verify variant-specific M6800/MC6801/HD6301 WAI buses"
	@echo "  test-mc6801-wai-response verify exact five/six-cycle WAI wake traces"
	@echo "  test-mc6800-wrapper verify HALT, TSC, DBE, WAI, and bus ownership"
	@echo "  test-mc6800-phased-wrapper verify phi1/phi2 digital bus subphases"
	@echo "  test-m6801  run MC6801/MC6803 model regressions"
	@echo "  test-m6801-opcodes compare all documented MC6801 encodings to the model"
	@echo "  test-mc6801-mcu verify Mode 2/3 RAM, GPIO, timer, SCI, and interrupts"
	@echo "  test-mc6801-modes verify Mode 0-7/1R/6R decode, vectors, RAM, ROM, and ports"
	@echo "  test-mc6801-bus-wrapper verify the four-subphase E/AS/IOS physical bus"
	@echo "  test-mc6801-sci-external verify P22-clocked NRZ transmit and receive"
	@echo "  test-mc6801-sci-biphase verify transition-coded transmit and receive"
	@echo "  test-mc6801-peripheral-diff compare 1,536 model/RTL E-cycles"
	@echo "  test-hd6303r-bus-wrapper verify Mode-1 and Mode-2/4 physical buses"
	@echo "  test-mc6803 verify the inherited MC6801 Mode 2/3 device profile"
	@echo "  test-m6805  run M6805-lineage model regressions"
	@echo "  test-m6805-rtl run directed and exhaustive M6805 RTL regressions"
	@echo "  test-m6805-opcodes compare all documented M6805 encodings to the model"
	@echo "  test-hitachi run HD6301/HD6305 model regressions"
	@echo "  test-hd6301-opcodes compare all documented HD6301 encodings to the model"
	@echo "  test-hd6301-trap verify opcode/address TRAP retry and exact entry trace"
	@echo "  test-hd6301v1 verify all legal HD6301V1 Mode-0/1/2/4/5/6/7 profiles"
	@echo "  test-hd6301v1-bus-wrapper verify all legal HD6301V1 pin waveforms"
	@echo "  test-hd6303r verify all legal ROMless HD6303R Mode-1/2/4 profiles"
	@echo "  test-hd63701v0 verify all legal HD63701V0 Mode-0/1/2/5/6/7 profiles"
	@echo "  test-hd63701v0-bus-wrapper verify all legal HD63701V0 pin waveforms"
	@echo "  test-hd6305-opcodes compare all documented HD6305 encodings to the model"
	@echo "  test-hd63705v0 verify HD63705V0 memory, GPIO, timer, SCI, interrupts, and modes"
	@echo "  test-hd63705-peripheral-diff compare 768 independent model/RTL E-cycles"
	@echo "  test-alu    run Python and RTL exhaustive practical ALU spaces"
	@echo "  test-alu-rtl run the compiled SystemVerilog ALU regression"
	@echo "  test-cycle  verify documented instruction cycles and semantic bus accesses"
	@echo "  test-interrupts run reset, IRQ, NMI, SWI, WAI, and RTI regressions"
	@echo "  test-interrupt-delay verify documented CLI/TAP interrupt boundaries"
	@echo "  test-peripherals run every implemented MCU peripheral profile"
	@echo "  test-mc68705p5 run MC68705P5 memory, GPIO, timer, interrupt, and programming tests"
	@echo "  test-mc68705p5-peripheral-diff compare 768 independent model/RTL cycles"
	@echo "  test-random run 5,120 deterministic model/RTL retirement comparisons"
	@echo "  test-iverilog run both directed core suites with the secondary simulator"
	@echo "  formal      prove bounded core safety and stall invariants with Yosys"
	@echo "  synth       synthesize every CPU architecture and record generic statistics"
	@echo "  quick       run the fast local gate"
	@echo "  ci          run the authoritative committed-source gate"
	@echo "  clean       remove generated local build products"

refs:
	$(PYTHON) -m tools.fetch_references

refs-check:
	$(PYTHON) -m tools.fetch_references --manifest-only

spec-build:
	$(PYTHON) -m tools.build_opcode_specs
	$(PYTHON) -m tools.build_rtl_decode
	$(PYTHON) -m tools.build_m6800_rtl_vectors
	$(PYTHON) -m tools.build_m6805_rtl_vectors
	$(PYTHON) -m tools.build_random_programs
	$(PYTHON) -m tools.build_mc6801_peripheral_vectors
	$(PYTHON) -m tools.build_mc68705p5_peripheral_vectors
	$(PYTHON) -m tools.build_hd63705_peripheral_vectors
	$(PYTHON) -m tools.build_yosys_sources

spec-check: refs-check
	$(PYTHON) -m tools.validate_devices
	$(PYTHON) -m tools.validate_peripherals
	$(PYTHON) -m tools.validate_interfaces
	$(PYTHON) -m tools.build_opcode_specs --check
	$(PYTHON) -m tools.validate_opcodes
	$(PYTHON) -m tools.build_rtl_decode --check
	$(PYTHON) -m tools.build_m6800_rtl_vectors --check
	$(PYTHON) -m tools.build_m6805_rtl_vectors --check
	$(PYTHON) -m tools.build_random_programs --check
	$(PYTHON) -m tools.build_mc6801_peripheral_vectors --check
	$(PYTHON) -m tools.build_mc68705p5_peripheral_vectors --check
	$(PYTHON) -m tools.build_hd63705_peripheral_vectors --check
	$(PYTHON) -m tools.build_yosys_sources --check

lint: spec-check lint-rtl
	$(PYTHON) -m compileall -q model tools tests
	git diff --check

lint-rtl:
	$(VERILATOR) --lint-only --assert -Wall --top-module m6800_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module mc6800_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module mc6800_phased_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv \
		rtl/m6800/mc6800_phased_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module m6800_core "-GARCHITECTURE=2'b01" \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module mc6801_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module mc6801_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/m6801/mc6801_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module m6800_core "-GARCHITECTURE=2'b10" \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd6303r_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd6303r_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv rtl/hd6301/hd6303r_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd6301v1_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd6301v1_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv rtl/hd6301/hd6301v1_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd63701v0_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd63701v0_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv rtl/hd6301/hd63701v0_bus_wrapper.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module m6805_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module m6805_core "-GHITACHI_PROFILE=1'b1" \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module mc68705p5_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module hd63705v0_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv rtl/hd6305/hd63705v0_mcu.sv

test:
	$(PYTHON) -m unittest discover -s tests -v

test-model:
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_m6805_model \
		tests.test_mc6801_device_model tests.test_mc6801_bus_model \
		tests.test_mc6800_phase_model \
		tests.test_hd6301v1_device_model tests.test_hd6301v1_bus_model \
		tests.test_hd6303r_device_model tests.test_hd6303r_bus_model \
		tests.test_hd63701v0_device_model tests.test_hd63701v0_bus_model \
		tests.test_mc68705p5_device_model tests.test_hd63705v0_device_model -v

test-m6800: test-m6800-rtl test-mc6800-wrapper test-mc6800-phased-wrapper
	$(PYTHON) -m unittest tests.test_m6800_model -v

test-m6800-rtl: test-m6800-opcodes
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_core \
		-Mdir build/obj_m6800_core -o Vtb_m6800_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_m6800_core.sv
	build/obj_m6800_core/Vtb_m6800_core

test-wai-bus:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_wait_bus \
		"-GTEST_ARCHITECTURE=2'b00" -Mdir build/obj_wait_bus_m6800 \
		-o Vwait_bus_m6800 rtl/common/m680x_alu_pkg.sv \
		rtl/generated/m680x_decode_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_wait_bus.sv
	build/obj_wait_bus_m6800/Vwait_bus_m6800
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_wait_bus \
		"-GTEST_ARCHITECTURE=2'b01" -Mdir build/obj_wait_bus_m6801 \
		-o Vwait_bus_m6801 rtl/common/m680x_alu_pkg.sv \
		rtl/generated/m680x_decode_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_wait_bus.sv
	build/obj_wait_bus_m6801/Vwait_bus_m6801
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_wait_bus \
		"-GTEST_ARCHITECTURE=2'b10" -Mdir build/obj_wait_bus_hd6301 \
		-o Vwait_bus_hd6301 rtl/common/m680x_alu_pkg.sv \
		rtl/generated/m680x_decode_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_wait_bus.sv
	build/obj_wait_bus_hd6301/Vwait_bus_hd6301

test-mc6801-wai-response:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc6801_wai_response \
		-Mdir build/obj_mc6801_wai_response -o Vtb_mc6801_wai_response \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_mc6801_wai_response.sv
	build/obj_mc6801_wai_response/Vtb_mc6801_wai_response

test-m6800-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_opcodes \
		-Mdir build/obj_m6800_opcodes -o Vtb_m6800_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6800_opcode_vectors_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_opcodes.sv
	build/obj_m6800_opcodes/Vtb_m6800_opcodes

test-mc6800-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6800_bus_wrapper \
		-Mdir build/obj_mc6800_bus_wrapper -o Vtb_mc6800_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv \
		sim/tb_mc6800_bus_wrapper.sv
	build/obj_mc6800_bus_wrapper/Vtb_mc6800_bus_wrapper

test-mc6800-phased-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc6800_phased_bus_wrapper \
		-Mdir build/obj_mc6800_phased_bus_wrapper \
		-o Vtb_mc6800_phased_bus_wrapper \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv \
		rtl/m6800/mc6800_phased_bus_wrapper.sv \
		sim/tb_mc6800_phased_bus_wrapper.sv
	build/obj_mc6800_phased_bus_wrapper/Vtb_mc6800_phased_bus_wrapper
	$(PYTHON) -m unittest tests.test_mc6800_phase_model -v

test-m6801: test-m6801-opcodes test-mc6801-mcu test-mc6801-modes test-mc6801-bus-wrapper test-mc6801-sci-external test-mc6801-sci-biphase
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_mc6801_device_model tests.test_mc6801_bus_model -v

test-m6801-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_opcodes \
		"-GTEST_ARCHITECTURE=2'b01" -Mdir build/obj_m6801_opcodes -o Vtb_m6801_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6800_opcode_vectors_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_opcodes.sv
	build/obj_m6801_opcodes/Vtb_m6801_opcodes

test-mc6801-mcu:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_mcu \
		-Mdir build/obj_mc6801_mcu -o Vtb_mc6801_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_mcu.sv
	build/obj_mc6801_mcu/Vtb_mc6801_mcu
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_mcu \
		"-GTEST_MODE=3'd3" -Mdir build/obj_mc6801_mcu_mode3 -o Vtb_mc6801_mcu_mode3 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_mcu.sv
	build/obj_mc6801_mcu_mode3/Vtb_mc6801_mcu_mode3

test-mc6801-modes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_modes \
		-Mdir build/obj_mc6801_modes -o Vtb_mc6801_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_modes.sv
	build/obj_mc6801_modes/Vtb_mc6801_modes
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_boot_modes \
		-Mdir build/obj_mc6801_boot_modes -o Vtb_mc6801_boot_modes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		sim/tb_mc6801_boot_modes.sv
	build/obj_mc6801_boot_modes/Vtb_mc6801_boot_modes

test-mc6801-bus-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc6801_bus_wrapper \
		-Mdir build/obj_mc6801_bus_wrapper -o Vtb_mc6801_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/m6801/mc6801_bus_wrapper.sv \
		sim/tb_mc6801_bus_wrapper.sv
	build/obj_mc6801_bus_wrapper/Vtb_mc6801_bus_wrapper
	$(PYTHON) -m unittest tests.test_mc6801_bus_model -v

test-mc6801-sci-external:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc6801_sci_external \
		-Mdir build/obj_mc6801_sci_external -o Vtb_mc6801_sci_external \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_sci_external.sv
	build/obj_mc6801_sci_external/Vtb_mc6801_sci_external

test-mc6801-sci-biphase:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc6801_sci_biphase \
		-Mdir build/obj_mc6801_sci_biphase -o Vtb_mc6801_sci_biphase \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_sci_biphase.sv
	build/obj_mc6801_sci_biphase/Vtb_mc6801_sci_biphase

test-mc6803: test-mc6801-mcu test-mc6801-bus-wrapper
	$(PYTHON) -m unittest tests.test_peripheral_spec tests.test_mc6801_device_model \
		tests.test_mc6801_bus_model -v

test-mc6801-peripheral-diff:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_peripheral_diff \
		-Mdir build/obj_mc6801_peripheral_diff -o Vtb_mc6801_peripheral_diff \
		sim/generated/mc6801_peripheral_vectors_pkg.sv \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_peripheral_diff.sv
	build/obj_mc6801_peripheral_diff/Vtb_mc6801_peripheral_diff
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc6801_peripheral_diff \
		"-GTEST_MODE=3'd3" -Mdir build/obj_mc6801_peripheral_diff_mode3 \
		-o Vtb_mc6801_peripheral_diff_mode3 \
		sim/generated/mc6801_peripheral_vectors_pkg.sv \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_peripheral_diff.sv
	build/obj_mc6801_peripheral_diff_mode3/Vtb_mc6801_peripheral_diff_mode3

test-m6805: test-m6805-rtl
	$(PYTHON) -m unittest tests.test_m6805_model -v

test-m6805-rtl: test-m6805-opcodes
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6805_core \
		-Mdir build/obj_m6805_core -o Vtb_m6805_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv sim/tb_m6805_core.sv
	build/obj_m6805_core/Vtb_m6805_core

test-m6805-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6805_opcodes \
		-Mdir build/obj_m6805_opcodes -o Vtb_m6805_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6805_opcode_vectors_pkg.sv rtl/m6805/m6805_core.sv \
		sim/tb_m6805_opcodes.sv
	build/obj_m6805_opcodes/Vtb_m6805_opcodes

test-hitachi: test-hd6301-opcodes test-hd6301v1 test-hd6303r test-hd63701v0 test-hd6305-opcodes test-hd63705v0
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_m6805_model \
		tests.test_hd6301v1_device_model tests.test_hd6301v1_bus_model \
		tests.test_hd6303r_bus_model \
		tests.test_hd63701v0_device_model tests.test_hd63701v0_bus_model \
		tests.test_hd63705v0_device_model -v

test-hd6301-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_opcodes \
		"-GTEST_ARCHITECTURE=2'b10" -Mdir build/obj_hd6301_opcodes -o Vtb_hd6301_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6800_opcode_vectors_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_opcodes.sv
	build/obj_hd6301_opcodes/Vtb_hd6301_opcodes

test-hd6301-trap:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6301_trap \
		-Mdir build/obj_hd6301_trap -o Vtb_hd6301_trap \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_hd6301_trap.sv
	build/obj_hd6301_trap/Vtb_hd6301_trap

test-hd6301v1: test-hd6301v1-modes test-hd6301v1-bus-wrapper
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6301v1_mcu \
		-Mdir build/obj_hd6301v1_mcu -o Vtb_hd6301v1_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv sim/tb_hd6301v1_mcu.sv
	build/obj_hd6301v1_mcu/Vtb_hd6301v1_mcu
	$(PYTHON) -m unittest tests.test_hd6301v1_device_model -v

test-hd6301v1-modes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6301v1_modes \
		-Mdir build/obj_hd6301v1_modes -o Vtb_hd6301v1_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6301v1_mcu.sv \
		sim/tb_hd6301v1_modes.sv
	build/obj_hd6301v1_modes/Vtb_hd6301v1_modes
	# Seven parameter profiles expose the documented mixed async CPU / E-sync DDR reset net.
	$(VERILATOR) --binary --timing --assert -Wall -Wno-SYNCASYNCNET \
		--top-module tb_hd6301v1_mode_exec \
		-Mdir build/obj_hd6301v1_mode_exec -o Vtb_hd6301v1_mode_exec \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv sim/tb_hd6301v1_mode_exec.sv
	build/obj_hd6301v1_mode_exec/Vtb_hd6301v1_mode_exec

test-hd6301v1-bus-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_hd6301v1_bus_wrapper \
		-Mdir build/obj_hd6301v1_bus_wrapper -o Vtb_hd6301v1_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6301v1_mcu.sv \
		rtl/hd6301/hd6301v1_bus_wrapper.sv sim/tb_hd6301v1_bus_wrapper.sv
	build/obj_hd6301v1_bus_wrapper/Vtb_hd6301v1_bus_wrapper
	$(PYTHON) -m unittest tests.test_hd6301v1_bus_model -v

test-hd6303r: test-hd6303r-modes test-hd6303r-bus-wrapper
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6303r_mcu \
		-Mdir build/obj_hd6303r_mcu -o Vtb_hd6303r_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	build/obj_hd6303r_mcu/Vtb_hd6303r_mcu
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6303r_mcu \
		"-GTEST_MODE=3'd1" -Mdir build/obj_hd6303r_mcu_mode1 \
		-o Vtb_hd6303r_mcu_mode1 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	build/obj_hd6303r_mcu_mode1/Vtb_hd6303r_mcu_mode1
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6303r_mcu \
		"-GTEST_MODE=3'd4" -Mdir build/obj_hd6303r_mcu_mode4 \
		-o Vtb_hd6303r_mcu_mode4 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	build/obj_hd6303r_mcu_mode4/Vtb_hd6303r_mcu_mode4
	$(PYTHON) -m unittest tests.test_hd6303r_device_model \
		tests.test_hd6303r_bus_model -v

test-hd6303r-modes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd6303r_modes \
		-Mdir build/obj_hd6303r_modes -o Vtb_hd6303r_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6303r_mcu.sv \
		sim/tb_hd6303r_modes.sv
	build/obj_hd6303r_modes/Vtb_hd6303r_modes

test-hd6303r-bus-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_hd6303r_bus_wrapper \
		-Mdir build/obj_hd6303r_bus_wrapper -o Vtb_hd6303r_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6303r_mcu.sv \
		rtl/hd6301/hd6303r_bus_wrapper.sv sim/tb_hd6303r_bus_wrapper.sv
	build/obj_hd6303r_bus_wrapper/Vtb_hd6303r_bus_wrapper
	$(PYTHON) -m unittest tests.test_hd6303r_bus_model -v

test-hd63701v0: test-hd63701v0-modes test-hd63701v0-bus-wrapper
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd63701v0_mcu \
		-Mdir build/obj_hd63701v0_mcu -o Vtb_hd63701v0_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv sim/tb_hd63701v0_mcu.sv
	build/obj_hd63701v0_mcu/Vtb_hd63701v0_mcu
	$(PYTHON) -m unittest tests.test_hd63701v0_device_model -v

test-hd63701v0-bus-wrapper:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_hd63701v0_bus_wrapper \
		-Mdir build/obj_hd63701v0_bus_wrapper -o Vtb_hd63701v0_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd63701v0_mcu.sv \
		rtl/hd6301/hd63701v0_bus_wrapper.sv sim/tb_hd63701v0_bus_wrapper.sv
	build/obj_hd63701v0_bus_wrapper/Vtb_hd63701v0_bus_wrapper
	$(PYTHON) -m unittest tests.test_hd63701v0_bus_model -v

test-hd63701v0-modes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd63701v0_modes \
		-Mdir build/obj_hd63701v0_modes -o Vtb_hd63701v0_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd63701v0_mcu.sv \
		sim/tb_hd63701v0_modes.sv
	build/obj_hd63701v0_modes/Vtb_hd63701v0_modes
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_hd63701v0_mode_exec \
		-Mdir build/obj_hd63701v0_mode_exec -o Vtb_hd63701v0_mode_exec \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv sim/tb_hd63701v0_mode_exec.sv
	build/obj_hd63701v0_mode_exec/Vtb_hd63701v0_mode_exec

test-hd6305-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6805_opcodes \
		"-GTEST_HITACHI=1'b1" -Mdir build/obj_hd6305_opcodes -o Vtb_hd6305_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6805_opcode_vectors_pkg.sv rtl/m6805/m6805_core.sv \
		sim/tb_m6805_opcodes.sv
	build/obj_hd6305_opcodes/Vtb_hd6305_opcodes

test-hd63705v0:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_hd63705v0_mcu \
		-Mdir build/obj_hd63705v0_mcu -o Vtb_hd63705v0_mcu \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv rtl/hd6305/hd63705v0_mcu.sv \
		sim/tb_hd63705v0_mcu.sv
	build/obj_hd63705v0_mcu/Vtb_hd63705v0_mcu

test-hd63705-peripheral-diff:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_hd63705_peripheral_diff \
		-Mdir build/obj_hd63705_peripheral_diff -o Vtb_hd63705_peripheral_diff \
		sim/generated/hd63705_peripheral_vectors_pkg.sv \
		sim/hd63705_peripheral_bus_stub_pkg.sv sim/stub/m6805_core.sv \
		rtl/hd6305/hd63705v0_mcu.sv sim/tb_hd63705_peripheral_diff.sv
	build/obj_hd63705_peripheral_diff/Vtb_hd63705_peripheral_diff

test-alu: test-alu-rtl
	$(PYTHON) -m unittest tests.test_alu_exhaustive -v

test-alu-rtl:
	mkdir -p build
	$(VERILATOR) --binary --assert -Wall --top-module tb_alu \
		-Mdir build/obj_alu -o Vtb_alu \
		rtl/common/m680x_alu_pkg.sv sim/tb_alu.sv
	build/obj_alu/Vtb_alu

test-cycle: test-wai-bus test-mc6801-wai-response test-mc6800-phased-wrapper test-hd6301v1-bus-wrapper test-hd63701v0-bus-wrapper test-m6800-opcodes test-m6801-opcodes test-hd6301-opcodes test-m6805-opcodes test-hd6305-opcodes

test-interrupts: test-wai-bus test-mc6801-wai-response test-m6800-rtl test-mc6800-wrapper test-m6805-rtl test-interrupt-delay test-hd6301-trap test-hd6301v1 test-hd6303r test-hd63701v0 test-hd63705v0

test-interrupt-delay:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_interrupt_delay \
		"-GTEST_ARCHITECTURE=2'b01" -Mdir build/obj_delay_m6801 -o Vdelay_m6801 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_interrupt_delay.sv
	build/obj_delay_m6801/Vdelay_m6801
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_interrupt_delay \
		"-GTEST_ARCHITECTURE=2'b10" -Mdir build/obj_delay_hd6301 -o Vdelay_hd6301 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_interrupt_delay.sv
	build/obj_delay_hd6301/Vdelay_hd6301
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6805_interrupt_delay \
		-Mdir build/obj_delay_hd6305 -o Vdelay_hd6305 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv sim/tb_interrupt_delay.sv
	build/obj_delay_hd6305/Vdelay_hd6305

test-peripherals: test-mc6803 test-mc6801-modes test-mc6801-bus-wrapper test-mc6801-sci-external test-mc6801-sci-biphase test-mc6801-peripheral-diff test-hd6301v1 test-hd6303r test-hd63701v0 test-mc68705p5 test-mc68705p5-peripheral-diff test-hd63705v0 test-hd63705-peripheral-diff

test-mc68705p5:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc68705p5_mcu \
		-Mdir build/obj_mc68705p5 -o Vtb_mc68705p5 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6805/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv sim/tb_mc68705p5_mcu.sv
	build/obj_mc68705p5/Vtb_mc68705p5
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mc68705p5_mask_timer \
		-Mdir build/obj_mc68705p5_mask_timer -o Vtb_mc68705p5_mask_timer \
		sim/mc68705p5_peripheral_bus_stub_pkg.sv \
		sim/stub/mc68705p5/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv \
		sim/tb_mc68705p5_mask_timer.sv
	build/obj_mc68705p5_mask_timer/Vtb_mc68705p5_mask_timer

test-mc68705p5-peripheral-diff:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall \
		--top-module tb_mc68705p5_peripheral_diff \
		-Mdir build/obj_mc68705p5_peripheral_diff -o Vtb_mc68705p5_peripheral_diff \
		sim/generated/mc68705p5_peripheral_vectors_pkg.sv \
		sim/mc68705p5_peripheral_bus_stub_pkg.sv \
		sim/stub/mc68705p5/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv \
		sim/tb_mc68705p5_peripheral_diff.sv
	build/obj_mc68705p5_peripheral_diff/Vtb_mc68705p5_peripheral_diff

test-random: test-random-m6800 test-random-m6801 test-random-hd6301 test-random-m6805 test-random-hd6305

test-random-m6800:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_random_m6800 \
		-Mdir build/obj_random_m6800 -o Vtb_random_m6800 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/random_programs_pkg.sv rtl/m6800/m6800_core.sv sim/tb_random_m6800.sv
	build/obj_random_m6800/Vtb_random_m6800

test-random-m6801:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_random_m6800 \
		"-GTEST_ARCHITECTURE=2'b01" -Mdir build/obj_random_m6801 -o Vtb_random_m6801 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/random_programs_pkg.sv rtl/m6800/m6800_core.sv sim/tb_random_m6800.sv
	build/obj_random_m6801/Vtb_random_m6801

test-random-hd6301:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_random_m6800 \
		"-GTEST_ARCHITECTURE=2'b10" -Mdir build/obj_random_hd6301 -o Vtb_random_hd6301 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/random_programs_pkg.sv rtl/m6800/m6800_core.sv sim/tb_random_m6800.sv
	build/obj_random_hd6301/Vtb_random_hd6301

test-random-m6805:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_random_m6805 \
		-Mdir build/obj_random_m6805 -o Vtb_random_m6805 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/random_programs_pkg.sv rtl/m6805/m6805_core.sv sim/tb_random_m6805.sv
	build/obj_random_m6805/Vtb_random_m6805

test-random-hd6305:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_random_m6805 \
		"-GTEST_HITACHI=1'b1" -Mdir build/obj_random_hd6305 -o Vtb_random_hd6305 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/random_programs_pkg.sv rtl/m6805/m6805_core.sv sim/tb_random_m6805.sv
	build/obj_random_hd6305/Vtb_random_hd6305

test-iverilog: spec-check
	mkdir -p build/iverilog
	$(IVERILOG) -g2012 -Wall -s tb_mc6800_phased_bus_wrapper \
		-o build/iverilog/mc6800_phased_bus_wrapper \
		rtl/generated/yosys_m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv \
		rtl/m6800/mc6800_phased_bus_wrapper.sv \
		sim/tb_mc6800_phased_bus_wrapper.sv
	$(VVP) build/iverilog/mc6800_phased_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_wai_response \
		-o build/iverilog/mc6801_wai_response \
		rtl/generated/yosys_m6800_core.sv sim/tb_mc6801_wai_response.sv
	$(VVP) build/iverilog/mc6801_wai_response
	$(IVERILOG) -g2012 -Wall -s tb_m6800_wait_bus \
		-Ptb_m6800_wait_bus.TEST_ARCHITECTURE=0 -o build/iverilog/wait_bus_m6800 \
		rtl/generated/yosys_m6800_core.sv sim/tb_m6800_wait_bus.sv
	$(VVP) build/iverilog/wait_bus_m6800
	$(IVERILOG) -g2012 -Wall -s tb_m6800_wait_bus \
		-Ptb_m6800_wait_bus.TEST_ARCHITECTURE=1 -o build/iverilog/wait_bus_m6801 \
		rtl/generated/yosys_m6800_core.sv sim/tb_m6800_wait_bus.sv
	$(VVP) build/iverilog/wait_bus_m6801
	$(IVERILOG) -g2012 -Wall -s tb_m6800_wait_bus \
		-Ptb_m6800_wait_bus.TEST_ARCHITECTURE=2 -o build/iverilog/wait_bus_hd6301 \
		rtl/generated/yosys_m6800_core.sv sim/tb_m6800_wait_bus.sv
	$(VVP) build/iverilog/wait_bus_hd6301
	$(IVERILOG) -g2012 -Wall -s tb_m6800_core -o build/iverilog/tb_m6800_core \
		rtl/generated/yosys_m6800_core.sv sim/tb_m6800_core.sv
	$(VVP) build/iverilog/tb_m6800_core
	$(IVERILOG) -g2012 -Wall -s tb_mc6800_bus_wrapper -o build/iverilog/tb_mc6800_bus_wrapper \
		rtl/generated/yosys_m6800_core.sv rtl/m6800/mc6800_bus_wrapper.sv \
		sim/tb_mc6800_bus_wrapper.sv
	$(VVP) build/iverilog/tb_mc6800_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_m6805_core -o build/iverilog/tb_m6805_core \
		rtl/generated/yosys_m6805_core.sv sim/tb_m6805_core.sv
	$(VVP) build/iverilog/tb_m6805_core
	$(IVERILOG) -g2012 -Wall -s tb_mc68705p5_mcu -o build/iverilog/tb_mc68705p5 \
		rtl/generated/yosys_m6805_core.sv rtl/m6805/mc68705p5_mcu.sv sim/tb_mc68705p5_mcu.sv
	$(VVP) build/iverilog/tb_mc68705p5
	$(IVERILOG) -g2012 -Wall -s tb_mc68705p5_mask_timer \
		-o build/iverilog/tb_mc68705p5_mask_timer \
		sim/mc68705p5_peripheral_bus_stub_pkg.sv \
		sim/stub/mc68705p5/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv \
		sim/tb_mc68705p5_mask_timer.sv
	$(VVP) build/iverilog/tb_mc68705p5_mask_timer
	$(IVERILOG) -g2012 -Wall -s tb_mc68705p5_peripheral_diff \
		-o build/iverilog/mc68705p5_peripheral_diff \
		sim/generated/mc68705p5_peripheral_vectors_pkg.sv \
		sim/mc68705p5_peripheral_bus_stub_pkg.sv \
		sim/stub/mc68705p5/m6805_core.sv rtl/m6805/mc68705p5_mcu.sv \
		sim/tb_mc68705p5_peripheral_diff.sv
	$(VVP) build/iverilog/mc68705p5_peripheral_diff
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_mcu -o build/iverilog/tb_mc6801_mcu \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_mcu.sv
	$(VVP) build/iverilog/tb_mc6801_mcu
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_mcu -Ptb_mc6801_mcu.TEST_MODE=3 \
		-o build/iverilog/tb_mc6801_mcu_mode3 rtl/generated/yosys_m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_mcu.sv
	$(VVP) build/iverilog/tb_mc6801_mcu_mode3
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_modes -o build/iverilog/tb_mc6801_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_modes.sv
	$(VVP) build/iverilog/tb_mc6801_modes
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_boot_modes \
		-o build/iverilog/tb_mc6801_boot_modes rtl/generated/yosys_m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_boot_modes.sv
	$(VVP) build/iverilog/tb_mc6801_boot_modes
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_bus_wrapper \
		-o build/iverilog/tb_mc6801_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/m6801/mc6801_bus_wrapper.sv \
		sim/tb_mc6801_bus_wrapper.sv
	$(VVP) build/iverilog/tb_mc6801_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_sci_external \
		-o build/iverilog/tb_mc6801_sci_external \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_sci_external.sv
	$(VVP) build/iverilog/tb_mc6801_sci_external
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_sci_biphase \
		-o build/iverilog/tb_mc6801_sci_biphase \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_sci_biphase.sv
	$(VVP) build/iverilog/tb_mc6801_sci_biphase
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_peripheral_diff \
		-o build/iverilog/mc6801_peripheral_diff \
		sim/generated/mc6801_peripheral_vectors_pkg.sv \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_peripheral_diff.sv
	$(VVP) build/iverilog/mc6801_peripheral_diff
	$(IVERILOG) -g2012 -Wall -s tb_mc6801_peripheral_diff \
		-Ptb_mc6801_peripheral_diff.TEST_MODE=3 \
		-o build/iverilog/mc6801_peripheral_diff_mode3 \
		sim/generated/mc6801_peripheral_vectors_pkg.sv \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv sim/tb_mc6801_peripheral_diff.sv
	$(VVP) build/iverilog/mc6801_peripheral_diff_mode3
	$(IVERILOG) -g2012 -Wall -s tb_m6800_interrupt_delay \
		-Ptb_m6800_interrupt_delay.TEST_ARCHITECTURE=1 -o build/iverilog/delay_m6801 \
		rtl/generated/yosys_m6800_core.sv sim/tb_interrupt_delay.sv
	$(VVP) build/iverilog/delay_m6801
	$(IVERILOG) -g2012 -Wall -s tb_m6800_interrupt_delay \
		-Ptb_m6800_interrupt_delay.TEST_ARCHITECTURE=2 -o build/iverilog/delay_hd6301 \
		rtl/generated/yosys_m6800_core.sv sim/tb_interrupt_delay.sv
	$(VVP) build/iverilog/delay_hd6301
	$(IVERILOG) -g2012 -Wall -s tb_m6805_interrupt_delay -o build/iverilog/delay_hd6305 \
		rtl/generated/yosys_m6805_core.sv sim/tb_interrupt_delay.sv
	$(VVP) build/iverilog/delay_hd6305
	$(IVERILOG) -g2012 -Wall -s tb_hd6301_trap -o build/iverilog/tb_hd6301_trap \
		rtl/generated/yosys_m6800_core.sv sim/tb_hd6301_trap.sv
	$(VVP) build/iverilog/tb_hd6301_trap
	$(IVERILOG) -g2012 -Wall -s tb_hd6303r_modes -o build/iverilog/tb_hd6303r_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_modes.sv
	$(VVP) build/iverilog/tb_hd6303r_modes
	$(IVERILOG) -g2012 -Wall -s tb_hd6303r_bus_wrapper \
		-o build/iverilog/tb_hd6303r_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6303r_mcu.sv \
		rtl/hd6301/hd6303r_bus_wrapper.sv sim/tb_hd6303r_bus_wrapper.sv
	$(VVP) build/iverilog/tb_hd6303r_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_hd6303r_mcu -o build/iverilog/tb_hd6303r_mcu \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	$(VVP) build/iverilog/tb_hd6303r_mcu
	$(IVERILOG) -g2012 -Wall -s tb_hd6303r_mcu \
		"-Ptb_hd6303r_mcu.TEST_MODE=3'd1" -o build/iverilog/tb_hd6303r_mcu_mode1 \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	$(VVP) build/iverilog/tb_hd6303r_mcu_mode1
	$(IVERILOG) -g2012 -Wall -s tb_hd6303r_mcu \
		"-Ptb_hd6303r_mcu.TEST_MODE=3'd4" -o build/iverilog/tb_hd6303r_mcu_mode4 \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6303r_mcu.sv sim/tb_hd6303r_mcu.sv
	$(VVP) build/iverilog/tb_hd6303r_mcu_mode4
	$(IVERILOG) -g2012 -Wall -s tb_hd6301v1_modes -o build/iverilog/tb_hd6301v1_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6301v1_mcu.sv sim/tb_hd6301v1_modes.sv
	$(VVP) build/iverilog/tb_hd6301v1_modes
	$(IVERILOG) -g2012 -Wall -s tb_hd6301v1_bus_wrapper \
		-o build/iverilog/tb_hd6301v1_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd6301v1_mcu.sv \
		rtl/hd6301/hd6301v1_bus_wrapper.sv sim/tb_hd6301v1_bus_wrapper.sv
	$(VVP) build/iverilog/tb_hd6301v1_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_hd6301v1_mode_exec \
		-o build/iverilog/tb_hd6301v1_mode_exec \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv sim/tb_hd6301v1_mode_exec.sv
	$(VVP) build/iverilog/tb_hd6301v1_mode_exec
	$(IVERILOG) -g2012 -Wall -s tb_hd6301v1_mcu -o build/iverilog/tb_hd6301v1_mcu \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd6301v1_mcu.sv sim/tb_hd6301v1_mcu.sv
	$(VVP) build/iverilog/tb_hd6301v1_mcu
	$(IVERILOG) -g2012 -Wall -s tb_hd63701v0_modes -o build/iverilog/tb_hd63701v0_modes \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd63701v0_mcu.sv \
		sim/tb_hd63701v0_modes.sv
	$(VVP) build/iverilog/tb_hd63701v0_modes
	$(IVERILOG) -g2012 -Wall -s tb_hd63701v0_mode_exec \
		-o build/iverilog/tb_hd63701v0_mode_exec \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv sim/tb_hd63701v0_mode_exec.sv
	$(VVP) build/iverilog/tb_hd63701v0_mode_exec
	$(IVERILOG) -g2012 -Wall -s tb_hd63701v0_mcu -o build/iverilog/tb_hd63701v0_mcu \
		rtl/generated/yosys_m6800_core.sv rtl/m6801/mc6801_mcu.sv \
		rtl/hd6301/hd63701v0_mcu.sv sim/tb_hd63701v0_mcu.sv
	$(VVP) build/iverilog/tb_hd63701v0_mcu
	$(IVERILOG) -g2012 -Wall -s tb_hd63701v0_bus_wrapper \
		-o build/iverilog/tb_hd63701v0_bus_wrapper \
		sim/mc6801_peripheral_bus_stub_pkg.sv sim/stub/m6800_core.sv \
		rtl/m6801/mc6801_mcu.sv rtl/hd6301/hd63701v0_mcu.sv \
		rtl/hd6301/hd63701v0_bus_wrapper.sv sim/tb_hd63701v0_bus_wrapper.sv
	$(VVP) build/iverilog/tb_hd63701v0_bus_wrapper
	$(IVERILOG) -g2012 -Wall -s tb_hd63705v0_mcu -o build/iverilog/tb_hd63705v0_mcu \
		rtl/generated/yosys_m6805_core.sv rtl/hd6305/hd63705v0_mcu.sv \
		sim/tb_hd63705v0_mcu.sv
	$(VVP) build/iverilog/tb_hd63705v0_mcu
	$(IVERILOG) -g2012 -Wall -s tb_hd63705_peripheral_diff \
		-o build/iverilog/hd63705_peripheral_diff \
		sim/generated/hd63705_peripheral_vectors_pkg.sv \
		sim/hd63705_peripheral_bus_stub_pkg.sv sim/stub/m6805_core.sv \
		rtl/hd6305/hd63705v0_mcu.sv sim/tb_hd63705_peripheral_diff.sv
	$(VVP) build/iverilog/hd63705_peripheral_diff

formal: spec-check
	mkdir -p build
	$(YOSYS) -ql build/formal_m6800.log -s formal/prove_m6800.ys
	$(YOSYS) -ql build/formal_m6801.log -s formal/prove_m6801.ys
	$(YOSYS) -ql build/formal_hd6301.log -s formal/prove_hd6301.ys
	$(YOSYS) -ql build/formal_m6805.log -s formal/prove_m6805.ys
	$(YOSYS) -ql build/formal_hd6305.log -s formal/prove_hd6305.ys
	$(YOSYS) -ql build/formal_mc6800_wrapper.log -s formal/prove_mc6800_wrapper.ys
	$(YOSYS) -ql build/formal_mc6800_phased_bus_wrapper.log -s formal/prove_mc6800_phased_bus_wrapper.ys
	$(YOSYS) -ql build/formal_mc6801_mcu.log -s formal/prove_mc6801_mcu.ys
	$(YOSYS) -ql build/formal_mc6801_modes.log -s formal/prove_mc6801_modes.ys
	$(YOSYS) -ql build/formal_mc6801_bus_wrapper.log -s formal/prove_mc6801_bus_wrapper.ys
	$(YOSYS) -ql build/formal_hd6303r_modes.log -s formal/prove_hd6303r_modes.ys
	$(YOSYS) -ql build/formal_hd6303r_bus_wrapper.log -s formal/prove_hd6303r_bus_wrapper.ys
	$(YOSYS) -ql build/formal_mc68705p5_mcu.log -s formal/prove_mc68705p5_mcu.ys
	$(YOSYS) -ql build/formal_hd6301v1_mcu.log -s formal/prove_hd6301v1_mcu.ys
	$(YOSYS) -ql build/formal_hd6301v1_modes.log -s formal/prove_hd6301v1_modes.ys
	$(YOSYS) -ql build/formal_hd6301v1_bus_wrapper.log -s formal/prove_hd6301v1_bus_wrapper.ys
	$(YOSYS) -ql build/formal_hd63701v0_mcu.log -s formal/prove_hd63701v0_mcu.ys
	$(YOSYS) -ql build/formal_hd63701v0_modes.log -s formal/prove_hd63701v0_modes.ys
	$(YOSYS) -ql build/formal_hd63701v0_bus_wrapper.log -s formal/prove_hd63701v0_bus_wrapper.ys
	$(YOSYS) -ql build/formal_hd63705v0_mcu.log -s formal/prove_hd63705v0_mcu.ys

synth: spec-check
	mkdir -p build
	$(YOSYS) -ql build/synth_m6800.log -s synth/m6800.ys
	$(YOSYS) -ql build/synth_m6801.log -s synth/m6801.ys
	$(YOSYS) -ql build/synth_hd6301.log -s synth/hd6301.ys
	$(YOSYS) -ql build/synth_m6805.log -s synth/m6805.ys
	$(YOSYS) -ql build/synth_hd6305.log -s synth/hd6305.ys
	$(YOSYS) -ql build/synth_mc68705p5.log -s synth/mc68705p5.ys
	$(YOSYS) -ql build/synth_mc6800_wrapper.log -s synth/mc6800_wrapper.ys
	$(YOSYS) -ql build/synth_mc6800_phased_bus_wrapper.log -s synth/mc6800_phased_bus_wrapper.ys
	$(YOSYS) -ql build/synth_mc6801_mcu.log -s synth/mc6801_mcu.ys
	$(YOSYS) -ql build/synth_mc6801_modes.log -s synth/mc6801_modes.ys
	$(YOSYS) -ql build/synth_mc6801_bus_wrapper.log -s synth/mc6801_bus_wrapper.ys
	$(YOSYS) -ql build/synth_hd6303r_mcu.log -s synth/hd6303r_mcu.ys
	$(YOSYS) -ql build/synth_hd6303r_mode1_mcu.log -s synth/hd6303r_mode1_mcu.ys
	$(YOSYS) -ql build/synth_hd6303r_mode4_mcu.log -s synth/hd6303r_mode4_mcu.ys
	$(YOSYS) -ql build/synth_hd6303r_bus_wrapper.log -s synth/hd6303r_bus_wrapper.ys
	$(YOSYS) -ql build/synth_hd6301v1_mcu.log -s synth/hd6301v1_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_mode0_mcu.log -s synth/hd6301v1_mode0_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_mode1_mcu.log -s synth/hd6301v1_mode1_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_mode4_mcu.log -s synth/hd6301v1_mode4_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_mode5_mcu.log -s synth/hd6301v1_mode5_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_mode6_mcu.log -s synth/hd6301v1_mode6_mcu.ys
	$(YOSYS) -ql build/synth_hd6301v1_bus_wrapper.log -s synth/hd6301v1_bus_wrapper.ys
	$(YOSYS) -ql build/synth_hd63701v0_mcu.log -s synth/hd63701v0_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_mode0_mcu.log -s synth/hd63701v0_mode0_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_mode1_mcu.log -s synth/hd63701v0_mode1_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_mode2_mcu.log -s synth/hd63701v0_mode2_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_mode5_mcu.log -s synth/hd63701v0_mode5_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_mode6_mcu.log -s synth/hd63701v0_mode6_mcu.ys
	$(YOSYS) -ql build/synth_hd63701v0_bus_wrapper.log -s synth/hd63701v0_bus_wrapper.ys
	$(YOSYS) -ql build/synth_hd63705v0_mcu.log -s synth/hd63705v0_mcu.ys

quick: lint test test-m6800-rtl test-m6805-rtl

ci: lint test test-alu-rtl test-wai-bus test-mc6801-wai-response test-m6800-rtl test-mc6800-wrapper test-mc6800-phased-wrapper test-m6801-opcodes test-hd6301-opcodes test-hd6301-trap test-hd6301v1 test-hd6303r test-hd63701v0 test-m6805-rtl test-hd6305-opcodes test-interrupt-delay test-peripherals test-random test-iverilog formal synth

clean:
	rm -rf build obj_dir
	find model tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
