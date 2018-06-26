#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ mkdi-example.pl $
# SPDX-License-Identifier: Unlicense

use 5.10.1;
use strict;
use warnings;

BEGIN { require './mkdibuild.pm' }

# show defaults in outcommented examples
# ''''''''''''''''''''''''''''''''''''''
#$::mkdi_datetag = 1;
#$::mkdi_runcmd_hhmm = 1;
#$::mkdi_dry_run = 0;

#@::default_cmd = qw'/bin/bash'; # if no cmd/entrypoint given.
#@::default_cmd = (); # would disable the feature. sleeps then.

#@::mkdi_dbr_opts = (); # docker build run options. careful!
#@::mkdi_dbr_opts = qw[--privileged -v.:/mnt]; # one example

#

die "Usage: $0 'dry|mk'\n" unless @ARGV == 1;
if ($ARGV[0] eq 'dry') { $::mkdi_dry_run = 1 }
elsif ($ARGV[0] ne 'mk') { die "'$ARGV[0]' not 'dry' nor 'mk'\n" }

my @built_images_if_tracked;
# redifing function for demonstration purposes -- just that this example
# uses mkdi_build; real use should just write a wrapper function and call
# it... here mkdi_build is "wrapped" for summary at end.
my $mkdi_build; BEGIN { $mkdi_build = \&mkdi_build }
sub mkdi_build($) # expect perl warning
{
    $mkdi_build->($_[0]);
    push @built_images_if_tracked, $_[0] if $::mkdi_created;
}


mkdi_init 1, 'debian:9-slim', 'docker.io/debian:9-slim';
#mkdi_init 1, 'docker.io/debian:9';
#mkdi_init 1, 'docker.io/debian:8.6';

mkdi_run '/bin/sh', '-xeufc', <<'EOF';
# Locale is set in a way that it is both debian and ubuntu compatible
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y -q locales
if test -f /etc/locale.gen
then    sed -i '/en_IE.UTF-8/ s/^. *//' /etc/locale.gen
fi
locale-gen en_IE.UTF-8
echo 'LANG="en_IE.UTF-8"' > /etc/default/locale

apt-get -y autoremove
apt-get -y clean
rm -rf /var/lib/apt/lists/
EOF

mkdi_env qw/LANG en_IE.UTF-8/;
mkdi_env qw/LC_ALL en_IE.UTF-8/;

mkdi_tmp_no_recreate; # during dev sometimes useful temporary measure...
mkdi_build 'mkdi-example:inet-access';
##########
print "$0:", __LINE__, ": created: $::mkdi_created\n";

#mkdi_file depends 'sh, 'cat' and 'chmod'. currently limited write success chk
mkdi_file 755, '/usr/bin/exec-as-user', <<'EOF';
#!/usr/bin/perl
#use strict;
#use warnings;

die "Usage: $0 user command [args...]\n" unless @ARGV >= 2;

my $user = shift;
my @user = getpwnam $user;
die "Failed to read user '$user' pw entry: $!\n" unless @user;

if ($ARGV[0] eq '.') { shift }
else { chdir $user[7] or warn "Cannot chdir to '$user[7]': $!\n" }
$ENV{HOME} = $user[7];
$ENV{USER} = $user;
$! = 0;
$( = $) = "$user[3] $user[3] 0";
$< = $> = $user[2]; die "Setting user '$user' uids/gids: $!\n" if $!;
exec @ARGV
EOF

# qw// works with mkdi_run as its prototype is (@)...
mkdi_run qw(useradd -m -k /dev/null user);

# all options for demonstration purposes

my $home = '/home/user';

mkdi_copy $0, $home;

mkdi_author 'Arttu T. Luupihvi <atk@example.org>';
mkdi_message 'what is not done cannot be undone';

my $day = '20180614';
mkdi_env 'IMAGE', "mkdi-example:$day";

mkdi_entrypoint '/bin/bash';
mkdi_cmd qw/-i -t/;

mkdi_user 'user';
mkdi_workdir $home;

mkdi_volume '/opt';

# look dox what this really mean...
mkdi_expose '8080';

mkdi_next_no_cksum; # careful!
mkdi_label 'mkdi-example', scalar localtime;

# no idea if this works...
mkdi_onbuild 'RUN ["echo", "are we having fun yet?"]';

mkdi_build 'mkdi-example:changes';
##########
print "$0:", __LINE__, ": created: $::mkdi_created\n";

# Note: using same 'repository' part in image name at least
#       not common, and may be confusing. Here it is just
#       to have less names in output...

mkdi_copy 'mkdibuild.pm', '/root/';

mkdi_run 'env';
mkdi_run qw'ls -l /proc';
#mkdi_run qw/suid-me-harder ls -l root/;
mkdi_run 'perl', '-ple', 's/\0/ /', '/proc/1/cmdline';
mkdi_run 'id';
mkdi_run 'pwd';

mkdi_entrypoint '/bin/bash';

#mkdi_env qw/TEST docker inspect/; # would do exactly the same as next line
mkdi_env 'TEST', 'docker inspect';
mkdi_force; # all following builds will be (re)done
mkdi_build 'mkdi-example:latest';
##########
print "$0:", __LINE__, ": created: $::mkdi_created\n";

print "\n";
print ": run; sudo docker inspect $_\n     : sudo docker run --rm -it $_\n"
  foreach @built_images_if_tracked;;
