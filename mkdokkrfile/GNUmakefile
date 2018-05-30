
# SPDX-License-Identifier: BSD-2-Clause

SHELL = /bin/sh

MAKEFILE := $(MAKEFILE_LIST)  # hint: make -pn -f /dev/null

.PHONY: all
all:
	@echo
	@echo Demonstration targets:
	@echo
	@sed -n '/^all:/d; /^\./d; /^[[:alnum:]\.%-]*:/s/^/  /p' $(MAKEFILE)
	@echo

# It is somewhat dumb it is hard to restrict what is sent to docker daemon
# during build. Fortunately .git/ is not too big in this project.

.PHONY: testimage
testimage1: Dockerfile.1.out
	docker build -f $< -t $@ .
	@echo
	@echo 'test run: $$ [sudo] docker run --rm -it testimage1 /bin/bash'
	@echo

# the idea is, that Dockerfile.2.out begins with:  FROM testimage1:latest
testimage2: Dockerfile.2.out testimage1
	docker build -f $< -t $@ .

Dockerfile%.out: Dockerfile%.src mkdokkrfile.pl
	./mkdokkrfile.pl $<
#	cat "$@"

.PHONY: clean
clean:
	-grep -Hnie '^## md5: ' -e '^FROM' *.out >> dokkrfile.diffs 2>/dev/null
	-rm -f *.out *~
	@echo docker rmi ... have to be executed by hand

distclean: clean
	-rm -f dokkrfile.diffs

.SUFFIXES:
MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

# Local variables:
# mode: makefile
# End:
