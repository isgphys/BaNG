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
use Data::Dumper;


use Exporter 'import';
our @EXPORT = qw(
    queue_lftp_backup
    run_lftp_threads
);

sub queue_lftp_backup {
    my ($dryrun, $hostsref, $queueref, $host, $group, $noreport,$taskid,$serverconfig ) = @_;
    my $jobid;
    my $source_path;
    my ( $startstamp, $endstamp );
    logit ($taskid, $host, $group, "Queueing lftp backup for host $host, group $group");
    my $bkptimestamp = eval_bkptimestamp ($host, $group);
    my @src_folders = split( / /, %$hostsref{"$host-$group"}->{hostconfig}->{BKP_SOURCE_FOLDER});
    my $hostconfig = %$hostsref{"$host-$group"}->{hostconfig};
    my $excludes;

    if ( $hostconfig->{BKP_EXCLUDE_FILE} ) {
        my $excludefile = "$serverconfig->{path_excludes}/$hostconfig->{BKP_EXCLUDE_FILE}";
        if ( -e $excludefile ) {
            $excludes = $excludefile;
        } else {
            logit( $taskid, $host, $group, "Warning: could not find excludefile $excludefile." );
            $excludes = "";
        }
    }
    # queue list of source folders as a whole
    $jobid = create_timeid( $taskid, $host, $group );
    my %bkpjob = (
            taskid       => $taskid,
            jobid        => $jobid,
            host         => $host,
            group        => $group,
            srcdirs      => \@src_folders,
            bkptimestamp => $bkptimestamp,
            dryrun       => $dryrun,
            excludes     => $excludes,
        );
    push( @$queueref, \%bkpjob );


    logit( $taskid, $host, $group, "End of queueing backup of host $host group $group" );
    return $queueref;
}

sub run_lftp_threads {
    my ($queue, $nthreads_arg, $dryrun, $hosts) = @_;
    my $Q = Thread::Queue->new;
    my $rQ = Thread::Queue->new;
    my $nthreads;
    my @threads;


    foreach my $j (@$queue) {

        foreach my $srcdir (@{$j->{srcdirs}}) {
            my $host = $$j{host};
            my $group = $$j{group};

            if ($nthreads_arg) {
                # If nthreads was defined by cli argument, use it
                $nthreads = $nthreads_arg;
                print "Using nthreads = $nthreads from command line argument\n" if $serverconfig{verbose};
            } else {
                # If no nthreads was given, and we back up a single host and group, get nthreads from its config
                my $ntfh = defined %$hosts{"$host-$group"}->{hostconfig}->{BKP_THREADS_DEFAULT} ? %$hosts{"$host-$group"}->{hostconfig}->{BKP_THREADS_DEFAULT} : 1;

                $nthreads = $ntfh;

            }
            my $parallel = $nthreads;
            my %threadargs = (dryrun => $dryrun,
                              taskid => $$j{taskid},
                              host => $host,
                              group => $group,
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
            my $finished_thread = $rQ->dequeue();
            print "Finished waiting for thread $finished_thread.\n";

        }



    return 0;
}
sub _lftp_parse_exclude_file {
    my ($theargs) = @_;
    my $excludes = %$theargs{excludes};

    my @excludeslist;
    my $lftp_excludes;
    if (-e $excludes) {
        open(my $fh,"<",$excludes);
        while(<$fh>) {
            if (($_) =~ s/^- (.*)$/$1/) {
                chomp;
                push @excludeslist, "--exclude=\"$_\"";
            }
            elsif (($_) =~ s/^\+ (.*)$/$1/) {
                chomp;
                push @excludeslist, "--include=$_";
            }
        }
        my $x = join " ", @excludeslist;
        return $x;
    }

}
sub _get_target_dir {
    my $theargs = shift;
    my $target = targetpath( $$theargs{host}, $$theargs{group} );
    $target .= '/current';
    return $target;

}
sub _do_lftp {
    my $Q = shift;
    my $theargs = $Q->dequeue;
    my ($dryrun, $taskid, $host, $group, $bkptimestamp, $srcpath, $jobthreads) = ($$theargs{dryrun}, $$theargs{taskid}, $$theargs{host},$$theargs{group},$$theargs{bkptimestamp},$$theargs{path},$$theargs{parallel});

    my $rQ = $$theargs{rQ};
    my $lftp_bin = "/usr/bin/lftp";
    my $verbose = " --verbose";
    my $delete = " --delete";
    my $excludes = _lftp_parse_exclude_file($theargs);
    my $nthreads = $jobthreads;
    my $parallel = " --parallel=$jobthreads";
    my $lftp_mode = "mirror";
    $srcpath =~ s/^:(.*)$/$1/;
    $srcpath =~ tr/'/"/;
    $srcpath =~ tr/\/\//\//;
    my $destpath = _get_target_dir($theargs) . $srcpath;
    my $lftp_pget_n = " --use-pget-n=2";
    my $lftp_script = "-e " . "'" . $lftp_mode . $verbose . " " . $excludes . $delete . $lftp_pget_n . $parallel . " " . '-c "' . $srcpath . '"' . " " . $destpath . ";bye'";
    my $lftp_srchost = $host;
    my $lftp_srcproto = "sftp://"; # good for now. maybe look into torrent because it sounds interesting and maybe useful

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
    logit( $taskid, $host, $group, "ERROR: lftp[$lftppid] child exited with status of $errcode" ) if $errcode;
    my $jobid = $lftppid;
    waitpid ($lftppid,0);
    print "Thread finished lftp[$lftppid]\n $jobid $host $group with err $errcode.\n";
    remove_lockfile($taskid,$host,$group,$srcpath,"shpid",$lftppid);
    $rQ->enqueue(threads->tid);
    return $errcode;
}
