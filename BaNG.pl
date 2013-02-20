#!/usr/bin/perl
#
# copyright 2013 Patrick Schmid <schmid@phys.ethz.ch>, distributed under
# the terms of the GNU General Public License version 2 or any later
# version.
#
# This is compiled with threading support
#
# 2013.02.20, Patrick Schmid <schmid@phys.ethz.ch>
use strict;
use warnings;
use Getopt::Long;

my $help            = 0;
my $debug           = 1;
my ($cfg_group, $bulk_type, $target_host, $nis_group) = ('') x 4;
my $nthreads        = 1;


#################################
# Get/Check command options
#
GetOptions (
    "h"     => \$help,
    "d"     => \$debug,
    "g=s"   => \$cfg_group,
    "b=s"   => \$bulk_type,
    "s=s"   => \$target_host,
    "n=s"   => \$nis_group,
    "th=i"  => \$nthreads,
)
    or usage("Invalid commmand line options.");

    usage("You must provide some arguments") unless ($target_host || $bulk_type || $nis_group);

    if (( $target_host and $bulk_type ) || ( $target_host and $nis_group ) || ( $bulk_type and $nis_group )){
        usage("Don't mix the mode options (-s/-b/-n)!");
    }

    if ( $target_host ){
        usage("The option -g is not defined!")
            unless $cfg_group;
    }

    if ( $bulk_type ){
        usage("The option -g is not defined!")
            unless (($bulk_type eq "ALL") or $cfg_group);
    }



##############
# Usage
#
sub usage {
    my ($message) = @_;

    if (defined $message && length $message) {
        $message .= "\n\n"
            unless $message =~ /\n$/;
    }

    my $command = $0;
    $command    =~ s#^.*/##;

    print STDERR (
        $message,
       "usage: $command [-h|-v]
        usage: $command [-d] -s <hostname> -g <group> -[-th <nr>]
        usage: $command [-d] -b Server|Workstation -g <group> [-th <nr>]
        usage: $command [-d] -b All [-th <nr>]
        usage: $command [-d] -n <nisgroup> [-th <nr>]

        Options:

          -b <typ>           bulk backup
              All            backup every host where enabled
              Server         backup only the enabled servers
              Workstation    backup only the enabled workstations

          -s <hostname>      single host backup
          -g <group>         select group for backup, e.g. *_homes.yaml, *_groupdata.yaml, your choice!
              system         backup *_system.yaml (preserved for System-Backups)

          -n <nisgroup>      backup-list from NIS (e.g. astro > auto.astro)
                             Hint: for activation of nis-clients, you must create
                                   a folder with the name of the host
                             example: mkdir /export/backup/data/workstations/<hostname>

          -th                Number of threads, default: 1

          -d                 show debugging messages

          -h                 show this
      \n"
    );
    exit 0;
}
