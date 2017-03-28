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
    queue_tar_backup
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
    my ( $group, $ltsconfig, $taskid ) = @_;

    my $nfs_share         = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_share};
    my $nfs_mount_options = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_mount_options};
    my $tar_target        = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_mount};

    if (`cat /proc/mounts | grep $tar_target`) {
        print "$taskid, $group, $tar_target is mounted \n" if $serverconfig{verbose};
    } else {
        print "$taskid, $group, $tar_target is not mounted \n" if $serverconfig{verbose};
        my $mount_cmd = "mount -t nfs -o $nfs_mount_options $nfs_share $tar_target";
        $mount_cmd = "echo $mount_cmd" if $serverconfig{dryrun};
        my $mount_result = system($mount_cmd);
        if ($mount_result == 0) {
            print "$taskid, $group, $tar_target is now mounted \n" if $serverconfig{verbose};
        } else {
            print "$taskid, $group, Mount error for $tar_target: $mount_result\n";
            return;
        }
    }

    $tar_target .= "/$ltsconfig->{BKP_PREFIX}/$group";

    return $tar_target;
}

sub execute_tar {
    my ( $taskid, $group, $srcfolder ) = @_;
    my $ltsconfig  = $ltsjobs{"$group"}->{ltsconfig};

    my $startstamp = time();

    my ($tar_options, $tar_helper) = _eval_tar_options($group, $taskid);
    my $tar_source                 = _eval_tar_source($group);
    my $tar_target                 = _setup_tar_target($group, $ltsconfig, $taskid);

    my $tar_cmd  = $serverconfig{path_tar};

    print "$taskid, $group, Tar Command: $tar_cmd $tar_options -cf $tar_target $tar_source\n" ;
    print "$taskid, $group, Executing tar for group $group\n";

    _delete_tar_helper($tar_helper);
}

#################################
# Queuing
#
sub queue_tar_backup {
    my ( $group, $noreport, $taskid ) = @_;
    my $jobid;

    logit( $taskid, $group, '', "Queueing backup for group $group" );

    # make sure backup is enabled
    return unless $ltsjobs{"$group"}->{ltsconfig}->{BKP_ENABLED};

    if ( !-e ($serverconfig{path_tar} || "") ) {

        logit( $taskid, $group, '', "TAR command " . ($serverconfig{path_tar} || "") . " not found!" );

        return 1;
    }

    my $src_folder = $ltsjobs{"$group"}->{ltsconfig}->{BKP_SOURCE_PATH};

    if ( $ltsjobs{"$group"}->{ltsconfig}->{BKP_THREAD_SUBFOLDERS} ) {

        _queue_subfolders( $taskid, $group, $src_folder );

    } else {

        $jobid = create_timeid( $taskid, $group );

        my $ltsjob = {
            jobid        => $jobid,
            group        => $group,
            path         => "$src_folder",
            srcfolder    => "$src_folder",
        };
        print "Push-Queue JobID: $ltsjob->{jobid} Group: $ltsjob->{group} srcfolder: $ltsjob->{srcfolder} path: $ltsjob->{path}\n" if $serverconfig{verbose};
        push( @queue, $ltsjob );
    }

    logit( $taskid, $group, '', "End of queueing backup of group $group" );

    return 1;
}

sub _queue_subfolders {
    my ( $taskid, $group, $searchpath ) = @_;
    print "searchpath: $searchpath\n" if $serverconfig{verbose};

    my @subfolders = `find $searchpath -mindepth 1 -maxdepth 1 -xdev -type d -not -empty | sort`;

    if ( $#subfolders == -1 ) {
        push( @subfolders, $searchpath );
        logit( $taskid, $group, '', "ERROR: eval subfolders failed, use now with:\n @subfolders" );
    } else {
        logit( $taskid, $group, '', "found subfolders:\n @subfolders" );
    }

    foreach my $subfolder (@subfolders) {
        my $jobid = create_timeid( $taskid, $group );
        chomp $subfolder;
        my $ltsjob = {
            jobid        => $jobid,
            group        => $group,
            path         => "$subfolder",
            srcfolder    => "$searchpath",
        };
        print "Push-Queue JobID: $ltsjob->{jobid} Group: $ltsjob->{group} srcfolder: $ltsjob->{srcfolder} path: $ltsjob->{path}\n" if $serverconfig{verbose};
        push( @queue, $ltsjob );
    }
    return 1;
}

1;
