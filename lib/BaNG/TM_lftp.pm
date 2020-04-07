package BaNG::TM_lftp;

use 5.010;
use strict;
use warnings;
use Encode qw(decode);
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BackupServer;
use BaNG::BTRFS;
use Date::Parse;
use forks;
use IPC::Open3;
use Thread::Queue;

use Exporter 'import';
our @EXPORT = qw(
    queue_lft_backup
    run_lft_threads
);

sub queue_lftp_backup {
    my ($dryrun, $hostsref, $queueref, $host, $group, $taskid ) = @_;
    my $jobid;
    my $source_path;
    my ( $startstamp, $endstamp );
    logit ($taskid, $host, $group, "Queueing lftp backup for host $host, group $group");
    my $bkptimestamp = eval_bkptimestamp ($host, $group);
    my (@src_folders) = split( / /, %$hostsref{$host-$group}->{hostconfig}->{BKP_SOURCE_FOLDER});

    # queue list of source folders as a whole
    $jobid = create_timeid( $taskid, $host, $group );
    my $bkpjob = {
            taskid       => $taskid,
            jobid        => $jobid,
            host         => $host,
            group        => $group,
            path         => "@src_folders",
            srcfolder    => "@src_folders",
            bkptimestamp => $bkptimestamp,
            dosnapshot   => 1,
            dryrun       => $dryrun,
            rsync_err    => 0,
            has_failed   => 0,
        };
    push( @$queueref, $bkpjob );
    
    
    logit( $taskid, $host, $group, "End of queueing backup of host $host group $group" );
    return $queueref;
}

sub run_lftp_threads {

    return 0;
}
