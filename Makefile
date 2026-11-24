PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin

.PHONY: test install uninstall

test:
	@fail=0; \
	for t in tests/t_*.sh; do \
		echo "== $$t"; \
		sh "$$t" || fail=1; \
	done; \
	echo "== python unit tests"; \
	python3 -m unittest discover -s tests || fail=1; \
	exit $$fail

install:
	mkdir -p $(BINDIR)
	install -m 755 callscribe $(BINDIR)/callscribe
	install -m 755 callscribe-merge $(BINDIR)/callscribe-merge

uninstall:
	rm -f $(BINDIR)/callscribe $(BINDIR)/callscribe-merge
