#!/bin/sh
# mkdi-01-base-for-mm.sh

. ./mkdi-00-lib.sh || exit 1

ver=8.6

mkdi_name debian-$ver-base-for-mm # pitäisi antaa tag (tai joku :day:)
mkdi_base debian:$ver pull
#mkdi_add_dest 755 /root/.docker-setup/ # already there
mkdi_add_file 755 debian-en-ie-locale.sh
mkdi_add_change ENV LC_ALL=en_IE.UTF-8 LANG=en_IE.UTF-8
mkdi_create

# the rest of this script is executed in the container

./debian-en-ie-locale.sh

export DEBIAN_FRONTEND=noninteractive

apt-get install -y -q postgresql postgresql-contrib nginx wget

apt-get -y autoremove
apt-get -y clean
rm -rf /var/lib/apt/lists/

mm_ver=3.3.0

wget --progress=dot:mega https://releases.mattermost.com/$mm_ver/mattermost-team-$mm_ver-linux-amd64.tar.gz
tar -C /opt -zxf mattermost-team-$mm_ver-linux-amd64.tar.gz
rm mattermost-team-$mm_ver-linux-amd64.tar.gz
