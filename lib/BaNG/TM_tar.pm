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
    my ($group, $taskid) = @_;
    my $tar_options = $ltsjobs{"$group"}->{ltsconfig}->{lts_tar_options};
    my $tar_helper  = _create_tar_helper();

    logit( $taskid, $group, '', "tar helper script $tar_helper created" );

    $tar_options .= " -F $tar_helper";

    return ($tar_options, $tar_helper);
}

sub _eval_tar_source {
    my ( $group ) = @_;
    my $tar_source = targetpath( $group );

    if ( $ltsjobs{"$group"}->{ltsconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
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

    my $nfs_share         = $serverconfig{lts_nfs_share};
    my $nfs_mount_options = $serverconfig{lts_nfs_mount_options};
    my $tar_target        = $serverconfig{lts_target_mnt};

    if (`cat /proc/mounts | grep $tar_target`) {
        print "$taskid, $host, $group, $tar_target is mounted \n" if $serverconfig{verbose};
    } else {
        print "$taskid, $host, $group, $tar_target is not mounted \n" if $serverconfig{verbose};
        my $mount_cmd = "mount -t nfs -o $nfs_mount_options $nfs_share $tar_target";
        $mount_cmd = "echo $mount_cmd" if $serverconfig{dryrun};
        my $mount_result = system($mount_cmd);
        if ($mount_result == 0) {
            print "$taskid, $host, $group, $tar_target is now mounted \n" if $serverconfig{verbose};
        } else {
            print "$taskid, $host, $group, Mount error for $tar_target: $mount_result\n";
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
