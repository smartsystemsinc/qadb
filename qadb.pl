#!/usr/bin/env perl

# Quick and Dirty Backup by Cory <cory@smartsystemsaz.com>
# Designed for use on Ubuntu for quick, CYA backups

# TODO: Investigate this
# Linux, and all Unix machines, use hard links extensively, so make 100% sure
# you maintain link integrity. Rsync for instance, needs the special flag
# --hard-links, even when you've also specified --archive (as the man page
# says, --archive still lacks --hard-links, --acls and --xattrs).
# http://www.halfgaar.net/backing-up-unix
# Would need -H (hard links), -A (ACLS and permissions), -X (extended attributes)

use warnings;
use strict;
use Carp;
use English qw(-no_match_vars);
use File::Basename;
use POSIX qw(strftime);    # Built-in

# Variables and usage
our $VERSION = 0.2;
my $source = $ARGV[0]             or usage();
my $dest   = $ARGV[1]             or usage();
my $name   = basename( $ARGV[2] ) or usage();
my $datetime = strftime '%Y-%m-%d', localtime;
my $log      = "$dest\/$name-transfer-$datetime";
my $rsync    = 'rsync --archive --checksum --verbose';
my $tree     = 'tree -i -f --du -h';
my @initerr;
my @redunerr;
my $count = 0;

sub usage {
    croak
        "Usage: $PROGRAM_NAME <source> <dest> <log_filename>\nLog file will go into the destination directory\n";
}

# Check to see if rsync and tree exist and get them if not
# The 'and' is not a typo; perl's system() reverses the normal logic

if ( `which rsync` eq q{} ) {
    print "rsync not found. Attempting to install.\n" or croak $ERRNO;
    system 'sudo apt-get install rsync --yes' and croak $ERRNO;
}

if ( `which tree` eq q{} ) {
    print "tree not found. Attempting to install.\n" or croak $ERRNO;
    system 'sudo add-apt-repository universe && sudo apt-get update'
        and croak $ERRNO;
    system 'sudo apt-get install tree --yes' and croak $ERRNO;
}

# Make sure the destination directory is there
system "mkdir -p \"$dest\"" and croak $ERRNO;

# Open pipe to STDOUT and use tee(1) to write to it and the log file
no warnings;    # Stops warning about "potential typo"
open *SAVEOUT, '>&', '*STDOUT'
    or croak("Couldn't create new STDOUT\n")
    ;           # * (typeglob) is needed here for barewords to avoid ambiguity
use warnings;
open STDOUT, qw{|-}, 'tee', $log or croak "tee failed: $ERRNO";

# Get source tree output
print "### Source Tree\n" or croak $ERRNO;
system "$tree \"$source\"";
print "\n" or croak $ERRNO;

# Get initial rsync output
print "### Initial Rsync Output\n" or croak $ERRNO;
system "$rsync \"$source\" \"$dest\" 2>&1";
my $rsync_status_initial_return = $CHILD_ERROR >> 8;
my $rsync_status_initial_error  = $ERRNO;
open my $LOG, '<', "$log" or croak $ERRNO;
while ( my $line = <$LOG> ) {
    if ( $line =~ /### Initial Rsync Output/xms .. $line
        =~ /### Redundant Rsync Output/xms )
    {
        if ( $line =~ /rsync.*:/xms ) {
            push @initerr, $line;
        }
    }
}
close $LOG or croak $ERRNO;
print "\n" or croak $ERRNO;

LOOP:
$count = $count + 1;
if ( $count > 5 ) { goto DONE; }

# Get redundant rsync output as a sanity check
print "### Redundant Rsync Output $count\n" or croak $ERRNO;

system "$rsync \"$source\" \"$dest\" 2>&1";
my $rsync_status_redundant_return = $ERRNO >> 8;
my $rsync_status_redundant_error  = $ERRNO;
open $LOG, '<', "$log" or croak $ERRNO;
while ( my $line = <$LOG> ) {
    if ( $line =~ /### Redundant Rsync Output $count/xms .. $line
        =~ /### Destination Tree/xms )
    {
        if ( $line =~ /rsync.*:/xms ) {
            push @redunerr, $line;
        }
    }
}
close $LOG or croak $ERRNO;
print "\n" or croak $ERRNO;

# Sanity check and final output
if (   $rsync_status_initial_return ne '0'
    || $rsync_status_redundant_return ne '0' )
{
    print "\nrsync reported issues. Check $log for more details\n\n"
        or croak $ERRNO;
    if ( $count == 2 ) {
        print "Initial rsync error code: $rsync_status_initial_return\n"
            or croak $ERRNO;
        print "Initial rsync error message: $rsync_status_initial_error\n"
            or croak $ERRNO;
    }
    print "Redundant rsync error code: $rsync_status_redundant_return\n"
        or croak $ERRNO;
    print "Redundant rsync error message: $rsync_status_redundant_error\n\n"
        or croak $ERRNO;
    if ( $count == 2 ) {
        print "Initial rsync errors:\n @initerr\n" or croak $ERRNO;
    }
    print "Redundant rsync errors:\n @redunerr\n" or croak $ERRNO;
    goto LOOP;
}

DONE:

if ( $count >= 2 ) {
    my $attempts = $count - 1;
    print
        "Made $attempts additional attempt(s) at copying data; data should be intact\n"
        or croak $ERRNO;
}
if ( $count == 5 ) {
    print "Maximum number of attempts reached; some data may be corrupt\n"
        or croak $ERRNO;
}

# Get destination tree output
print "### Destination Tree\n" or croak $ERRNO;
system "$tree \"$dest\"";

# Reset STDOUT
open *STDOUT, '>&', '*SAVEOUT'
    or croak("Couldn't reset STDOUT\n")
    ;    # * (typeglob) is needed here for barewords to avoid ambiguity

if (   $rsync_status_initial_return eq '0'
    && $rsync_status_redundant_return eq '0' )
{
    print "\nBackup completed successfully\n" or croak $ERRNO;
}

# Compress and remove the log, junking the path
system "zip -j \"$dest\"\/\"$name-$datetime\".zip \"$log\" && rm \"$log\"";

# (c) 2015 SmartSystems, Inc.
 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
