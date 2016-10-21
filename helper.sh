#!/bin/sh
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-

case ~ in '~') echo "'~' does not expand. old /bin/sh?" >&2; exit 1; esac

case ${BASH_VERSION-} in *.*) PATH=/ shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) PATH=/ emulate ksh; esac

set -u  # expanding unset variable makes non-interactive shell exit immediately
set -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

LANG=en_IE.UTF-8 LC_ALL=en_IE.UTF-8; export LANG LC_ALL; unset LANGUAGE

# XXX If bash finds *this* script by searching PATH...
case $0 in */*) ;; *)
	echo "'$0' does not contain '/'s. try './$0'" >&2; exit 1
esac

if test "${HELPER_BUILD_SCRIPT_WRAPPER-}" != '' # set in cmd_build
then
	exec $HELPER_BUILD_SCRIPT_WRAPPER
	exit not reached
fi

saved_IFS=$IFS; readonly saved_IFS

warn () { printf '%s\n' "$*"; } >&2
die () { printf '%s\n' "$*"; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_env () { printf '+ %s\n' "$*" >&2; env "$@"; }
x_eval () { printf '+ %s\n' "$*" >&2; eval "$*"; }
x_exec () { printf '+ %s\n' "$*" >&2; exec "$@"; die "exec '$*' failed"; }


set_nap0 () # not absolute path $0 (best effort heuristics)
{
	case $0 in /*) nap0=${0##*/} ;; *) nap0=$0 ;; esac
	set_nap0 () { :; }
}

usage () {
	set_nap0; printf '\nUsage: %s %s %s\n\n' "$nap0" "$cmd" "$*"; exit 1;
} >&2


cmd_images () # output of `docker images` formatted differently
{
	printf '  IMAGE ID       CREATED        SIZE      REPOSITORY:TAG\n'
	exec docker images --format '{{.ID}}  {{printf "%10.10s ago  %8s" .CreatedSince .Size}}  {{.Repository}}:{{.Tag}}' "$@"
}

cmd_dangling () # $0 images --filter dangling=true "$@"
{
	cmd_images --filter dangling=true "$@"
}

cmd_ps () # narrower docker ps output (less info)
{
	echo
	echo 'CONTAINER ID  IMAGE              STATUS                NAMES'
	docker ps --format '{{.ID}}  {{printf "%-18.18s %-20.20s" .Image .Status}}  {{.Names}}' "$@"
	echo
}

cmd_history () # narrower docker history (114 columns)
{
	test $# = 1 || usage '{image}'
	case $1 in *:*) i=$1 ;; *) i=$1:latest; echo image: $i ;; esac
	docker history "$i" | cut -c 1-12,18-32,39-76,87-98,109-145
}

cmd_build () # wrapper to build with script(1) and diff-file
{
	case ${1-} in [0-9]|[1-9][0-9])
		MKDI_FORCE_BUILDS=$1; export MKDI_FORCE_BUILDS; shift
	esac
	test $# != 0 || usage [force-count] {buildscript} [args]
	test -f $1 || die "'$1': not a file"
	case $1 in ../* | */../*) die "'$1' references parent directory"
		;;	/*) die "'$1' is absolute path"
		;;	*/*) sfx=${1##*/}
		;;	*) sfx=$1; shift; set -- ./"$sfx" "$@"
	esac
	HELPER_BUILD_SCRIPT_WRAPPER=$*
	SHELL=$0
	MKDI_DIFFFILE=log-$sfx.diffs
	export SHELL MKDI_DIFFFILE HELPER_BUILD_SCRIPT_WRAPPER
	exec script -a log-$sfx.txt
}

cmd_testrun () # docker run --rm -it --name rm-"$name" "$image" "$@"
{
	privileged= vopt=
	while test $# -gt 0
	do
		case $1 in --privileged) privileged=--privileged; shift
			;; -v) vopt=$2; shift 2
			;; *) break
		esac
	done
	test $# != 0 || usage [--privileged] [-v ...] {image} [cmd [args]]
	image=$1; shift
	# ensure image exists (and do not call docker mothership)
	docker inspect --format '{{.ID}}' >/dev/null "$image"
	name=${image%:*} name=${name##*/}
	x_exec docker run --rm -it --name rm-"$name" -h "$name" $privileged \
		${vopt:+-v "$vopt"} "$image" "$@"
}

older () {
	case `exec ls -t "$1" "$2" 2>/dev/null` in "$1"*) return 1 ;; esac
}

# hidden
cmd_gendoc ()
{
	older README.rst readme.html   || x rst2html README.rst readme.html
	older More.rst more.html || x rst2html More.rst more.html
	echo file://$PWD/readme.html
}

cmd_source () # check source of given '$0' command or function
{
	set +x
	case ${1-} in '') die $0 $cmd cmd-prefix ;; esac
	echo
	exec sed -n "/^cmd_$1/,/^}/p; /^$1/,/^}/p" "$0"
}

cmd_help ()
{
	set_nap0
	echo
	echo Usage: $nap0 '[-x] <command> [args]'
	echo
	echo $nap0 commands available:
	echo
	# note: | in $0 would break expression below...
	sed -n '/^cmd_[a-z0-9_]/ { s/cmd_/ /; s/ () [ #]*/                   /
		s|$0|'"$nap0"'|g; s/\(.\{14\}\) */\1/p; }' "$0"
	echo
	echo Command can be abbreviated to any unambiguous prefix.
	echo
	exit 0
}

# ---

case ${1-} in -x) setx=-x; shift ;; *) setx= ;; esac

case ${1-} in '')
	cmd_help
esac


cm=$1; shift

case $cm in
	h) cm=help ;;
esac

cc= cp=
for m in `LC_ALL=C exec sed -n 's/^cmd_\([a-z0-9_]*\) (.*/\1/p' "$0"`
do
	case $m in
		$cm) cp= cc=1 cmd=$cm; break ;;
		$cm*) cp=$cc; cc="$m $cc"; cmd=$m ;;
	esac
done

case $cc in '') echo $0: $cm -- command not found.; exit 1
esac
case $cp in '') ;; *) echo $0: $cm -- ambiguous command: matches $cc; exit 1
esac
unset cc cp cm
readonly cmd
case $setx in -x) x () { "$@"; }; set -x
esac
cmd_$cmd ${1+"$@"}

# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
