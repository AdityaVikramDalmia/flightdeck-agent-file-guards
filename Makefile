PREFIX ?= $(HOME)/.local
.PHONY: test install

test:
	@bash tests/shrink-guard-test.sh
	@bash tests/nul-lint-test.sh
	@bash tests/untrusted-intake-test.sh
	@bash tests/install-test.sh

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 bin/shrink-guard.sh "$(DESTDIR)$(PREFIX)/bin/shrink-guard"
	install -m 0755 bin/nul-lint.sh "$(DESTDIR)$(PREFIX)/bin/nul-lint"
	install -m 0755 bin/untrusted-intake.sh "$(DESTDIR)$(PREFIX)/bin/untrusted-intake"
