#!/bin/sh
# debian-en-ie-locale.sh

set -u  # expanding unset variable makes non-interactive shell exit immediately
set -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

LANG=C LC_ALL=C; export LANG LC_ALL; unset LANGUAGE
PATH='/sbin:/usr/sbin:/bin:/usr/bin'; export PATH

set -x

export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y -q locales

# for debian
if test -f /etc/locale.gen
then	sed -i '/en_IE.UTF-8/ s/^. *//' /etc/locale.gen
fi

# ubuntu uses arg, debian ignores it
locale-gen en_IE.UTF-8
echo 'LANG="en_IE.UTF-8"' > /etc/default/locale
