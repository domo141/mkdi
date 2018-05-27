#!/bin/bash
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-

set -u  # expanding unset variable makes non-interactive shell exit immediately
set -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

# just for the case developer tests this with `sh -x ...`
case ${BASH_VERSION-} in *.*) ;; *) echo 'not bash' >&2; sleep 10; exit 1
esac
shopt -s xpg_echo

# LANG=en_IE.UTF-8 LC_ALL=en_IE.UTF-8; export LANG LC_ALL; unset LANGUAGE
# PATH='/sbin:/usr/sbin:/bin:/usr/bin'; export PATH

# XXX If bash finds *this* script by searching PATH...
case $0 in */*) ;; *)
	echo "'$0' does not contain '/'s. try './$0'" >&2; exit 1
esac

printf -v secs '%(%s)T' # bash 4.2+ feature
printf -v tmoff '%(%z)T' # ditto

case $tmoff in [+-][0-9][0-9][0-9][0-9]) ;;
		*) tmoff=0
esac

tmhr=${tmoff%??}
tmsecs=$(($tmhr * 3600))

# set -x # uncomment when testing next line
sleep $((86400 - (secs - tmsecs) % 86400 + 10800)) # ~3 hrs next morning local
# check above with date --date='now + {number} seconds'

# the actual 'daily' part does nothing for now...
#EOF
