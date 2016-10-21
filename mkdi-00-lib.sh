: || {
#!perl
#line 4
# This file consists of mkdi shell script library code and embedded perl
# helper program (shell code put into perl pod block between =pod and =cut).
=pod
}

# source this file as  ./mkdi-00-lib.sh || exit 1

case ${BASH_VERSION-} in *.*) PATH=/ shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) PATH=/ emulate ksh; esac

set -u  # expanding unset variable makes non-interactive shell exit immediately
set -f  # disable pathname expansion by default -- makes e.g. eval more robust
set -e  # exit on error -- know potential false negatives and positives !
#et -x  # s/#/s/ may help debugging  (or run /bin/sh -x ... on command line)

LANG=C LC_ALL=C; export LANG LC_ALL; unset LANGUAGE
PATH='/sbin:/usr/sbin:/bin:/usr/bin'; export PATH

# Note: dash(1) does not support dollar-single ($'\n'); therefore
NL='
'
readonly NL

saved_IFS=$IFS; readonly saved_IFS

warn () { printf '%s\n' "$*"; } >&2
die () { printf '%s\n' "$*"; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_env () { printf '+ %s\n' "$*" >&2; env "$@"; }
x_eval () { printf '+ %s\n' "$*" >&2; eval "$*"; }
x_exec () { printf '+ %s\n' "$*"; exec "$@"; die "exec '$*' failed"; }

if test $$ != 1
then
    bn0=${0##*/}
    echo "### Executing '$bn0${1:+ $*}' on host ###"
    readonly this=mkdi-00-lib.sh
    mkdi_on_host () { return 0; }
    name= tags= base= parent= pargs= author= changes= comment=
    mkdi_name () { name=$1; shift; tags=$*; readonly name tags; }
    mkdi_base () { case $1 in *:*) base=$1 ;; *) base=$1:latest ;; esac
		   parent=$2; shift 2; pargs=$*; readonly base parent pargs
    }
    mkdi_author () { author=$*; readonly author; }
    mkdi_add_dest () { adds="$adds$NL$1 ${2%/}/"; }
    mkdi_add_file () { adds="$adds$NL$1 $2"; }
    adds='755 /root/.docker-setup/'
    mkdi_add_file 644 $this # this gets filtered out on non-parent-pull images
    mkdi_add_file 755 "$bn0"
    mkdi_add_change () { changes="${changes:+$changes$NL}$*"; }
    mkdi_comment () { comment=$*; readonly comment; }
    mkdi_create () {
	test "$name" != '' || die "mkdi_name not given"
	test "$base" != '' || die "mkdi_base not given"
	test "${MKDI_IMAGES-}" != '' || {
		MKDI_IMAGES=`docker images -qa --no-trunc || kill $$ | sort -u`
		export MKDI_IMAGES
	}
	test "$parent" = 'pull' && pull=1 || { pull=0
		force_blds=${MKDI_FORCE_BUILDS-}
		case $force_blds in ( '' | *[!0-9]* ) ;;
			*) export MKDI_FORCE_BUILDS=$((force_blds - 1))
		esac
		"./$parent" $pargs
		echo "*** Continuing on host with '$bn0' ***"
		test -z "$force_blds" || export MKDI_FORCE_BUILDS=$force_blds
	}
	exec perl -x $this create-image "$name" "$tags" "$base" $pull \
		"$author" "$adds" "$changes" "$comment" "./$bn0" "$@"
	die not reached
    }
else
    echo "--- Executing '$0${1:+ $*}' in container ---"
    mkdi_on_host () { return 1; }
    mkdi_name () { :; }
    mkdi_base () { :; }
    mkdi_author () { :; }
    mkdi_add_dest () { :; }
    mkdi_add_file () { :; }
    mkdi_add_change () { :; }
    mkdi_comment () { :; }
    mkdi_create () { :; }
    sleep 0.1 # note: fractional seconds linux specific. for output ordering...
fi

return # return to the invoking script

;; c-x c-e at the end of following lines to change mode in emacs...
(shell-script-mode)
(cperl-mode)
(perl-mode)

=cut # this file continues as perl helper program

use 5.8.1;
use strict;
use warnings;
use Digest;

unless (@ARGV) {
    warn "Usage: $0 command [args]\n";
    open I, '<', $0 or die;
    warn "Commands:\n";
    while (<I>) { warn "  $1\n" if /^if ..cmd eq '(.*?)'/; }
    warn "\n";
    exit 1;
}
$| = 1;
my $cmd = shift;
my $pid = $$;
my $mtime;
my %filelocks;

my $exit = 0;
sub ddie(@) { $exit++; warn "@_\n"; } # delayed die

sub echo(@) { syswrite(STDOUT, "@_\n"); }
sub check_filelock($$);
sub xfork_parent_waits();
sub system0(@);
sub qsystem(@);
sub tar_directory_to_P($$);
sub tar_file_to_P($$$);
sub tar_close_P();
sub eval_end($);

if ($cmd eq 'create-image') {
    die "Usage: $0 $cmd name tags base pull author adds changes comment sname [...]\n"
      unless @ARGV >= 9;
    my ($name, $tags, $base, $pull, $author, $adds, $changes, $comment) = @ARGV;
    splice @ARGV, 0, 8;
    foreach (split /\n/, $adds) {
	die "'$_': Format incorrect\n" unless /^[0-7]{3}\s+(.*)/;
	my $filename = $1; next if $filename =~ /\/$/;
	ddie "'$filename': no such file\n" unless -f $filename;
    }
    exit 1 if $exit;
    # XXX add changes validation (early)
    #foreach (split /\n/, $changes) { }

    my $force_build = ($ENV{MKDI_FORCE_BUILDS} || '0');
    warn ("Incorrect MKDI_FORCE_BUILDS format: '$force_build' (ignored)\n"),
      $force_build = 0 unless ($force_build =~ /^-?\d+$/);

    if ($tags =~ /^\s*$/) { $tags = 'latest'; }
    else { sub day { my @lt = localtime;
		     sprintf "%d%02d%02d", $lt[5]+1900, $lt[4]+1, $lt[3]; }
	   $tags =~ s/:day:/&day/ge;
    }
    my @images = split /\n/, $ENV{MKDI_IMAGES};
    push @images, $base;
    my (%hashmap, $basehash);
    open I, '-|', qw/docker inspect --type image --format/,
      '{{.Id}} {{.RepoTags}} [{{index .ContainerConfig.Cmd 0}}]' .
      ' {{index .ContainerConfig.Labels "mkdi-digest"}}', @images or die;
    while (<I>) {
	next unless /^(\S+)\s+\[(.*?)\]\s+\[(.*?)\]\s+(.*?)\s*$/;
	my ($id, $tags, $command, $digest) = ($1, $2, $3, $4);
	$tags = $id if $tags =~ /^\s*$/;
	$id = $digest if $digest =~ /^md5:[0-9a-f]{32}$/;
	next if defined $hashmap{$id}; # @images has duplicates
	my @tags = split /\s+/, $tags;
	foreach (@tags) {
	    s|.*/||; # ...
	    $basehash = $id if $_ eq $base;
	}
	$hashmap{$id} = ($command eq $ARGV[0]) ? \@tags : '!';
    }
    close I; # don't check exit value as $base may not be there

    unless (defined $basehash) {
	die "Base image '$base' missing" unless $pull;
	echo "Pulling '$base' image";
	system0 qw/docker pull/, $base;
	open I, '-|', qw/docker inspect --type image --format {{.Id}}/, $base
	  or die;
	chomp ($basehash = <I>);
	close I or die;
    }
    my @input = ( $basehash, $adds, $changes, @ARGV );
    foreach (split /\n/, $adds) {
	next unless /^\d+\s+(.*[^\/])$/;
	my $f = $1;
	open I, '<', $f or die;
	binmode I;
	my $ctx = Digest->new('MD5');
	$ctx->addfile(*I);
	close I or die;
	my $digest = $ctx->hexdigest;
	check_filelock($f, $digest);
	push @input, $digest;
    }
    exit 1 if $exit;
    my $ctx = Digest->new('MD5');
    $ctx->add(join("\n", @input));
    my $digest = 'md5:' . $ctx->hexdigest;
    echo "Mkdi digest for image $name: $digest";
    #echo 'X', $_, @{$hashmap{$_}} foreach (keys %hashmap); exit 0;
    my @tags = map { "$name:$_" } split /\s+/, $tags;
    my $iname = $hashmap{$digest};
    undef $iname if defined $iname and $iname eq '!';
    if (defined $iname and $force_build <= 0) {
	echo "Found mathing image digest with tags: @$iname";
	my $ref = $iname->[0];
	TAG: foreach (@tags) {
	    my $tag = $_;
	    foreach (@$iname) { next TAG if $_ eq $tag; }
	    echo "+++ Adding missing tag $tag +++";
	    system0 qw/docker tag/, $ref, $tag;
	}
	echo ">>> Done with $name <<<";
	exit 0;
    }
    my $wipname = 'wip-'.$name;
    echo "Creating intermediate container $wipname";
    system0 qw(docker create
	       -w /root/.docker-setup/ --name), $wipname, $base, @ARGV;
    eval_end "qsystem qw/docker rm -f $wipname/";
    echo "Adding files and directories";
    open P, '|-', qw/docker cp -/, $wipname . ':/' or die;
    my $tdir;
    $mtime = time;
    foreach (split /\n/, $adds) {
	/^([0-7]{3})\s+(.*?)(\/?)$/ or die;
	my ($perm, $name) = ($1, $2);
	if ($3) {
	    $tdir = $name;
	    tar_directory_to_P oct($perm), $tdir;
	}
	else {
	    next if ! $pull and $name eq $0; # non-pulled parent already has $0
	    tar_file_to_P oct($perm), $tdir, $name;
	}
    }
    tar_close_P;
    #echo 'Container filesystem changes before script execution:';
    #system0 qw/docker diff/, $wipname;
    echo "=== Executing '@ARGV' in container ===";
    unless (xfork_parent_waits) {
	exec qw/docker start -i/, $wipname;
	die 'not reached';
    }
    die if $?;
    echo "=== Back on host ('@ARGV' completed) ===";
    my $difffile = $ENV{MKDI_DIFFFILE};
    if (defined $difffile and xfork_parent_waits == 0) {
	open STDOUT, '>>', $difffile or die;
	echo scalar localtime, 'Changes in', $name;
	exec qw/docker diff/, $wipname;
	die 'not reached';
    }
    qsystem qw/docker rmi/, @tags;
    my (@changes, $havecmd);
    foreach (split /\n/, $changes) {
	push(@changes, '-c', $_);
	$havecmd = 1 if $_ =~ /^CMD/;
    }
#    push @changes, '-c', 'CMD ["echo", "No CMD in image configuration. ' .
#     'Enter one on docker run/create command line."]' unless defined $havecmd;
    push @changes, '-c', "LABEL mkdi-digest=$digest";
    #push @changes, '-c', "ONBUILD LABEL mkdi-digest=0"; # not useful here
    push @changes, '-a', $author if $author ne '';
    push @changes, '-m', $comment if $comment ne '';
    my $nametag = shift @tags;
    echo "+++ Committing $nametag... +++";
    system0 qw/docker commit/, @changes, $wipname, $nametag;
    foreach (@tags) {
	echo "+++ Tagging $_ +++";
	system0 qw/docker tag/, $nametag, $_;
    }
    system0 qw/docker history/, $nametag;
    echo ">>> Done creating $name <<<";
    exit;
}

# Add more commands here

die "$0 $cmd: command not found\n";

sub read_filelocks()
{
    if (-f 'mkdi.filelocks') {
	open I, '<', 'mkdi.filelocks' or die;
	while(<I>) {
	    # pretty strict for now, no / nor ' ':s accepted (skipped)
	    next unless /^([\da-f]{32})\s+.*?([^\/\s]+)\s*$/;
	    $filelocks{$2} = [ $., $1 ];
	}
	close I;
    }
    eval 'read_filelocks() { }';
}

sub check_filelock($$)
{
    sub read_filelocks();
    read_filelocks();
    my $f = $_[0]; $f =~ s/.*\///;
    my $a = $filelocks{$_[0]};
    return unless defined $a;
    ddie "mkdi.filelocks:$a->[0]: file '$f': changed unexpectedly"
      unless $_[1] eq $a->[1];
}


sub xfork_parent_waits()
{
    my $pid = fork;
    die 'fork:' unless defined $pid;
    wait if $pid;
    return $pid;
}

sub system0(@) {
    return unless system @_;
    my @c = caller; die "Died ad $c[1] line $c[2]\n";
}

sub qsystem(@) {
    return if xfork_parent_waits;
    open STDOUT, '>', '/dev/null';
    open STDERR, '>&', \*STDOUT;
    exec @_;
    die 'not reached';
}

# IEEE Std 1003.1-1988 (“POSIX.1”) ustar format
# tname perm uid gid size mtime type lname uname gname
sub _tarlisted_mkhdr($$$$$$$$$$)
{
    if (length($_[7]) > 99) {
	die "Link name '$_[7]' too long\n";
    }
    my $name = $_[0];
    my $prefix;
    if (length($name) > 99) {
	die "Name splitting unimplemented ('$name' too long)\n";
    }
    else {
	$name = pack('a100', $name);
	$prefix = pack('a155', '');
    }
    my $mode = sprintf("%07o\0", $_[1]);
    my $uid = sprintf("%07o\0", $_[2]);
    my $gid = sprintf("%07o\0", $_[3]);
    my $size = sprintf("%011o\0", $_[4]);
    my $mtime = sprintf("%011o\0", $_[5]);
    my $checksum = '        ';
    my $typeflag = $_[6];
    my $linkname = pack('a100', $_[7]);
    my $magic = "ustar\0";
    my $version = '00';
    my $uname = pack('a32', $_[8]);
    my $gname = pack('a32', $_[9]);
    my $devmajor = "0000000\0";
    my $devminor = "0000000\0";
    my $pad = pack('a12', '');

    my $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    my $sum = 0;
    foreach (split //, $hdr) {
	$sum = $sum + ord $_;
    }
    $checksum = sprintf "%06o\0 ", $sum;
    $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    return $hdr;
}

my $_tarlisted_wb = 0;

sub tar_directory_to_P($$)
{
    print "Adding d $_[0] $_[1]\n";
    # XXX mtime
    my $hdr = _tarlisted_mkhdr($_[1], $_[0], 0, 0, 0,
			       $mtime, '5', '', 'root', 'root');
    syswrite P, $hdr;
    $_tarlisted_wb += 512;
}

sub tar_file_to_P($$$)
{
    my $size = -s $_[2];
    my $bn = $_[2]; $bn =~ s,.*/,,;
    print "Adding f $_[0] $_[1]/$bn (from $_[2], $size bytes)\n";

    my $hdr = _tarlisted_mkhdr("$_[1]/$bn", $_[0], 0, 0, $size,
			       $mtime, '0', '', 'root', 'root');
    syswrite P, $hdr;
    open I, '<', $_[2] or die;
    my $buf; my $tlen = 0;
    while ( (my $len = sysread(I, $buf, 65536)) > 0) {
	syswrite P, $buf;
	$tlen += $len;
    }
    die "Short read ($tlen != $size)!\n" if $tlen != $size;
    $_tarlisted_wb += $tlen;
    close I;
    if ($tlen % 512 != 0) {
	my $more = 512 - $_tarlisted_wb % 512;
	syswrite P, "\0" x $more;
	$_tarlisted_wb += $more;
    }
}

sub tar_close_P()
{
    # end archive
    syswrite P, "\0" x 1024;
    $_tarlisted_wb += 1024;

    if ($_tarlisted_wb % 10240 != 0) {
	my $more = 10240 - $_tarlisted_wb % 10240;
	syswrite P, "\0" x $more;
	$_tarlisted_wb += $more;
    }
    close P or die;
}

my $endsub;
sub eval_end ($) {
    eval "\$endsub = sub { return if $$ != $pid; $_[0]; exit $? }";
    eval "END { &\$endsub(); }";
    $SIG{INT} = $endsub;
    $SIG{TERM} = $endsub;
    $SIG{HUP} = $endsub;
    $SIG{QUIT} = $endsub;
}
