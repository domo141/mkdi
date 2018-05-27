#!/bin/sh

# template file to be copied as a base for new script

. ./mkdi-00-lib.sh || exit 1

if mkdi_on_host
then
	echo on host
else
	echo in container
fi

# note: dash(1) may report *wrong* file for undefined vars. bash(1) seems not
# hint: sh -x ./mkdi-... (or bash -x ./mkdi-...) shows such problems quickly

mkdi_name image-name # latest $1 :day:
mkdi_base !pullable-image pull
#mkdi_base !pullable-image mkdi-01-make-parent.sh
#mkdi_add_dest 755 /root/.docker-setup/ # already there
mkdi_add_dest 755 /root/no-content/
mkdi_add_file 755 README.rst
mkdi_add_change ENV LC_ALL=en_IE.UTF-8 LANG=en_IE.UTF-8
mkdi_add_change EXPOSE 80
mkdi_add_change USER $USER
mkdi_add_change WORKDIR /
mkdi_add_change VOLUME /var/cache
mkdi_add_change LABEL template=template
mkdi_add_change ENTRYPOINT [ "/bin/false" ]
mkdi_add_change CMD [ "/bin/false" ]
mkdi_comment comment line
exit # <- for initial testing, with sh -x ./mkdi-... remove when thru that...
mkdi_create "$@"

### the rest of this script is executed in the container ###

die 'no content in this template'
