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
use Data::Dumper;
use BaNG::Hosts;
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
my $debuglevel      = 2;        #1 normal output, 2 ultimate output, 3 + rsync verbose!

my ($help, $showversion) = ('') x 2;
my ($group, $host) = ('') x 2;
my $nthreads        = 1;
my $wipe            = 0;

my $conn_status     = 0;
my $conn_msg        = '';

#################################
# Get/Check command options
#
GetOptions (
    "help"         => sub { usage('') },
    "v|version"    => \$showversion,
    "d|debug"      => \$debug,
    "g|group=s"    => \$group,
    "h|host=s"     => \$host,
    "t|threads=i"  => \$nthreads,
    "w|wipe"       => \$wipe,
)
    or usage("Invalid commmand line options.");
    usage("Current version number: $version")   if ( $showversion );
    usage("You must provide some arguments")    unless ($host || $group || $showversion);
    usage("Number of threads must be positive") unless ($nthreads && $nthreads > 0);


#################################
# Get the configuration
#
get_global_config();
find_hosts($host, $group);
eval_rsync_options($host,$group);

($conn_status, $conn_msg ) = chkClientConn($host, $hosts{"$host-$group"}->{hostconfig}->{BKP_GWHOST});
print "chkClientConn: $conn_status, $conn_msg\n" if $debug;

sub eval_rsync_options {
    my ($host, $group) = @_;
    my $rsync_options  = '';
    my $hostconfig = $hosts{"$host-$group"}->{hostconfig};

    $rsync_options .= "-ax "            if $hostconfig->{BKP_RSYNC_ARCHIV};
    $rsync_options .= "-R "             if $hostconfig->{BKP_RSYNC_RELATIV};
    $rsync_options .= "-H "             if $hostconfig->{BKP_RSYNC_HLINKS};
    $rsync_options .= "--delete "       if $hostconfig->{BKP_RSYNC_DELETE};
    $rsync_options .= "--force "        if $hostconfig->{BKP_RSYNC_DELETE_FORCE};
    $rsync_options .= "--numeric-ids "  if $hostconfig->{BKP_RSYNC_NUM_IDS};
    $rsync_options .= "--inplace "      if $hostconfig->{BKP_RSYNC_INPLACE};
    $rsync_options .= "--acls "         if $hostconfig->{BKP_RSYNC_ACL};
    $rsync_options .= "--xattrs "       if $hostconfig->{BKP_RSYNC_XATTRS};
    $rsync_options .= "--no-D "         if $hostconfig->{BKP_RSYNC_OSX};
    $rsync_options .= "-v "             if ($debug && ($debuglevel == 3));

    if ($hostconfig->{BKP_RSYNC_RSHELL}){
        if ($hostconfig->{BKP_GWHOST}){
            $rsync_options .= "-e $hostconfig->{BKP_RSYNC_RSHELL} $hostconfig->{BKP_GWHOST} ";
        } else {
            $rsync_options .= "-e $hostconfig->{BKP_RSYNC_RSHELL} ";
        }
    }
    if ($hostconfig->{BKP_RSYNC_RSHELL_PATH}){
        $rsync_options .= "--rsync-path=$hostconfig->{BKP_RSYNC_RSHELL_PATH} ";
    }
    if ($hostconfig->{BKP_EXCLUDE_FILE}){
        $rsync_options .= "--exclude-from=$config_path/$hostconfig->{BKP_EXCLUDE_FILE} ";
    }

    $rsync_options =~ s/\s+$//; # remove trailing space
    print "Rsync Options: $rsync_options\n" if $debug;

    return $rsync_options;
}

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
