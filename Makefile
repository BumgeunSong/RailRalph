.PHONY: install check test uninstall

install:
	./install.sh

check:
	./install.sh --check-only

test:
	./tests/test-harness.sh

uninstall:
	rm -f "$${HOME}/.local/bin/railralph"
