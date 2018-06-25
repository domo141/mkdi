# -*- mode: cperl; cperl-indent-level: 4 -*-
# SPDX-License-Identifier: BSD-2-Clause
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#       Copyright (c) 2018 Tomi Ollila
#           All rights reserved
#
# Created: Sun 03 Jun 2018 20:17:21 EEST too
# Last modified: Mon 25 Jun 2018 22:35:09 +0300 too

# How to use:

# 1) BEGIN { require './mkdibuild.pm' }
#
# - when program is in run in same directory where this file is located
#
# 2) BEGIN { my $dn = $0; $dn =~ s|[^/]+$||; require $dn . 'mkdibuild.pm' }
#
# - when program loading this file is located in the same directory
#   as this file (easy to customize to other relative dirs)

use 5.10.1;
use strict;
use warnings;
use Digest::MD5;

# no 'package' call here (no experience, might be good, though)

#
# user settable variables in 'require'r code

our $mkdi_runcmd_hhmm = 1; # whether to sleep yymmdd.hhmm or sleep yymmdd
our $mkdi_datetag = 1; # whether to add additional :yyyymmdd-hhmmss tag
our $mkdi_dry_run = 0; # don't build when set, overrules force

our @default_cmd = qw'/bin/bash';
our @mkdi_dbr_opts = (); # extra docker build run options...

our $mkdi_pre_build_hook;

our $mkdi_created; # set if mkdi_build() created new image, zeroed if not

# end of (initially thought) user settable variables...
#

my (%_mkdi_digests, %_mkdi_names);
my $_mkdi_from = '';
my $_mkdi_dgst;

sub mkdi_init($$)
{
    die "Unknown version '$_[0]'; currently supported '1.0'\n"
        unless $_[0] == 1.0;

    my (%images, @images);
    open P, '-|', qw/docker images -qa --no-trunc -f dangling=false/
      or die "docker images: $!\n";
    while (<P>) {
        chomp;
        next if defined $images{$_};
        $images{$_} = 1;
        push @images, $_;
    }
    close P or die "docker images: exit $?\n";

    open P, '-|', qw/docker inspect --type image --format/,
#      '{{.Id}} {{.RepoTags}} {{index .ContainerConfig.Labels "mkdi-digest"}}',
#      '{{.Id}} {{.RepoTags}} {{index .Config.Labels "mkdi-digest"}}',
#      '{{.Id}} {{.RepoTags}} {{.Config.Labels}}', # still crashes...
      '{{.Id}} {{.RepoTags}} {{.Config}}',
      @images or die;
    while (<P>) {
        #warn " -- $_";
        next unless /^(\S+)\s+\[(.*?)\]\s+(.*?)\s*$/;
        my ($id, $tags, $digest) = ($1, $2, $3);
        $_mkdi_from = $_[1] if $id eq $_[1];
        if ($digest =~ /\bmkdi-digest:md5:([0-9a-f]{32})\b/) {
            $digest = $1;
        } else { $digest = 0 }
        #warn "\tid: $id\n\ttags: $tags\n\tdigest: $digest";
        my $lref = [ $id, $digest, $tags ]; # $lref->[2] not accessed so far...
        $_mkdi_digests{$digest} = $lref
          if $digest and not defined $_mkdi_digests{$digest};
        #warn "--- $tags $digest";# if $digest;
        foreach (split /\s+/, $tags) {
            $_mkdi_from = $_[1] if $_ eq $_[1];
            $_mkdi_names{$_} = $lref;
        }
    }
    #die "test exit $.";
    close P; # don't check exit value as $base may not be there
    die "Cannot find initial image '$_[1]'\n" unless $_mkdi_from;
    # in init mkdi_digest code w/ the id (sha256 hash) of the from image
    $_mkdi_dgst = $_mkdi_names{$_mkdi_from}->[0];
}

my @_mkdi_actions;

# works like "multi-stage" build, where results from one
# path can be copied to another...
#sub mkdi_from($) {  die 'not implemented yet'; }

# can be used e.g. in file to "force once" rebuild of particular image
sub mkdi_nop(@) { push @_mkdi_actions, [ 'nop', @_ ] }

# just the opposite to the above
sub mkdi_next_no_cksum(@) { push @_mkdi_actions, [ 'nocksum', @_ ] }

sub mkdi_file($$$)
{
    my $perm = ((oct $_[0]) - 1 & 0xffffff);
    die "Permissions $_[0] out of range\n" if $perm >= 07777;
    push @_mkdi_actions, [ 'file', @_ ]
}

sub mkdi_copy($$@)
{
    my $trg = pop @_;
    foreach (@_) {
        # at least at the time of check...
        die "'$_': no such file\n" unless -f $_;
        die "'$_': is unreadable\n" unless -r $_;
    }
    push @_mkdi_actions, [ 'copy', $trg, @_ ]
}

sub mkdi_run(@) { push @_mkdi_actions, [ 'run', @_ ] }

sub mkdi_cmd(@)        { push @_mkdi_actions, [ 'cmd',        @_ ] }
sub mkdi_entrypoint(@) { push @_mkdi_actions, [ 'entrypoint', @_ ] }
sub mkdi_env(@)        { push @_mkdi_actions, [ 'env',        @_ ] }
sub mkdi_expose($)     { push @_mkdi_actions, [ 'expose',     @_ ] }
sub mkdi_label(@)      { push @_mkdi_actions, [ 'label',      @_ ] }
sub mkdi_onbuild($)    { push @_mkdi_actions, [ 'onbuild',    @_ ] }
sub mkdi_user($)       { push @_mkdi_actions, [ 'user',       @_ ] }
sub mkdi_volume($)     { push @_mkdi_actions, [ 'volume',     @_ ] }
sub mkdi_workdir($)    { push @_mkdi_actions, [ 'workdir',    @_ ] }

sub mkdi_author($)  { push @_mkdi_actions, [ 'author', @_ ] }
sub mkdi_message($) { push @_mkdi_actions, [ 'message', @_ ] }

# no point resetting _mkdi_force after set (would break things)
my $_mkdi_force = 0;
sub mkdi_force() { $_mkdi_force = 1 }

# temporarily no recreation if named image exists
my $_mkdi_tmp_no_recreate = 0;
sub mkdi_tmp_no_recreate() { $_mkdi_tmp_no_recreate = 1 }

sub _mkdi_digest();
sub _mkdi_create($);
sub _mkdi_system0(@);
sub _mkdi_qsystem(@);

my %_mkdi_names_seen;
sub mkdi_build($)
{
    $mkdi_created = 0;
    die "Image '$_[0]' does not contain ':{tag}' suffix.\n" unless $_[0] =~ /:/;
    die "Image named '$_[0]' built already.\n"
      if defined $_mkdi_names_seen{$_[0]}; $_mkdi_names_seen{$_[0]} = 1;
    $_mkdi_dgst = _mkdi_digest;
    #warn "$_mkdi_dgst"; #exit 0;
    my $found = $_mkdi_force? 0: $_mkdi_digests{$_mkdi_dgst};

    if ($found) {
        print "Image $_[0], digest $_mkdi_dgst exists. Skipping build.\n";
        my $nfound = $_mkdi_names{$_[0]};
        unless (defined $nfound and $nfound == $found) {
            my $id = $found->[0];
            if ($mkdi_dry_run) {
                print "Would tag image $id as $_[0].\n";
            } else {
                _mkdi_system0 qw/docker tag/, $id, $_[0] and die $?;
            }
        }
        goto _done;
    }
    if ($_mkdi_tmp_no_recreate && defined $_mkdi_names{$_[0]}) {
        print "Image with name '$_[0]' exists.\n";
        print "Skipping creation on request (digest did not match)!\n";
        my $dgst = $_mkdi_names{$_[0]}->[1];
        if ($dgst) { $_mkdi_dgst = $dgst }
        else {
            $_mkdi_dgst = sprintf("%032x", (time));
            print "No former digest in '$_[0]':",
              " Next builds will be built unconditionally.\n";
        }
        goto _done;
    }
    if ($mkdi_dry_run) {
        my $f = $_mkdi_force? ' (force)': '';
        print "Would create new image $_[0]$f, digest $_mkdi_dgst.\n";
        goto _done;
    }
    if (defined $mkdi_pre_build_hook) {
        &$mkdi_pre_build_hook();
        undef $mkdi_pre_build_hook;
    }
    _mkdi_create $_[0];
    $mkdi_created = 1;

_done:
    @_mkdi_actions = ();
    $_mkdi_tmp_no_recreate = 0;
    $_mkdi_from = $_[0];
}

sub _mkdi_digest()
{
    my $ctx = Digest::MD5->new;
    $ctx->add($_mkdi_dgst); #warn $_mkdi_dgst;
    my $default_cmd = scalar @default_cmd;
    my $skip = 0;
    foreach (@_mkdi_actions) {
        $skip = 1, $_->[0] = 'nop', next if $_->[0] eq 'nocksum';
        $skip = 0, next if $skip;
        if ($_->[0] eq 'copy') {
            $ctx->add($_->[0]); $ctx->add($_->[1]);
            my @l = @{$_}; shift @l; shift @l;
            foreach (@l) {
                open I, '<', $_ or die "Opening '$_': $!\n";
                $ctx->addfile(*I);
                close I;
            }
            next;
        }
        $default_cmd = 0 if $_->[0] eq 'cmd' or $_->[0] eq 'entrypoint';
        # fallback for rest
        $ctx->add($_) foreach (@{$_});
    }
    if ($default_cmd) {
        $ctx->add('cmd'); $ctx->add($_) foreach (@default_cmd);
    }
    return $ctx->hexdigest;
}

my $_mkdi_wipname;
END {
    _mkdi_system0 qw/docker stop -t0/, $_mkdi_wipname if defined $_mkdi_wipname
}

sub _mkdi_create($)
{
    my @tm = localtime;
    my $todate = sprintf '%d%02d%02d', $tm[5] + 1900, $tm[4] + 1, $tm[3];
    $todate .= sprintf '.%02d%02d', $tm[2], $tm[1] if $mkdi_runcmd_hhmm;

    $_mkdi_wipname = 'wip-'.$_[0]; $_mkdi_wipname =~ tr/:/-/;
    _mkdi_qsystem qw/docker rm -f/, $_mkdi_wipname;
    _mkdi_system0 qw/docker run -d --name/, $_mkdi_wipname, @mkdi_dbr_opts,
      '--entrypoint=', $_mkdi_from, 'sleep', $todate;
      #'--entrypoint=sleep', $_mkdi_from, $todate;

    my @changes; push @changes, '-c', "LABEL mkdi-digest=md5:$_mkdi_dgst";
    local @default_cmd = @default_cmd;

    my ($cmd, $entrypoint, $user, $workdir, $onbuild, $author, $message)
      = ('') x 7;

    sub _enla(@) {
        my $enla = (shift)? 'LABEL': 'ENV';
        # modifies args. fine.
        s/\\/\\\\/g, s/"/\\"/g foreach (@_);
        my $key = shift;
        return "$enla $key=\"@_\"";
    }

    sub _jl(@) {
        # modifies args. fine.
        s/\\/\\\\/g, s/"/\\"/g, $_ = qq'"$_"' foreach (@_);
        my $rv = '[' . join(',', @_) . ']';
        @default_cmd = ();
        return $rv;
    }

    foreach (@_mkdi_actions) {
        my $op = shift @{$_};
        #warn $op;
        if ($op eq 'file') {
            open P, '|-', qw/docker exec -i/, $_mkdi_wipname, '/bin/sh', '-ec',
              '/bin/cat > "$1"; exec /bin/chmod "$0" "$1"', $_->[0], $_->[1]
              or die $!;
            print P $_->[2];
            close P or die $!;
            next;
        }
        if ($op eq 'run') {
            _mkdi_system0 qw/docker exec -t/, $_mkdi_wipname, @{$_};
            die if $?;
            next;
        }
        if ($op eq 'copy') {
            my $dest = $_mkdi_wipname.':'.shift @{$_};
            _mkdi_system0 qw/docker cp/, @{$_}, $dest;
            die if $?;
            next;
        }
        # we could use language constructs to combine these, but good enough...
        if ($op eq 'env')    { push @changes, '-c', _enla(0, @$_);    next; }
        if ($op eq 'expose') { push @changes, '-c', "EXPOSE $_->[0]"; next; }
        if ($op eq 'label')  { push @changes, '-c', _enla(1, @$_);    next; }
        if ($op eq 'volume') { push @changes, '-c', "VOLUME $_->[0]"; next; }

        if ($op eq 'cmd')        { $cmd        = _jl(@$_); next; }
        if ($op eq 'entrypoint') { $entrypoint = _jl(@$_); next; }
        if ($op eq 'user')       { $user       = $_->[0];  next; }
        if ($op eq 'workdir')    { $workdir    = $_->[0];  next; }
        if ($op eq 'onbuild')    { $onbuild    = $_->[0];  next; }

        if ($op eq 'author')  { $author  = $_->[0]; next; }
        if ($op eq 'message') { $message = $_->[0]; next; }
        if ($op eq 'nop') { next; }
        die "unknown action $op";
    }
    push @changes, '-c', 'CMD '       . $cmd        if $cmd ne '';
    push @changes, '-c', 'ENTRYPOINT '. $entrypoint if $entrypoint ne '';
    push @changes, '-c', 'USER '      . $user       if $user ne '';
    push @changes, '-c', 'WORKDIR '   . $workdir    if $workdir ne '';
    push @changes, '-c', 'ONBUILD '   . $onbuild    if $onbuild ne '';

    push @changes, '-c', 'CMD ' . _jl(@default_cmd) if @default_cmd;

    push @changes, '-a', $author  if $author ne '';
    push @changes, '-m', $message if $message ne '';

    _mkdi_system0 qw/docker commit/, @changes, $_mkdi_wipname, $_[0];
    die if $?;
    if ($mkdi_datetag) {
        my $totime = sprintf '%02d%02d%02d', $tm[2], $tm[1], $tm[0];
        my $b = $_[0]; $b =~ s/:.*//;
        $todate =~ s/[.].*//;
        _mkdi_system0 qw/docker tag/, $_[0], "$b:$todate-$totime";
    }
    _mkdi_system0 qw/docker rm -f/, $_mkdi_wipname;
    die if $?;
    undef $_mkdi_wipname;
    _mkdi_system0 qw/docker history/, $_[0];
}

sub _mkdi_system0(@) {
    print "Executing: @_\n";
    return unless system @_;
    my @c = caller; die "Died at $c[1] line $c[2].\n";
}

sub _mkdi_xfork_parent_waits()
{
    my $pid = fork;
    die 'fork:' unless defined $pid;
    wait if $pid;
    return $pid;
}

sub _mkdi_qsystem(@) {
    return if _mkdi_xfork_parent_waits;
    open STDOUT, '>', '/dev/null';
    open STDERR, '>&', \*STDOUT;
    exec @_;
    die 'not reached';
}

1
