#!/bin/sh
# mkdi-00-test.sh

. ./mkdi-00-lib.sh || exit 1

#test -f version && read version < version || version=0.1

mkdi_name mkdi-quick-test latest 1.0 :day:
mkdi_base debian:8.6 pull
mkdi_author Arttu T. Luupihvi '<atk@example.org>'
mkdi_add_dest 755 /root
mkdi_add_file 644 README.rst
# look `man Dockerfile` for these "changes" (and man docker-commit)
mkdi_add_change ENV LESS mdeQMiR # well, base image doesn't have less(1)...
mkdi_add_change EXPOSE 22 # ... and no sshd(8) either
mkdi_add_change WORKDIR /root
mkdi_add_change CMD exec /bin/bash --login # this syntax uses /bin/sh -c ...
#mkdi_add_change CMD '[ "/bin/bash", "--login" ]'
mkdi_comment example comment
mkdi_create unused-arg

### the rest of this script is executed in the container ###

echo Message from container "(pid $$)": Do nothing in order to be quick.
