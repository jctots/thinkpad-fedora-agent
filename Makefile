# The acceptance test for a guardrail is feeding it a real command and
# watching the verdict. `make probe` is that, and it is the only thing here
# that matters before the machine exists.

PYTHON ?= python3

.PHONY: probe check hooks

## probe — run the acceptance set against the real guard
probe:
	@PYTHON=$(PYTHON) test/probe --suite

## check — probe one command:  make check CMD='wipefs -a /dev/nvme0n1'
check:
	@PYTHON=$(PYTHON) test/probe --command '$(CMD)' $(if $(EXPECT),--expect $(EXPECT),)

## hooks — point git at the tracked pre-commit secret scan
hooks:
	@scripts/install-hooks.sh
