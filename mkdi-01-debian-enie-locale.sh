#!/bin/sh
# mkdi-01-debian-locale.sh

. ./mkdi-00-lib.sh || exit 1

known_argvals="'8.4', '8.5', '8.6', '14.04.5' or '16.04'"

test $# != 0 || die Usage "$0 {debian/ubuntu base version}" \
		    "${NL}version options:" \
		    "${known_argvals% or *} and ${known_argvals#* or }"

case $known_argvals
  in *"'$1'"*) ;; *) die "'$1' not any of these: $known_argvals".
esac

case $1 in 1?.04*) debian=ubuntu ;; *) debian=debian ;; esac

mkdi_name $debian-$1-locale # latest $1
mkdi_base $debian:$1 pull
#mkdi_add_dest 755 /root/.docker-setup/ # already there
mkdi_add_file 755 debian-en-ie-locale.sh
mkdi_add_change ENV LC_ALL=en_IE.UTF-8 LANG=en_IE.UTF-8
mkdi_create "$1"

### the rest of this script is executed in the container ###

./debian-en-ie-locale.sh

apt-get -y autoremove
apt-get -y clean
rm -rf /var/lib/apt/lists/
