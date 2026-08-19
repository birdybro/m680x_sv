PYTHON ?= python3

.PHONY: help refs refs-check spec-build spec-check lint test test-model test-m6800 test-m6801 test-m6805 test-hitachi test-alu quick ci clean

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
	@echo "  test-alu    run exhaustive practical ALU state spaces"
	@echo "  quick       run the fast local gate"
	@echo "  ci          run the authoritative committed-source gate"
	@echo "  clean       remove generated local build products"

refs:
	$(PYTHON) -m tools.fetch_references

refs-check:
	$(PYTHON) -m tools.fetch_references --manifest-only

spec-build:
	$(PYTHON) -m tools.build_opcode_specs

spec-check: refs-check
	$(PYTHON) -m tools.validate_devices
	$(PYTHON) -m tools.build_opcode_specs --check
	$(PYTHON) -m tools.validate_opcodes

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

test-alu:
	$(PYTHON) -m unittest tests.test_alu_exhaustive -v

quick: lint test

ci: quick

clean:
	rm -rf build obj_dir
	find model tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
