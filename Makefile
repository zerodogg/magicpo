# MagicPO makefile

VERSION=0.4
MYVERSION=$(VERSION)

ifdef DESTDIR
prefix ?= /usr
endif
ifndef prefix
# This little trick ensures that make install will succeed both for a local
# user and for root. It will also succeed for distro installs as long as
# prefix is set by the builder.
prefix=$(shell perl -e 'if($$< == 0 or $$> == 0) { print "/usr" } else { print "$$ENV{HOME}/.local"}')
endif


BINDIR ?= $(prefix)/bin
DATADIR ?= $(prefix)/share
mandir ?= $(prefix)/share/man
# Create the manpage if required
POD2MAN = $(shell [ ! -e "./magicpo.1" ] && echo man)
ifneq ($(POD2MAN), man)
POD2MAN = $(shell [ ! -e "./magicpo.dict.5" ] && echo man)
endif
# Extract the git revision from the log
GITREV=$(shell git log|head|grep commit|perl -pi -e 'chomp; s/.//g if $$i; $$i =1;s/commit\s*//;')

# Install magicpo
install: $(POD2MAN)
	mkdir -p "$(DESTDIR)$(BINDIR)"
	mkdir -p "$(DESTDIR)$(DATADIR)/magicpo"
	install -m755 magicpo -D "$(DESTDIR)$(DATADIR)/magicpo/magicpo"
	install -m755 gtk-magicpo -D "$(DESTDIR)$(DATADIR)/magicpo/gtk-magicpo"
	ln -sf "$(DATADIR)/magicpo/magicpo" "$(DATADIR)/magicpo/gtk-magicpo" "$(DESTDIR)$(BINDIR)"
	cp -rf dictionaries modules "$(DESTDIR)$(DATADIR)/magicpo"
	install -m644 magicpo.1 -D "$(DESTDIR)$(mandir)/man1/magicpo.1"
	install -m644 magicpo.dict.5 -D "$(DESTDIR)$(mandir)/man5/magicpo.dict.5"
# Uninstall an installed magicpo
uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/magicpo" "$(DESTDIR)$(BINDIR)/gtk-magicpo"
	rm -rf "$(DESTDIR)$(DATADIR)/magicpo"
# Clean up the tree
clean:
	rm -f `find|egrep '~$$'`
	rm -f *.po
	rm -f *.tmp
	rm -f magicpo-$(MYVERSION).tar.bz2 magicpo-gitsnapshot-*.tar.bz2
	rm -rf magicpo-$(MYVERSION) magicpo-$(MYVERSION)-*git
# Verify syntax and run automated tests
test:
	@perl -Imodules -c modules/MagicPO/Parser.pm
	@perl -Imodules -c modules/MagicPO/DictLoader.pm
	@perl -Imodules -c modules/MagicPO/Magic.pm
	@perl -Imodules -c modules/MagicPO/TransDB.pm
	@perl -c magicpo
	@perl -c gtk-magicpo
	@perl -c tools/dictlint
	@perl -c tools/ReverseDict
	@echo
	perl -Imodules -mTest::Harness -e 'Test::Harness::runtests(glob("tools/tests/*.t"))'
# Create a manpage from the POD
man:
	pod2man --name "magicpo" --center "" --release "MagicPO $(MYVERSION)" ./magicpo ./magicpo.1
	pod2man --name "magicpo.dict" --center "" --release "MagicPO dictionary $(MYVERSION)" ./magicpo.dict.pod ./magicpo.dict.5
# Clean up the tree to prepare for distrib
distclean: clean
	perl -MFile::Find -e 'use File::Path qw/rmtree/;find(sub { return if $$File::Find::name =~ /\.git/; my $$i = `git stat $$_ 2>&1`; if ($$i =~ /^error.*did.*not.*match/) { if (-d $$_) { print "rmtree: $$File::Find::name\n"; rmtree($$_); } else {  print "unlink: $$File::Find::name\n"; unlink($$_); }}},"./");'
# Create the tarball
distrib: distclean test man
	mkdir -p magicpo-$(MYVERSION)
	cp -r ./`ls|grep -v magicpo-$(MYVERSION)` ./magicpo-$(MYVERSION)
	rm -rf `find magicpo-$(MYVERSION) -name \\.git`
	tar -jcvf magicpo-$(MYVERSION).tar.bz2 ./magicpo-$(MYVERSION)
	rm -rf magicpo-$(MYVERSION)
# Create a git snapshot
gitsnapshot:
	./tools/SetVersion "$(VERSION)-$(GITREV)git"
	-make distrib
	mv magicpo-$(VERSION)-$(GITREV)git.tar.bz2 magicpo-gitsnapshot-$(GITREV).tar.bz2
	./tools/SetVersion "$(VERSION)"
# User-facing version of gitsnapshot
gitdistrib: MYVERSION =$(VERSION)-$(GITREV)git
gitdistrib: distrib
