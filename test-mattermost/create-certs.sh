#!/bin/sh
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-
#
# Created: Fri 08 Jul 2016 22:54:50 EEST too
# Last modified: Sun 16 Oct 2016 20:03:55 +0300 too

case ~ in '~') echo "'~' does not expand. old /bin/sh?" >&2; exit 1; esac

case ${BASH_VERSION-} in *.*) PATH=/ shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) PATH=/ emulate ksh; esac

set -u  # expanding unset variable makes non-interactive shell exit immediately
##t -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

LANG=en_IE.UTF-8 LC_ALL=en_IE.UTF-8; export LANG LC_ALL; unset LANGUAGE
PATH='/sbin:/usr/sbin:/bin:/usr/bin'; export PATH

# XXX If bash finds *this* script by searching PATH...
case $0 in */*) ;; *)
	echo "'$0' does not contain '/'s. try './$0'" >&2; exit 1
esac

saved_IFS=$IFS; readonly saved_IFS

warn () { printf '%s\n' "$@"; } >&2
die () {  printf '%s\n' "$@"; exit 1; } >&2

x () { echo + "$@" >&2; "$@"; }

test $# -gt 0 || {
	die '' "Usage: $0 [--] [c [st [l [o [ou [cacn [cn]]]]]]]" '' \
	    'Enter certificate request information either from command line' \
	    'or asked interactively.' '' \
	    "'cacn' goes to rootCA and 'cn' (eg. fqdn) to device certificate."\
	    '' "Enter '--' as first arg to ask everything interactively." ''
}
case $1 in --) shift; esac

cabas=rootCA
cakey=rootCA.key
capem=rootCA.pem

redo=false

test -d _crts || mkdir _crts
cd _crts

#Country Name (2 letter code) [AU]:
#State or Province Name (full name) [Some-State]:
#Locality Name (eg, city) []:
#Organization Name (eg, company) [Internet Widgits Pty Ltd]:
#Organizational Unit Name (eg, section) []:
#Common Name (e.g. server FQDN or YOUR name) []:
#Email Address []:

subjdata ()
{
	r () { printf "$2: "; read $1; }
	test $# -ge 1 && _c=$1    || r _c    'Country (2 letter code)'
	test $# -ge 2 && _st=$2   || r _st   'Province'
	test $# -ge 3 && _l=$3    || r _l    'City'
	test $# -ge 4 && _o=$4    || r _o    'Company/Org'
	test $# -ge 5 && _ou=$5   || r _ou   'Org Unit'
	test $# -ge 6 && _cacn=$6 || r _cacn 'Root CA "name"'
	test $# -ge 7 && _cn=$7   || r _cn   'Host/IP'
}
subjdata "$@"

! $redo && test -f $cakey && test -f $capem && echo found $cabas.* || {
  trap "rm -f $cabas.*" 0
  x openssl genrsa -aes128 -out $cakey 2048

  x openssl req -x509 -new -nodes -key $cakey -sha256 -days 9999 -out $capem \
	-subj "/C=$_c/ST=$_st/L=$_l/O=$_o/OU=$_ou/CN=$_cacn/"
  redo=true
}
#rm $cabas.srl

! $redo && test -f device.key && test -f device.crt && echo found device.* || {
  trap 'rm -f device.*' 0
  x openssl genrsa -out device.key 2048

  x openssl req -new -key device.key -out device.csr \
	-subj "/C=$_c/ST=$_st/L=$_l/O=$_o/OU=$_ou/CN=$_cn/"

  x openssl x509 -req -in device.csr -CA $capem -CAkey $cakey -sha256 \
	-CAcreateserial -out device.crt -days 1000
  redo=true
}
#rm device.csr
trap - 0

cd ..
echo
/bin/ls -l _crts/*
echo
echo "Move 'device.crt' and 'device.key' to the server."
echo "Give 'rootCA.pem' to users to validate the server."
echo "Keep 'rootCA.key' in a safe place."
echo
