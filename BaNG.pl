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
use Cwd 'abs_path';
use File::Basename;
use lib dirname(abs_path($0))."/lib";

use BaNG::Config;
our %globalconfig;
our %defaultconfig;
our %hosts;
our $servername;
our $prefix;
our $config_path;
our $config_global;

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
    "s=s"   => \$target_host,
    "n=s"   => \$nis_group,
    "th=i"  => \$nthreads,
)
    or usage("Invalid commmand line options.");
    usage("You must provide some arguments")    unless ($target_host || $cfg_group || $nis_group);
    usage("Number of threads must be positive") unless ($nthreads && $nthreads > 0);
    usage("Don't mix the mode options")         if ( $target_host and $nis_group );


#################################
# Get the global variables
#
get_global_config();



##############
# Usage
#
sub usage {
    my ($message) = @_;

    if (defined $message && length $message) {
        $message .= "\n"
            unless $message =~ /\n$/;
    }

    my $command = $0;
    $command    =~ s#^.*/##;

    print STDERR (
        $message, qq(
        Usage Examples:

        $command -s <hostname> -g <group>   # back up given host and group
        $command -s <hostname>              # back up all groups of given host
        $command -g <group>                 # back up all hosts of given group
        $command -n <nisgroup>              # back up all paths defined by NIS group
        $command -v                         # show version number
        $command -h                         # show this help message

        Optional Arguments:

        -th <nr>        # number of threads, default: 1
        -d              # show debugging messages

        Note: for activation of nis-clients, you must create a folder with the name of the host
        example: mkdir /export/backup/data/workstations/<hostname>
    \n)
    );
    exit 0;
}
