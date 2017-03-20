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
    my $tar_options = '';
    my $tar_helper  = _create_tar_helper();

    logit( $taskid, $host, $group, "tar helper script $tar_helper created" );

    $tar_options .= "-ML 25G -b 1024 -F $tar_helper";

    return ($tar_options, $tar_helper);
}

sub _eval_tar_source {
    my ( $host, $group ) = @_;
    my $tar_source = targetpath( $host, $group );

    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
        $tar_source .= '/current';
    } else {
        $tar_source .= "/snap_LTS";
    }

    return $tar_source;
}

sub _create_tar_helper {

    my $tar_helper_path = "$prefix/var/tmp";
    if ( ! -e $tar_helper_path ) {
        print "Create missing tmp folder: $tar_helper_path\n" if $serverconfig{verbose};
        mkdir -p $tar_helper_path unless $serverconfig{dryrun};
    }

    my $tar_helper = "$tar_helper_path/tar_helper.sh";

    my $script_content = <<"EOF";

#!/bin/bash
# BaNG tar_helper script
# Created by BaNG, do not manually edit this script!

echo \$TAR_VERSION \$TAR_ARCHIVE \$TAR_VOLUME \$TAR_BLOCKING_FACTOR \$TAR_FD \$TAR_SUBCOMMAND \$TAR_FORMAT

echo "Rotate to \$TAR_VOLUME"
mv "\$TAR_ARCHIVE" "\$TAR_ARCHIVE-\$TAR_VOLUME"
# tar_helper end
EOF
    unless ( $serverconfig{dryrun} ) {
        open HELPERFILE, '>', $tar_helper;
        print HELPERFILE $script_content;
        close HELPERFILE;
    }
    print "Create tar helper script: $tar_helper\n$script_content\n" if $serverconfig{verbose};

    return $tar_helper;
}

sub _delete_tar_helper {
    my ($tar_helper) = @_;

    print "check if tar helper script $tar_helper exists\n" if $serverconfig{verbose};

    if ( -e "$tar_helper" ){
        unlink  "$tar_helper";
        print "Deleted tar helper script $tar_helper\n" if $serverconfig{verbose};
    }
}

sub _setup_tar_target {
    my ( $host, $group, $hostconfig, $taskid ) = @_;

    my $nfs_share         = "lts11.ethz.ch:/shares/phys_lts_nfs";
    my $nfs_mount_options = "noauto,hard,intr,retrans=10,timeo=300,rsize=65536,wsize=1048576,vers=3,proto=tcp,sync";
    my $tar_target        = "/mnt/LTS/lts-11";

    if (`cat /proc/mounts | grep $tar_target`) {
        print "$taskid, $host, $group, $tar_target is mounted \n" if $serverconfig{verbose};
    } else {
        print "$taskid, $host, $group, $tar_target is not mounted \n" if $serverconfig{verbose};
        my $result = system("mount -t nfs -o $nfs_mount_options $nfs_share $tar_target");
        if ($result == 0) {
            print "$taskid, $host, $group, $tar_target is now mounted \n" if $serverconfig{verbose};
        } else {
            print "$taskid, $host, $group, Mount error for $tar_target: $result\n";
            return;
        }
    }

    $tar_target .= "/$hostconfig->{BKP_PREFIX}/$host";

    return $tar_target;
}

sub execute_tar {
    my ( $taskid, $host, $group, $srcfolder ) = @_;
    my $hostconfig  = $hosts{"$host-$group"}->{hostconfig};

    my $startstamp = time();

    my ($tar_options, $tar_helper) = _eval_tar_options($host, $group, $taskid);
    my $tar_source                 = _eval_tar_source($host, $group);
    my $tar_target                 = _setup_tar_target($host, $group, $hostconfig, $taskid);

    my $tar_cmd  = $serverconfig{path_tar};

    print "$taskid, $host, $group, Tar Command: $tar_cmd $tar_options -cf $tar_target $tar_source\n" ;
    print "$taskid, $host, $group, Executing tar for host $host group $group\n";

    _delete_tar_helper($tar_helper);
}

1;
