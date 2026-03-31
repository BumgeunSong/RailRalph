.PHONY: install check test uninstall

install:
	./install.sh

check:
	./install.sh --check-only

test:
	./tests/test-rail.sh

uninstall:
	rm -f "$${HOME}/.local/bin/railralph"
