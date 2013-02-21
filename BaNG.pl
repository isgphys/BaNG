#!/usr/bin/perl
#
# copyright 2013 Patrick Schmid <schmid@phys.ethz.ch>, distributed under
# the terms of the GNU General Public License version 2 or any later
# version.
#
# This is compiled with threading support
#
# 2013.02.20, Patrick Schmid <schmid@phys.ethz.ch> & Claude Becker <becker@phys.ethz.ch>
#
use strict;
use warnings;
use Getopt::Long qw(:config no_auto_abbrev);
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

my $version         = '3.0';
my $debug           = 1;
my ($help, $showversion) = ('') x 2;
my ($cfg_group, $bulk_type, $target_host) = ('') x 3;
my $nthreads        = 1;
my $wipe            = 0;


#################################
# Get/Check command options
#
GetOptions (
    "help"         => sub { usage('') },
    "v|version"    => \$showversion,
    "d|debug"      => \$debug,
    "g|group=s"    => \$cfg_group,
    "h|host=s"     => \$target_host,
    "t|threads=i"  => \$nthreads,
    "w|wipe"       => \$wipe,
)
    or usage("Invalid commmand line options.");
    usage("Current version number: $version")   if ( $showversion );
    usage("You must provide some arguments")    unless ($target_host || $cfg_group || $showversion);
    usage("Number of threads must be positive") unless ($nthreads && $nthreads > 0);


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

        $command -h <hostname> -g <group>   # back up given host and group
        $command -h <hostname>              # back up all groups of given host
        $command -g <group>                 # back up all hosts of given group
        $command -v                         # show version number
        $command --help                     # show this help message

        Optional Arguments:

        -t <nr>         # number of threads, default: 1
        -w              # wipe the backup
        -d              # show debugging messages
    \n)
    );
    exit 0;
}
