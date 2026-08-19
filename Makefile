PYTHON ?= python3

.PHONY: help refs refs-check lint test quick ci clean

help:
	@echo "m680x_sv developer targets"
	@echo "  refs        download/verify ignored primary-reference cache"
	@echo "  refs-check  validate reference metadata without network access"
	@echo "  lint        run source and policy consistency checks"
	@echo "  test        run current automated tests"
	@echo "  quick       run the fast local gate"
	@echo "  ci          run the authoritative committed-source gate"
	@echo "  clean       remove generated local build products"

refs:
	$(PYTHON) tools/fetch_references.py

refs-check:
	$(PYTHON) tools/fetch_references.py --manifest-only

lint: refs-check
	$(PYTHON) -m compileall -q tools tests
	git diff --check

test:
	$(PYTHON) -m unittest discover -s tests -v

quick: lint test

ci: quick

clean:
	rm -rf build obj_dir
	find tools tests -type d -name __pycache__ -prune -exec rm -rf {} +
