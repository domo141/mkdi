#!/bin/sh
# mkdi-01-notmuch-build-env.sh

# browse https://hub.docker.com/explore/ to find more base images...

. ./mkdi-00-lib.sh || exit 1

known_argvals="'8.6', '14.04.5', '16.04', '24' or 'unstable'"

test $# != 0 || die Usage "$0 {debian/ubuntu/fedora base version}" \
		    "${NL}version options:" \
		    "${known_argvals% or *} and ${known_argvals#* or }"

case $known_argvals
  in *"'$1'"*) ;; *) die "'$1' not any of these: $known_argvals".
esac

# the scheme below works fine with current set of "supported" distributions...
case $1 in [12]?.04*)	base=ubuntu debian=true
	;; [23]*)	base=fedora debian=false
	;; *)		base=debian debian=true
esac

if mkdi_on_host
then	user=${SUDO_USER:-$USER}
	# note: $user check is stricter in container-executed code (from other
	#       codebase) -- this should have same level of strictness!!1!
	case $user in *["$IFS"]*) die "'$user' contains whitespace!"; esac
	set_uid_home () {
		IFS=:
		set -- `exec getent passwd "$user"`
		uid=$3 home=$6
		IFS=$saved_IFS
	}
	set_uid_home
else
	# in container, these values are given as arguments (mkdi_create below)
	user=$2 uid=$3 home=$4
fi

mkdi_name notmuch-be-$user-$base-$1
mkdi_base $base:$1 pull
#mkdi_add_dest 755 /root/.docker-setup/ # already there
if $debian
then	mkdi_add_file 755 debian-en-ie-locale.sh
fi
mkdi_add_change ENV LC_ALL=en_IE.UTF-8 LANG=en_IE.UTF-8
mkdi_add_change WORKDIR $home
mkdi_add_change CMD '[ "/bin/bash",  "--login" ]'
mkdi_add_change USER $user
#mkdi_add_change VOLUME '[ "'$home:$home'" ]' # did not work use -v $HOME:$HOME
mkdi_create "$1" "$user" "$uid" "$home"

### the rest of this script is executed in the container ###

set -x

chmod 755 /root # make /root visible to the non-root user...

test -f /etc/bash.bashrc && bashrc=/etc/bash.bashrc || bashrc=/etc/bashrc

cat >> /etc/profile.d/mkdi-rc.sh <<'EOF'
if test $UID != 0
then	echo
	eval r`exec stat --printf '_dev=%d ' / "$HOME" 2>/dev/null`
	if test "$_dev" = '' || test "$r_dev" = "$_dev"
	then
		echo "Home directory '$HOME' not mounted to this container"
		echo "Restart container with  --privileged -v $HOME:$HOME"
		echo "command line options"
		echo
	fi
	unset r_dev _dev

	echo If you need root access in this container, execute
	read hostname < /etc/hostname
	echo sudo docker exec -it -u root $hostname /bin/bash
	echo
fi
# emulate zsh printexitvalue
trap 'echo -n bash: exit $? \ \ ; fc -nl -1 -1' ERR
EOF

if test "$user" != root
then
	case $user in *[!-a-z0-9_]*) die "invalid user '$user'"; esac
	useradd -d "$home" -M -u $uid -U -s /bin/bash -c "user $user" "$user"
fi

if $debian
then	export DEBIAN_FRONTEND=noninteractive
	./debian-en-ie-locale.sh
	apt-get install -y -q build-essential git \
		libxapian-dev libgmime-2.6-dev libtalloc-dev zlib1g-dev \
		python-sphinx man   #  gdb   emacs-nox
	apt-get -y autoremove
	apt-get -y clean
	rm -rf /var/lib/apt/lists/
else
	: Note: dnf commands below may be long-lasting and silent...
	dnf -v -y install glibc-langpack-en
	dnf -v -y install make gcc gcc-c++ git \
		xapian-core-devel gmime-devel libtalloc-devel zlib-devel \
		python2-sphinx man  #  findutils gdb   emacs-nox
	dnf -v -y autoremove
	dnf -v -y clean all
fi
