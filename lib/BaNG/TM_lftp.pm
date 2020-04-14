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
    my ($queue, $parallel, $dryrun) = @_;
    my $Q = Thread::Queue->new;
    my $cond_end :shared;
    lock ($cond_end);
    foreach my $j (@queue) {
        
        my $nthreads = scalar %$j{src_folders}; # do process per directory
        my @threads = map { threads->create( \&_do_lftp, $Q ) } ( 1 .. $nthreads );
        $Q->enqueue($j);
#        $Q->enqueue( (undef) x $nthreads ); # wtf is undef XOR nthreads supposed to do
        for(%$j{src_folders}) {
            lock($cond_end);
            cond_wait($cond_end);
            lock($cond_end);
            my %fj = %$cond_end;
            logit($fj{taskid}, $fj{host}, $fj{group}, "Job $fj{jobid} finished."); # TODO do I really want to copy this info and pass it back this way
        }    
}
    

    return 0;
}
sub _do_lftp {
    my ($taskid, $host, $group, $bkptimestamp, $srcpath, @excludes,$jobthreads, $cond_end) = @_; # TODO uh this all has to come from $Q or I have to parse this earlier in run_lftp_threads
    my $lftp_bin = "/usr/bin/lftp";
    my $verbose = " --verbose";
    my $delete = " --delete";
    my $lftp_excludes = ""; # TODO - extract from rsync exclude file
    my $nthreads = 0; # TODO - is the setting for rsync per job or task ?
    my $parallel = " --parallel=$jobthreads"; # TODO - figure out what job/task are supposed to mean in this program and stop using interchangeably
    my $lftp_mode = "mirror";
    $srcpath =~ tr/://;
    $srcpath =~ tr/'/"/;
    $srcpath =~ tr/\/\//\//;
    my $destpath = '""'; # TODO - figure this out
    my $lftp_script = "-c '" . $lftp_mode . $verbose . $delete . $parallel . $srcpath . $destpath . "'";
    my $lftp_cmd = $lftp_bin . $lftp_script;
    logit( $taskid, $host, $group, "LFTP Command: $lftp_cmd" );
    logit( $taskid, $host, $group, "Executing lft for host $host group $group path $srcpath" );    
    local (*HIS_IN, *HIS_OUT, *HIS_ERR);
    $lftp_cmd = "echo $lftp_cmd" if $serverconfig{dryrun};
    my $lftppid = open3(*HIS_IN, *HIS_OUT, *HIS_ERR, "$lftp_cmd");
    writeto_lockfile($taskid,$host,$group,$srcpath,"shpid",$lftppid);
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    close HIS_IN;
    close HIS_OUT;
    close HIS_ERR;

    logit( $taskid, $host, $group, "lftp[$lftppid] STDOUT: @outlines" ) if ( @outlines && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "ERROR: lftp[$lftppid] STDERR: @errlines" ) if @errlines;
    my $errcode = $?;
    logit( $taskid, $host, $group, "ERROR: lftp[$lftppid] child exited with status of $?" ) if $errcode;
    my $jobid = $lftppid; # TODO - probably not a good idea
    waitpid ($lftppid,0);
    { lock ($cond_end);
      $cond_end = {taskid => $taskid, jobid => $jobid, host => $host, group => $group, errcode => $errcode};
      cond_signal($cond_end);
      }    
    return $errcode;

}
