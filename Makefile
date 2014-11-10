VERSION = 0.1.1

bindir = /usr/local/sbin
sysconfdir = /etc
docdir = /usr/share/doc/mousetrapd
mandir = /usr/share/man
perllibdir = /usr/share/perl5

MAN_SECTION = 8

DOCS = LICENSE README CREDITS
SAMPLES = sample-mousetrapd.conf mousetrapd.redhat-init mousetrapd.redhat-spec
BIN = Makefile mousetrapd
MAN = mousetrapd.8
LIB = MT/

DIST_DIR = mousetrapd-${VERSION}
DEB_DIST_DIR = mousetrapd-${VERSION}-debian
TARBALL = mousetrapd_${VERSION}.orig.tar.gz
DEB_TARBALL = mousetrapd_${VERSION}.debian.tar.gz

FILES = ${DOCS} ${SAMPLES} ${BIN} ${MAN}

all: ${FILES}

clean:
	rm -rf mousetrapd*.tar.gz

dist: ${TARBALL} ${DEB_TARBALL}

${TARBALL}:
	mkdir -p ${DIST_DIR}
	cp ${FILES} ${DIST_DIR}
	cp -r ${LIB} ${DIST_DIR}/${LIB}
	tar czvf ${TARBALL} ${DIST_DIR}
	rm -rf ${DIST_DIR}

${DEB_TARBALL}:
	mkdir -p ${DEB_DIST_DIR}
	cp debian/* ${DEB_DIST_DIR}
	cp mousetrapd.debian-init ${DEB_DIST_DIR}/init
	tar czvf ${DEB_TARBALL} ${DEB_DIST_DIR}
	rm -rf ${DEB_DIST_DIR}

doc:
	pod2man --center "Mousetrapd" --section ${MAN_SECTION} mousetrapd >mousetrapd.${MAN_SECTION}
	pod2text mousetrapd >README

install:
	install -D mousetrapd ${DESTDIR}${bindir}/mousetrapd
	install -D MT/Config.pm ${DESTDIR}${perllibdir}/MT/Config.pm
	install -D MT/Logger.pm ${DESTDIR}${perllibdir}/MT/Logger.pm
	install -D MT/TokenBucket.pm ${DESTDIR}${perllibdir}/MT/TokenBucket.pm
	install -D MT/Watcher.pm ${DESTDIR}${perllibdir}/MT/Watcher.pm
	install -D MT/Server.pm ${DESTDIR}${perllibdir}/MT/Server.pm
	install -g root -m 0644 mousetrapd.8 ${DESTDIR}${mandir}/man8/
	install -D mousetrapd ${DESTDIR}${bindir}/mousetrapd
	[ -f ${DESTDIR}${sysconfdir}/mousetrapd/mousetrapd.conf ] || \
		install -g root -m 0644 -D sample-mousetrapd.conf ${DESTDIR}${sysconfdir}/mousetrapd/mousetrapd.conf
