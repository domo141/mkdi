#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ initti.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2016 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 22 Aug 2016 21:51:52 EEST too
# Last modified: Sat 01 Oct 2016 01:16:12 +0300 too

# In case of backup/restore, kill -STOP this, then child processes.

use 5.8.1;
use strict;
use warnings;

#$ENV{'PATH'} = '/sbin:/usr/sbin:/bin:/usr/bin';

die "My pid '$$' is not '1'.\n" unless $$ == 1;
chdir '/';

my $smtpdpid = 0;
my $psqlpid = 0;
my $mmpid = 0;
my $nginxpid = 0;
my $dailypid = 0;

sub get_user($)
{
    my @user = getpwnam $_[0];
    die "Cannot find user '$_[0]': $!\n" unless @user;
    return $user[2];
}
my $user_postgres = get_user 'postgres';
my $user_mattermost = get_user 'mattermost';

sub run_cmd($$@)
{
    my $pid = fork;
    return $pid if $pid > 0;
    die "fork: $!\n" if $pid < 0;
    # child #
    my $user = shift;
    my $pwd = shift;
    chdir $pwd if $pwd;
    if ($user) {
#	$( = $) = "$user $user 108"; # FIXME 108 == ssl-cert (qx/id/ & parse ?)
	$( = $) = "$user $user 109"; # FIXME 109 == ssl-cert (qx/id/ & parse ?)
	$< = $> = $user;
    }
    exec @_;
    die 'not reached'
}

sub run_daily()
{
    $dailypid = run_cmd 0, '', '/usr/local/sbin/daily.sh';
}


my (@psql, $psql_pwd);
{
    my $PGV = '9.4';
    # qw// with variable interpolation...
    @psql = eval "qw[/usr/lib/postgresql/$PGV/bin/postgres
		     -D /var/lib/postgresql/$PGV/main
		     --config-file=/etc/postgresql/$PGV/main/postgresql.conf]";
    $psql_pwd = "/var/lib/postgresql/$PGV/main";
}
sub run_psql()
{
    $psqlpid = run_cmd $user_postgres, $psql_pwd, @psql;
}

sub run_mattermost()
{
    $mmpid = run_cmd $user_mattermost, '/opt/mattermost',
      '/opt/mattermost/bin/platform';
}

sub run_nginx()
{
    $nginxpid = run_cmd 0, '',
      qw[/usr/sbin/nginx -g], 'daemon off; master_process on;'
}

# "smtpd" implemented at the end of this file
sub run_smtpd();

$SIG{TERM} = \&sigterm;
sub sigterm
{
    $SIG{TERM} = 'IGNORE';
    kill 'TERM', -1;
    sleep 1;
    exit 0;
}
$SIG{HUP} = $SIG{INT} = sub { warn "Stopping...\n"; sigterm(); };

$| = 1;
print "Starting $0\n";

run_smtpd;
run_psql;
run_mattermost;
run_nginx;
run_daily;

while (1)
{
    for (1..3) {
	my $pid = wait;
	last if $pid < 0; # last for, next while after sleep

	run_daily if $pid == $dailypid;
	run_psql if $pid == $psqlpid;
	run_mattermost if $pid == $mmpid;
	run_nginx if $pid == $nginxpid;
	run_smtpd if $pid == $smtpdpid;
    }
    sleep 1;
}

die 'not reached';

use Socket;
use POSIX ":sys_wait_h";

sub run_smtpd()
{
    $smtpdpid = fork;
    return if $smtpdpid > 0;
    die "fork: $!\n" if $smtpdpid < 0;
    # child #

    print "Starting embedded smtpd: pid $$\n";
    $0 = 'smtpd';
    mkdir '/var/mail/incoming', 0755;
    chdir '/var/mail/incoming' or die "smtpd chdir failed: $!\n";

    # note: could drop privileges...

    socket SS, AF_INET, SOCK_STREAM, 0 or die "socket: $!\n";

    setsockopt(SS, SOL_SOCKET, SO_REUSEADDR, 1);

    bind(SS, pack_sockaddr_in(25, inet_aton('127.0.0.1')))
      or die "Cannot bind to port 25: $!\n";

    listen(SS, 5) or die "listen: $!\n";

    $SIG{CHLD} = sub() { waitpid(-1, WNOHANG); };

    while (1) {
	if (accept(S, SS)) {
	    my $pid = fork;
	    die "fork() failed: $!\n" if $pid < 0;
	    if ($pid > 0) {
		close S;
		next;
	    }
	    # child
	    close SS;
	    # fall to 'srand'
	    last;
	}
	else {
	    next if $!{EINTR};
	    die "accept() failed unexpectly: $!\n";
	}
    }

    srand;
    alarm 30;

    select S;
    $| = 1;

    # w/ our writetofile() works, perhaps not the righest, but...
    our $maxsize = 1024 * 1024;
    our $size = 0;

    print "220 127.0.0.1 ESMTP spoken here\r\n";
    while (<S>) {
	if (/^HELO\s+(\S+)/i) {
	    print "250 Hello $1, go ahead\r\n";
	    last;
	}
	if (/^EHLO\s+(\S+)/i) {
	    print "250-127.0.0.1 Hello $1 [127.0.0.1]\r\n";
	    print "250 SIZE $maxsize\r\n";
	    last;
	}
	if (/^QUIT/i) {
	    print "221 Bye\r\n";
	    exit 0;
	}
	print "503 Error: need HELO or EHLO with content\r\n";
    }
    exit 0 unless $_;

    my $time = time;
    my $rand = int(rand 9999);
    {
	my @tm = localtime $time;
	my $filename = sprintf '%d%02d%02d-%02d%02d%02d.%05d-%04d',
	  $tm[5] + 1900, $tm[4] + 1, $tm[3], $tm[2], $tm[1], $tm[0], $$, $rand;
	open F, '>', $filename or die "Opening '$filename': $!\n";
    }
    sub writetofile() # note: nested named subroutine; perhaps not supported...
    {
	$size += length;
	if ($size >= $maxsize) {
	    print F "523 Error: message too large\r\n";
	    print "523 Error: message too large\r\n";
	    exit 0;
	}
	print F $_;
    }
    writetofile;

    my ($sndr, $rcpt) = (0, 0);
    while (<S>) {
	writetofile;
	if (/^MAIL FROM:/i) {
	    print "250 Ok\r\n";
	    $sndr = 1;
	    next;
	}
	if (/^RCPT TO:/i) {
	    print "250 Ok\r\n";
	    $rcpt = 1;
	    next;
	}
	if (/^DATA\b/i) {
	    unless ($rcpt) {
		print "503 Error: need RCPT TO command\r\n";
		next;
	    }
	    unless ($sndr) {
		print "503 Error: need MAIL FROM command\r\n";
		next;
	    }
	    last;
	}
	if (/^QUIT\b/i) {
	    print "221 Bye\r\n";
	    exit 0;
	}
	print "502 Error: command not recognized\r\n";
    }
    exit 0 unless $_;

    print "354 End data with <CR><LF>.<CR><LF>\r\n";

    while (<S>) {
	writetofile;
	last if /^[.]\s*$/;
    }
    exit 0 unless $_;

    printf "250 Ok: queued as %08X\r\n", $time * 65536 + $rand;
    close F;

    while (<S>) {
	if (/^QUIT\b/i) {
	    print "221 Bye\r\n";
	    exit 0;
	}
	print "502 Error: command not recognized\r\n";
    }
    exit 0;
}
