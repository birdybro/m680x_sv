PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: help refs refs-check spec-build spec-check lint test test-model test-m6800 test-m6801 test-m6805 test-hitachi test-alu test-alu-rtl quick ci clean

help:
	@echo "m680x_sv developer targets"
	@echo "  refs        download/verify ignored primary-reference cache"
	@echo "  refs-check  validate reference metadata without network access"
	@echo "  spec-check  validate architecture and device specifications"
	@echo "  spec-build  regenerate expanded opcode specification artifacts"
	@echo "  lint        run source and policy consistency checks"
	@echo "  test        run current automated tests"
	@echo "  test-model  run both independent architectural model paths"
	@echo "  test-m6800  run M6800-lineage model regressions"
	@echo "  test-m6801  run MC6801/MC6803 model regressions"
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

spec-check: refs-check
	$(PYTHON) -m tools.validate_devices
	$(PYTHON) -m tools.build_opcode_specs --check
	$(PYTHON) -m tools.validate_opcodes
	$(PYTHON) -m tools.build_rtl_decode --check

lint: spec-check
	$(PYTHON) -m compileall -q model tools tests
	git diff --check

test:
	$(PYTHON) -m unittest discover -s tests -v

test-model:
	$(PYTHON) -m unittest tests.test_m6800_model tests.test_m6805_model -v

test-m6800 test-m6801:
	$(PYTHON) -m unittest tests.test_m6800_model -v

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

quick: lint test

ci: quick

clean:
	rm -rf build obj_dir
	find model tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
