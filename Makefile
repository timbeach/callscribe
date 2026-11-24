PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin

.PHONY: test install uninstall

test:
	@fail=0; \
	for t in tests/t_*.sh; do \
		echo "== $$t"; \
		sh "$$t" || fail=1; \
	done; \
	exit $$fail

install:
	mkdir -p $(BINDIR)
	install -m 755 callscribe $(BINDIR)/callscribe

uninstall:
	rm -f $(BINDIR)/callscribe
