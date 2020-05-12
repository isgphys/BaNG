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
use forks::shared;
use IPC::Open3;
use Thread::Queue;
use Data::Dumper;
use Thread::Semaphore;

use Exporter 'import';
our @EXPORT = qw(
    queue_lftp_backup
    run_lftp_threads
);

sub queue_lftp_backup {
    my ($dryrun, $hostsref, $queueref, $host, $group, $noreport,$taskid ) = @_;
    my $jobid;
    my $source_path;
    my ( $startstamp, $endstamp );
    logit ($taskid, $host, $group, "Queueing lftp backup for host $host, group $group");
    my $bkptimestamp = eval_bkptimestamp ($host, $group);
    my @src_folders = split( / /, %$hostsref{"$host-$group"}->{hostconfig}->{BKP_SOURCE_FOLDER});

    # queue list of source folders as a whole
    $jobid = create_timeid( $taskid, $host, $group );
    my %bkpjob = (
            taskid       => $taskid,
            jobid        => $jobid,
            host         => $host,
            group        => $group,
            path         => "@src_folders",
            srcdirs    => \@src_folders,
            bkptimestamp => $bkptimestamp,
            dosnapshot   => 1,
            dryrun       => $dryrun,
            rsync_err    => 0,
            has_failed   => 0,
            excludes =>  "",
        );
    push( @$queueref, \%bkpjob );
    
    
    logit( $taskid, $host, $group, "End of queueing backup of host $host group $group" );
    return $queueref;
}

sub run_lftp_threads {
    my ($queue, $parallel, $dryrun) = @_;
    my $Q = Thread::Queue->new;
    my $rQ = Thread::Queue->new;
    my @threads;
    
    
    foreach my $j (@$queue) {

        foreach my $srcdir (@{$j->{srcdirs}}) {
           my %threadargs = (dryrun => $dryrun,
                taskid => $$j{taskid},
                host => $$j{host},
                group => $$j{group},
                bkptimestamp => $$j{bkptimestamp},
                path => $srcdir,
                excludes => $$j{excludes},
                parallel => $parallel, rQ => $rQ);


            $Q->enqueue(\%threadargs);
           my $t = threads->create( \&_do_lftp, $Q);
           $t->detach();
            push(@threads,$t->tid);

            }
        
    }

    for(@threads) {
            print "Waiting for finished jobs in joiner loop.\n";

            my $finished_thread = $rQ->dequeue();
            print "finished waiting for thread $finished_thread.\n";

        } 
           
    

    return 0;
}
sub _do_lftp {
    my $Q = shift;
    print Dumper($Q);
    my $theargs = $Q->dequeue;
    print Dumper($theargs);
    my ($dryrun, $taskid, $host, $group, $bkptimestamp, $srcpath, $excludes,$jobthreads) = ($$theargs{dryrun}, $$theargs{taskid}, $$theargs{host},$$theargs{group},$$theargs{bkptimestamp},$$theargs{path},$$theargs{excludes},$$theargs{parallel});

    my $rQ = $$theargs{rQ};
    # TODO don't ignore dryrun..
    my $lftp_bin = "/usr/bin/lftp";
    my $verbose = " --verbose";
    my $delete = " --delete";
    my $lftp_excludes = ""; # TODO - extract from rsync exclude file
    # TODO add a method to just do it with a path so that we don't have to think about excludes - rsync will clean up afterwards anyway
    my $nthreads = 0; # TODO - is the setting for rsync per job or task ?
# rsync doesnt do parallel native
    my $parallel = " --parallel=$jobthreads"; # TODO: figure this out
    my $lftp_mode = "mirror";
    $srcpath =~ tr/://;
    $srcpath =~ tr/'/"/;
if (    $srcpath =~ tr/\/\//\//)
{
logit("mystery path $srcpath"); #wahrscheinlich nur für db
} 
    my $destpath = '""'; # TODO - figure this out
    my $lftp_script = "-c '" . $lftp_mode . $verbose . $delete . $parallel . " " . $srcpath . " " . $destpath . "'";
    my $lftp_srchost = $host;
    my $lftp_srcproto = "sftp://"; # good for now. maybe look into torrent because it sounds interesting and maybe useful
    my $lftp_pget_n = 2; #TODO figure out experimentally
    my $lftp_cmd = $lftp_bin . " $lftp_srcproto$lftp_srchost " . $lftp_script;
    logit( $taskid, $host, $group, "LFTP Command: $lftp_cmd" );
    logit( $taskid, $host, $group, "Executing lftp for host $host group $group path $srcpath." );    
    local (*HIS_IN, *HIS_OUT, *HIS_ERR);
    if (defined $dryrun && $dryrun == 1) {
        $lftp_cmd = "echo Would run: $lftp_cmd";
    }
    else {
        $lftp_cmd = "$lftp_cmd";
    }
    $lftp_cmd = "echo Would run: $lftp_cmd";
    my $lftppid = open3(*HIS_IN, *HIS_OUT, *HIS_ERR, "$lftp_cmd");
    writeto_lockfile($taskid,$host,$group,$srcpath,"shpid",$lftppid); # TODO clear this
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    close HIS_IN;
    close HIS_OUT;
    close HIS_ERR;

    logit( $taskid, $host, $group, "lftp[$lftppid] STDOUT: @outlines" ) if ( @outlines && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "ERROR: lftp[$lftppid] STDERR: @errlines" ) if @errlines;
    my $errcode = $?; # warum parset TM_rsync das stdout anstatt $? zu nehmen ?
    logit( $taskid, $host, $group, "ERROR: lftp[$lftppid] child exited with status of $errcode" ) if $errcode;
    my $jobid = $lftppid; # TODO - probably not a good idea
    waitpid ($lftppid,0);
    print "Thread finished lftp[$lftppid]\n $jobid $host $group with err $errcode.\n";
    $rQ->enqueue(threads->tid);
    print "going out of scope with $jobid\n";
    return $errcode;
}
