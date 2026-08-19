PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: help refs refs-check spec-build spec-check lint lint-rtl test test-model test-m6800 test-m6800-rtl test-m6800-opcodes test-m6801 test-m6801-opcodes test-m6805 test-hitachi test-alu test-alu-rtl quick ci clean

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
	@echo "  test-m6801  run MC6801/MC6803 model regressions"
	@echo "  test-m6801-opcodes compare all documented MC6801 encodings to the model"
	@echo "  test-m6805  run M6805-lineage model regressions"
	@echo "  test-hitachi run HD6301/HD6305 model regressions"
	@echo "  test-alu    run Python and RTL exhaustive practical ALU spaces"
	@echo "  test-alu-rtl run the compiled SystemVerilog ALU regression"
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

spec-check: refs-check
	$(PYTHON) -m tools.validate_devices
	$(PYTHON) -m tools.build_opcode_specs --check
	$(PYTHON) -m tools.validate_opcodes
	$(PYTHON) -m tools.build_rtl_decode --check
	$(PYTHON) -m tools.build_m6800_rtl_vectors --check

lint: spec-check lint-rtl
	$(PYTHON) -m compileall -q model tools tests
	git diff --check

lint-rtl:
	$(VERILATOR) --lint-only --assert -Wall --top-module m6800_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module m6800_core -GARCHITECTURE=1 \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv

test:
	$(PYTHON) -m unittest discover -s tests -v

test-model:
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_m6805_model -v

test-m6800: test-m6800-rtl
	$(PYTHON) -m unittest tests.test_m6800_model -v

test-m6800-rtl: test-m6800-opcodes
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_core \
		-Mdir build/obj_m6800_core -o Vtb_m6800_core \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		rtl/m6800/m6800_core.sv sim/tb_m6800_core.sv
	build/obj_m6800_core/Vtb_m6800_core

test-m6800-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_opcodes \
		-Mdir build/obj_m6800_opcodes -o Vtb_m6800_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6800_opcode_vectors_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_opcodes.sv
	build/obj_m6800_opcodes/Vtb_m6800_opcodes

test-m6801: test-m6801-opcodes
	$(PYTHON) -m unittest tests.test_m6800_model -v

test-m6801-opcodes:
	mkdir -p build
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_m6800_opcodes \
		-GTEST_ARCHITECTURE=1 -Mdir build/obj_m6801_opcodes -o Vtb_m6801_opcodes \
		rtl/common/m680x_alu_pkg.sv rtl/generated/m680x_decode_pkg.sv \
		sim/generated/m6800_opcode_vectors_pkg.sv rtl/m6800/m6800_core.sv \
		sim/tb_m6800_opcodes.sv
	build/obj_m6801_opcodes/Vtb_m6801_opcodes

test-m6805:
	$(PYTHON) -m unittest tests.test_m6805_model -v

test-hitachi:
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_m6805_model -v

test-alu: test-alu-rtl
	$(PYTHON) -m unittest tests.test_alu_exhaustive -v

test-alu-rtl:
	mkdir -p build
	$(VERILATOR) --binary --assert -Wall --top-module tb_alu \
		-Mdir build/obj_alu -o Vtb_alu \
		rtl/common/m680x_alu_pkg.sv sim/tb_alu.sv
	build/obj_alu/Vtb_alu

quick: lint test test-m6800-rtl

ci: quick

clean:
	rm -rf build obj_dir
	find model tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
