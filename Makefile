PACKAGE=cdns
VER=0.5-1
ARCH=all

IPK:=${PACKAGE}_${VER}_${ARCH}.ipk
export COPY_EXTENDED_ATTRIBUTES_DISABLE:=true
export COPYFILE_DISABLE:=true

INSTALL_HOST:=polidea-cdns
DEPLOY_HOST:=polidea-cdns-deploy:cdns

SOURCES_AND_DIRS:=$(shell find etc usr www '!' -name '.DS_Store')
CONFIGS:=$(shell find etc/config '!' -name '.DS_Store' -type f)
SOURCES:=$(shell find etc/init.d usr www '!' -name '.DS_Store' -type f)

all: ipk

help:
	@echo "make ipk - build ipk package"
	@echo "make deploy - push built package to remote repository"
	@echo "make install - install ipk on development device"
	@echo "make pull - download all changed files to working copy"
	@echo "make pullall - download all changed files with configs to working copy"
	@echo "make push - upload all changed files to development device"
	@echo "make pushall - upload all changed files with configs to development device"
	@echo "make clean - clean working copy"

info:
	echo ${SOURCES} ${CONFIGS}

control: Makefile
	sed -i "" -e "s/^Version: .*$$/Version: ${VER}/" $@

www/cdns.html: Makefile
	sed -i "" -e "s|<footer>.*</footer>|<footer>Polidea, `date +'%Y-%m-%d'`, v.${VER}</footer>|" $@

control.tar.gz: ./control ./conffiles ./postinst ./postrm
	tar --numeric-owner -zcf $@ $^

data.tar.gz: ${SOURCES_AND_DIRS}
	find . -name ".DS_Store" -delete
	tar --numeric-owner -zcf $@ $^

${IPK}: debian-binary data.tar.gz control.tar.gz
	tar --numeric-owner -zcf $@ $^

deploy: clean ${IPK}
	scp ${IPK} ${DEPLOY_HOST}

install: clean ${IPK}
	scp ${IPK} ${INSTALL_HOST}:/tmp
	ssh ${INSTALL_HOST} "opkg --nodeps install /tmp/${IPK}"

pull: FORCE
	( echo "cd /"; for i in ${SOURCES}; do echo "get $$i $$i"; done ) | sftp -q ${INSTALL_HOST}

pullall: FORCE
	( echo "cd /"; for i in ${CONFIGS} ${SOURCES}; do echo "get $$i $$i"; done ) | sftp -q ${INSTALL_HOST}

push: FORCE
	( echo "cd /"; for i in ${SOURCES}; do echo "put $$i $$i"; done ) | sftp -q ${INSTALL_HOST}

pushall: FORCE
	( echo "cd /"; for i in ${CONFIGS} ${SOURCES}; do echo "put $$i $$i"; done ) | sftp -q ${INSTALL_HOST}

ipk: ${IPK}

clean:
	rm -f ${IPK} control.tar.gz data.tar.gz

FORCE:

