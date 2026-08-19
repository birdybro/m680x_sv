PYTHON ?= python3

.PHONY: help refs refs-check spec-build spec-check lint test test-alu quick ci clean

help:
	@echo "m680x_sv developer targets"
	@echo "  refs        download/verify ignored primary-reference cache"
	@echo "  refs-check  validate reference metadata without network access"
	@echo "  spec-check  validate architecture and device specifications"
	@echo "  spec-build  regenerate expanded opcode specification artifacts"
	@echo "  lint        run source and policy consistency checks"
	@echo "  test        run current automated tests"
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

test-alu:
	$(PYTHON) -m unittest tests.test_alu_exhaustive -v

quick: lint test

ci: quick

clean:
	rm -rf build obj_dir
	find model tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
