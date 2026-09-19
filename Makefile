NAME       ?= installer-beginners
PREFIX     ?= /usr/local
BINDIR     ?= $(PREFIX)/bin
DOCDIR     ?= $(PREFIX)/share/doc/$(NAME)
LICENSEDIR ?= $(PREFIX)/share/licenses/$(NAME)

.PHONY: install uninstall check

install:
	install -Dm755 installer.sh $(DESTDIR)$(BINDIR)/$(NAME)
	install -Dm644 README.md $(DESTDIR)$(DOCDIR)/README.md
	install -Dm644 LICENSE $(DESTDIR)$(LICENSEDIR)/LICENSE

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(NAME)
	rm -rf $(DESTDIR)$(DOCDIR) $(DESTDIR)$(LICENSEDIR)

check:
	bash -n installer.sh
	shellcheck -s bash installer.sh
