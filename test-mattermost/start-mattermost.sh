#!/bin/sh
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-
# $ start-mattermost.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2016 Tomi Ollila
#	    All rights reserved
#
# Created: Tue 24 Aug 2016 22:31:28 EEST too
# Last modified: Sun 16 Oct 2016 20:04:10 +0300 too

set -u  # expanding unset variable makes non-interactive shell exit immediately
set -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

LANG=en_IE.UTF-8 LC_ALL=en_IE.UTF-8; export LANG LC_ALL; unset LANGUAGE

# XXX If bash finds *this* script by searching PATH...
case $0 in */*) ;; *)
	echo "'$0' does not contain '/'s. try './$0'" >&2; exit 1
esac

warn () { for l; do echo "$l"; done; } >&2
die () { echo; for l; do echo "$l"; done; echo; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_exec () { printf '+ %s\n' "$*" >&2; exec "$@"; die "exec '$*' failed"; }

mm=mattermost
mmi=mkdi-test-$mm

get_isolated_network_id ()
{
	network_id=`exec docker network inspect -f '{{.ID}}' isolated-nw 2>/dev/null` || :
	if test "$network_id" = ''
	then network_id=`exec docker network create --driver bridge isolated-nw`
	fi
}

cnd=`exec docker inspect -f '{{json .NetworkSettings.Networks}}' $mm 2>/dev/null` || :

#test line: docker inspect -f '{{json .NetworkSettings.Networks}}' {cntr} | jq .

start_container ()
{
	x docker start $mm
	echo sleeping 2 seconds while gathering some initial logs
	echo
	sleep 2
	x docker logs $mm
	test "${SUDO_USER-}" = '' && sudo= || sudo=sudo
	echo execute '' $sudo docker logs $mm '' to see more.
	$1 || echo 'locate the server near '' https://{host}:5443/'
	echo
	exit
}

if test "$cnd" != ''
then
	# restart existing container (if not running already)

	case $cnd in *'"EndpointID":"'[0-9a-f]*)
		die "Container '$mm' is already running"
	esac

	get_isolated_network_id

	# ensure container references isolated-nw (XXX does not ensure it is the only one)
	case $cnd in *$network_id*) ;; *)
		die "Existing '$mm' container is not configured to use 'isolated-nw' network"
	esac

	start_container true
	exit not reached
fi
# else

crtfile=
keyfile=

for arg
do
	case $arg in *.key|*.crt)
		test -f "$arg" || die "'$arg': no such file"
	esac
	case $arg in *.key) keyfile=$arg; continue; esac;
	case $arg in *.crt) crtfile=$arg; continue; esac;
	die "'$arg': unknown argument"
done

test "$crtfile" || \
	die "Creating '$mm' container. Append server .crt and .key files" \
	    "to the '$0' command line." '' \
	    'The dummy-* files or ./create-certs.sh may be used for testing...'

test "$keyfile" || die "Server .key file missing. Give it from command line."

cn=`openssl x509 -text -in "$crtfile" | sed -n 's/.*Subject.*CN=//p'`
case $cn in '' | *[!0-9A-Za-z.-]*)
	die "Problem extracting cn '$cn' from $crtfile"
esac

get_isolated_network_id

x docker create --name $mm -h $mm -p 5443:5443 --net isolated-nw $mmi \
	/usr/local/sbin/initti.pl

tmpfile=`exec mktemp`
trap "x rm -f $tmpfile; x docker rm $mm" 0
x docker cp $crtfile $mm:/etc/ssl/private/nginx-server.crt
x docker cp $keyfile $mm:/etc/ssl/private/nginx-server.key
x docker cp $mm:/etc/nginx/sites-available/mattermost $tmpfile
# perl -pi -e would write to another temporary file...
x perl -e 'use 5.10.1; use strict; use warnings; my @l;
	open F, "+<", $ARGV[0] or die "opening $ARGV[0] failed: $!\n";
	while (<F>) { s/\bserver_name\K\s.*/ $ARGV[1]/; push @l, $_; }
	seek F, 0, 0;  print F @l;  truncate F, tell F;
' $tmpfile $cn
x docker cp $tmpfile $mm:/etc/nginx/sites-available/mattermost
x rm -f $tmpfile
trap - 0

start_container false
