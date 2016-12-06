package BaNG::TM_tar;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BackupServer;

use Exporter 'import';
our @EXPORT = qw(
    execute_tar
);

sub _eval_tar_options {
    my ($host, $group, $taskid) = @_;
    my $tar_options ='';
#   my $hostconfig    = $hosts{"$host-$group"}->{hostconfig};

    my $tar_helper = _create_tar_helper();
    logit( $taskid, $host, $group, "tar helper script $tar_helper created" );

    $tar_options .= "-ML 25G -b 1024 -F $tar_helper";

    return $tar_options;
}

sub _eval_tar_target {
    my ( $host, $group ) = @_;
    my $tar_target = targetpath( $host, $group );

    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
        $tar_target .= '/current';
    } else {
        $tar_target .= "/snap_LTS";
    }

    return $tar_target;
}

sub _create_tar_helper {

    my $tar_helper_path = "$prefix/var/tmp";
    if ( ! -e $tar_helper_path ) {
        print "Create missing tmp folder: $tar_helper_path\n" if $serverconfig{verbose};
        mkdir -p $tar_helper_path unless $serverconfig{dryrun};
    }

    my $tar_helper = "$tar_helper_path/tar_helper.sh";

    print "Create tar helper script $tar_helper\n";

    return $tar_helper;
}

sub execute_tar {
    my ( $taskid, $host, $group ) = @_;
    my $hostconfig  = $hosts{"$host-$group"}->{hostconfig};

    my $startstamp = time();

    my $tar_options = _eval_tar_options( $host, $group, $taskid );
    my $tar_target  = _eval_tar_target( $host, $group);

    my $tar_cmd  = $serverconfig{path_tar};

    my $DESTPATH="/Folder_X.tar";
    my $path = "kommt noch";

    print "$taskid, $host, $group, Tar Command: $tar_cmd $tar_options -cf $path $tar_target\n" ;
    print "$taskid, $host, $group, Executing tar for host $host group $group\n";
}

1;
