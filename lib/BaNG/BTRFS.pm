package BaNG::BTRFS;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Common;
use BaNG::Reporting;

use Exporter 'import';
our @EXPORT = qw(
    create_btrfs_subvolume
    delete_btrfs_subvolume
    create_btrfs_snapshot
);

sub create_btrfs_subvolume {
    my ( $host, $group, $path, $taskid ) = @_;
    $taskid ||= 0;

    if ( -x $serverconfig{path_btrfs} ) {
        my $btrfs_subvolume_cmd = "$serverconfig{path_btrfs} subvolume create $path >/dev/null 2>&1";
        $btrfs_subvolume_cmd = "echo $btrfs_subvolume_cmd" if $serverconfig{dryrun};

        logit( $taskid, $host, $group, "Create btrfs subvolume: $btrfs_subvolume_cmd" );
        system($btrfs_subvolume_cmd) and logit( $taskid, $host, $group, "ERROR: creating subvolume for $host-$group: $!" );

    } else {
        logit( $taskid, $host, $group, "ERROR: could not create subvolumes, btrfs command not found, check path" );
    }
    return 1;
}

sub delete_btrfs_subvolume {
    my ( $host, $group, $path, $taskid ) = @_;
    $taskid ||= 0;

    if ( -x $serverconfig{path_btrfs} ) {
        my $btrfs_subvolume_cmd = "$serverconfig{path_btrfs} subvolume delete $path >/dev/null 2>&1";
        $btrfs_subvolume_cmd = "echo $btrfs_subvolume_cmd" if $serverconfig{dryrun};

        logit( $taskid, $host, $group, "Delete btrfs subvolume: $btrfs_subvolume_cmd" );
        system($btrfs_subvolume_cmd) and logit( $taskid, $host, $group, "ERROR: deleting subvolume for $host-$group: $!" );

    } else {
        logit( $taskid, $host, $group, "ERROR: could not delete subfolders, btrfs command not found, check path" );
    }

    return 1;
}

sub create_btrfs_snapshot {
    my ( $host, $group, $bkptimestamp, $taskid ) = @_;
    $taskid ||= 0;

    if ( -x $serverconfig{path_btrfs} ) {
        my $btrfs_cmd             = $serverconfig{path_btrfs};
        my $btrfs_snapshot_source = &BaNG::Common::targetpath( $host, $group ) . '/current';
        my $btrfs_snapshot_dest   = &BaNG::Common::targetpath( $host, $group ) . '/' . $bkptimestamp;

        my $touch_current_cmd = "touch $btrfs_snapshot_source >/dev/null 2>&1";
        $touch_current_cmd = "echo $touch_current_cmd" if $serverconfig{dryrun};
        logit( $taskid, $host, $group, "Touch current folder for host $host group $group" );
        system($touch_current_cmd) and logit( $taskid, $host, $group, "ERROR: touching current folder for $host-$group: $!" );

        my $btrfs_snapshot_cmd = "$btrfs_cmd subvolume snapshot -r $btrfs_snapshot_source $btrfs_snapshot_dest >/dev/null 2>&1";
        $btrfs_snapshot_cmd = "echo $btrfs_snapshot_cmd" if $serverconfig{dryrun};
        logit( $taskid, $host, $group, "Create btrfs snapshot for host $host group $group using $btrfs_snapshot_cmd" );
        system($btrfs_snapshot_cmd) and logit( $taskid, $host, $group, "ERROR: creating snapshot for $host-$group: $!" );

    } else {
        logit( $taskid, $host, $group, "ERROR: could not create snapshot, btrfs command not found, check path" );
    }

    return 1;
}

1;
