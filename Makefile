PREFIX ?= $(HOME)/.local
DESTDIR ?=
bindir = $(DESTDIR)$(PREFIX)/bin
libdir = $(DESTDIR)$(PREFIX)/lib
targetdir = $(libdir)/aurocksglr-target
mandir = $(DESTDIR)$(PREFIX)/man/man1

.PHONY: all install uninstall clean

all:
	@echo "AurocksGLR is ready. Run 'make install PREFIX=...' to install it."

install:
	install -d "$(bindir)" "$(libdir)" "$(targetdir)" "$(mandir)"
	install -m 0755 AurocksGLR.sh "$(bindir)/AurocksGLR.sh"
	install -m 0755 AurocksGLR.pl "$(libdir)/AurocksGLR.pl"
	install -m 0644 target/*.m4 "$(targetdir)/"
	if command -v pod2man >/dev/null 2>&1; then pod2man --section=1 --center="AurocksGLR" --release="AurocksGLR" AurocksGLR.pl "$(mandir)/AurocksGLR.1"; else echo "pod2man not found; skipping manpage generation"; fi
	@case ":$$PATH:" in *:"$(bindir)":*) ;; *) \
		shell_name=$$(basename "$$SHELL" 2>/dev/null || echo sh); \
		case "$$shell_name" in fish) echo "Add $(bindir) to PATH (fish): set -Ux PATH $(bindir) \$$PATH";; csh|tcsh) echo "Add $(bindir) to PATH: setenv PATH \"$(bindir):\$$PATH\"";; *) echo "Add $(bindir) to PATH ($$shell_name): export PATH=\"$(bindir):\$$PATH\"";; esac;; esac

uninstall:
	rm -f "$(bindir)/AurocksGLR.sh" "$(libdir)/AurocksGLR.pl" "$(mandir)/AurocksGLR.1"
	rm -rf "$(targetdir)"

clean:
	@:
