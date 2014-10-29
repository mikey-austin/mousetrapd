# Mousetrap makefile for distribution

VERSION = 0.0.4

bindir = /usr/local/sbin
sysconfdir = /etc
docdir = /usr/share/doc/mousetrap
mandir = /usr/share/man

# On Debian
#perllibdir = /usr/local/lib/site_perl

# RHEL
perllibdir = /usr/local/share/perl5

MAN_SECTION = 8

DOCS = LICENSE README CREDITS
SAMPLES = sample-mousetrap.conf mousetrap.redhat-init mousetrap.redhat-spec
BIN = Makefile mousetrap
MAN = mousetrap.8
LIB = MT/
TARBALL = mousetrap-${VERSION}.tar.gz
DIST_DIR = mousetrap-${VERSION}

FILES = ${DOCS} ${SAMPLES} ${BIN} ${MAN}

all: ${FILES}

clean:
	rm -rf mousetrap*.tar.gz

dist: ${TARBALL}

${TARBALL}:
	mkdir -p ${DIST_DIR}
	cp ${FILES} ${DIST_DIR}
	cp -r ${LIB} ${DIST_DIR}/${LIB}
	tar czvf ${TARBALL} ${DIST_DIR}
	rm -rf ${DIST_DIR}

doc:
	pod2man --center "Mousetrap" --section ${MAN_SECTION} mousetrap >mousetrap.${MAN_SECTION}
	pod2text mousetrap >README

install:
	install -D mousetrap ${DESTDIR}${bindir}/mousetrap
	install -D MT/Config.pm ${DESTDIR}${perllibdir}/MT/Config.pm
	install -D MT/Logger.pm ${DESTDIR}${perllibdir}/MT/Logger.pm
	install -D MT/TokenBucket.pm ${DESTDIR}${perllibdir}/MT/TokenBucket.pm
	install -D MT/Watcher.pm ${DESTDIR}${perllibdir}/MT/Watcher.pm
	install -D MT/Server.pm ${DESTDIR}${perllibdir}/MT/Server.pm
	install -g root -m 0644 mousetrap.8 ${DESTDIR}${mandir}/man8/
	install -D mousetrap ${DESTDIR}${bindir}/mousetrap
	[ -f ${DESTDIR}${sysconfdir}/mousetrap/mousetrap.conf ] || \
		install -g root -m 0644 -D sample-mousetrap.conf ${DESTDIR}${sysconfdir}/mousetrap/mousetrap.conf
