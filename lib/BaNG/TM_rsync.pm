package BaNG::TM_rsync;

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
    queue_rsync_backup
    run_rsync_threads
);

sub queue_rsync_backup {
    my ( $host_arg, $group_arg, $host, $group, $initial, $missingonly, $noreport, $taskid, $dryrun, $cron ) = @_;
    my ( $startstamp, $endstamp );
    my $jobid;

    logit( $taskid, $host, $group, "Queueing backup for host $host group $group" );

    my $bkptimestamp = eval_bkptimestamp( $host, $group );

    # get list of source folders to back up
    my (@src_folders) = split( / /, $hosts{"$host-$group"}->{hostconfig}->{BKP_SOURCE_FOLDER} );
    logit( $taskid, $host, $group, 'Number of source folders: ' . ( $#src_folders + 1 ) . " ( @src_folders )" );
    logit( $taskid, $host, $group, 'Status source folder threading: ' . $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SRCFOLDERS} );

    if (( $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SRCFOLDERS} ) || ( $#src_folders  == 0 )) {
        # optionally queue each subfolder of the source folders while only 1 srcfolder defined
        if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS} ) {

            my $dosnapshot = 0;
            my $numFolder  = @src_folders;

            foreach my $folder (@src_folders) {
                $jobid = create_timeid( $taskid, $host, $group );

                $numFolder--;
                if ( $numFolder == 0 ) {
                    $dosnapshot = 1;
                }
                _queue_remote_subfolders( $taskid, $jobid, $host, $group, $bkptimestamp, $dosnapshot, $folder, $dryrun, $cron, $noreport );
            }

        } else {

            my $dosnapshot = 0;
            my $numFolder  = @src_folders;

            $jobid = create_timeid( $taskid, $host, $group );

            foreach my $folder (@src_folders) {

                $numFolder--;
                if ( $numFolder == 0 ) {
                    $dosnapshot = 1;
                }

                my $bkpjob = {
                    taskid       => $taskid,
                    jobid        => $jobid,
                    host         => $host,
                    group        => $group,
                    path         => "$folder",
                    srcfolder    => "@src_folders",
                    bkptimestamp => $bkptimestamp,
                    dosnapshot   => $dosnapshot,
                    dryrun       => $dryrun,
                    noreport     => $noreport,
                    cron         => $cron,
                };
                push( @queue, $bkpjob );
            }

            my $bkpjob = {
                taskid       => $taskid,
                jobid        => $jobid,
                host         => $host,
                group        => $group,
                bkptimestamp => $bkptimestamp,
                dosnapshot   => $dosnapshot,
                dryrun       => $dryrun,
                cron         => $cron,
                noreport     => $noreport,
                rsync_err    => 0,
                has_failed   => 0,
            };
        }

    } else {
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
            cron         => $cron,
            noreport     => $noreport,
            rsync_err    => 0,
            has_failed   => 0,
        };
        push( @queue, $bkpjob );
    }

    logit( $taskid, $host, $group, "End of queueing backup of host $host group $group" );

    return 1;
}

sub _execute_rsync {
    my ( $taskid, $jobid, $noreport, $host, $group, $bkptimestamp, $path, $srcfolder, $exclsubfolders ) = @_;

    $bkptimestamp = eval_bkptimestamp( $host, $group ) unless $bkptimestamp;
    my $startstamp = time();

    # append custom string to path written to DB if we are excluding subfolders
    my $bkpfrompath = $exclsubfolders ? "$path/FILESONLY" : $path;
    $bkpfrompath =~ s/'//g;
    $bkpfrompath =~ s/\/\//\//g;

    # report rsync start to DB, jobstatus => 0
    bangstat_start_backupjob( $taskid, $jobid, $host, $group, $startstamp, '', $bkpfrompath, $srcfolder, targetpath( $host, $group ), '0', '0', '' ) unless $noreport;

    my $taskset = '';
    if ( $hosts{"$host-$group"}->{hostconfig}->{TASKSET_OPTIONS} ) {
        if ( -e $serverconfig{path_taskset} ) {
            $taskset = $serverconfig{path_taskset} . ' ' . $hosts{"$host-$group"}->{hostconfig}->{TASKSET_OPTIONS} . ' ';
        } else {
            logit( $taskid, $host, $group, "TASKSET selected but command $serverconfig{path_taskset} not found!" );
        }
    }

    my $nocache = '';
    if ( $hosts{"$host-$group"}->{hostconfig}->{NOCACHE_ENABLED} ) {
        if ( -e $serverconfig{path_nocache} ) {
            $nocache = $serverconfig{path_nocache} . ' ';
        } else {
            logit( $taskid, $host, $group, "NOCACHE selected but command $serverconfig{path_nocache} not found!" );
        }
    }

    my $ionice = '';
    if ( $hosts{"$host-$group"}->{hostconfig}->{IONICE_OPTIONS} ) {
        if ( -e $serverconfig{path_ionice} ) {
            $ionice = $serverconfig{path_ionice} . ' ' . $hosts{"$host-$group"}->{hostconfig}->{IONICE_OPTIONS} . ' ';
        } else {
            logit( $taskid, $host, $group, "IONICE selected but command $serverconfig{path_ionice} not found!" );
        }
    }

    my $timeout = '';
    if ( $hosts{"$host-$group"}->{hostconfig}->{TIMEOUT_DURATION} ne "0" ) {
        if ( -e $serverconfig{path_timeout} ) {
            $timeout  = $serverconfig{path_timeout} . ' --foreground ';
            $timeout .= '-k ' . $hosts{"$host-$group"}->{hostconfig}->{TIMEOUT_KILL_AFTER} . ' ';
            $timeout .= '-s ' . $hosts{"$host-$group"}->{hostconfig}->{TIMEOUT_SIGNAL} . ' ';
            $timeout .= $hosts{"$host-$group"}->{hostconfig}->{TIMEOUT_DURATION} . ' ';
        } else {
            logit( $taskid, $host, $group, "TIMEOUT selected but command $serverconfig{path_timeout} not found!" );
        }
    }

    my $rsync_cmd     = $nocache . $ionice . $taskset . $timeout . $serverconfig{path_rsync};
    my $rsync_options = _eval_rsync_options( $host, $group, $taskid );
    my $rsync_target  = _eval_rsync_target( $host, $group, $bkptimestamp );

    my $rsync_generic_exclude = '';
    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS} && $exclsubfolders ) {
        $rsync_generic_exclude = _eval_rsync_generic_exclude_cmd( $host, $group, $jobid );
        logit( $taskid, $host, $group, "Apply subfolder excludelist: $rsync_generic_exclude" );
    }

    logit( $taskid, $host, $group, "Rsync Command: $rsync_cmd $rsync_options$path $rsync_target" );
    logit( $taskid, $host, $group, "Executing rsync for host $host group $group path $path" );

    local ( *HIS_IN, *HIS_OUT, *HIS_ERR );
    $rsync_cmd = "echo $rsync_cmd" if $serverconfig{dryrun};
    my $rsyncpid = open3( *HIS_IN, *HIS_OUT, *HIS_ERR, "$rsync_cmd $rsync_generic_exclude $rsync_options$path $rsync_target" );

    writeto_lockfile( $taskid, $host, $group, $path, "shpid", $rsyncpid);

    logit( $taskid, $host, $group, "Rsync PID: $rsyncpid for host $host group $group path $path" );

    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    close HIS_IN;
    close HIS_OUT;
    close HIS_ERR;

    waitpid( $rsyncpid, 0 );

    logit( $taskid, $host, $group, "Rsync[$rsyncpid] STDOUT: @outlines" ) if ( @outlines && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "ERROR: Rsync[$rsyncpid] STDERR: @errlines" ) if @errlines;
    logit( $taskid, $host, $group, "ERROR: Rsync[$rsyncpid] child exited with status of $?" ) if $?;

    my $errcode  = 0;
    my $endstamp = time();

    if (@errlines) {
        foreach my $errline (@errlines) {
            if ( $errline =~ /.* \(code (\d+)/ ) {
                $errcode = $1;
                logit( $taskid, $host, $group, "Rsync errorcode: $errcode" );
            }
        }
    } else {
        logit( $taskid, $host, $group, "Rsync successful for host $host group $group path $path" );
    }

    #report finished rsync to DB, jobstatus => 1
    bangstat_update_backupjob( $taskid, $jobid, $host, $group, $endstamp, $bkpfrompath, targetpath( $host, $group ), $errcode, '1', @outlines ) unless $noreport;

    return $errcode;
}

sub run_rsync_threads {
    my ($host_arg, $group_arg, $nthreads_arg, $dryrun_arg, $cron) = @_;
    my %finishable_bkpjobs;
    # define number of threads
    my $nthreads;

    if ($nthreads_arg) {
        # If nthreads was defined by cli argument, use it
        $nthreads = $nthreads_arg;
        print "Using nthreads = $nthreads from command line argument\n" if $serverconfig{verbose};
    } elsif ( $host_arg && $group_arg ) {
        # If no nthreads was given, and we back up a single host and group, get nthreads from its config
        $nthreads = $hosts{"$host_arg-$group_arg"}->{hostconfig}->{BKP_THREADS_DEFAULT};
        print "Using nthreads = $nthreads from $host_arg-$group_arg config file\n" if $serverconfig{verbose};
    } else {
        $nthreads = 1;
    }

    my $Q = Thread::Queue->new;
    my @threads = map { threads->create( \&_rsync_thread_work, $Q ) } ( 1 .. $nthreads );
    $Q->enqueue($_) for @queue;
    $Q->enqueue( (undef) x $nthreads );

    foreach my $thread (@threads) {
        my (@finishable_bkpjobs_in_thread) = $thread->join;

        # Merge bkpjobs returned by this thread with already known jobs
        foreach my $bkpjob (@finishable_bkpjobs_in_thread) {
            if ( exists $finishable_bkpjobs{$bkpjob->{jobid}} ) {
                $finishable_bkpjobs{$bkpjob->{jobid}}->{has_failed} = 1 if $bkpjob->{has_failed};
                $finishable_bkpjobs{$bkpjob->{jobid}}->{dosnapshot} = 1 if $bkpjob->{dosnapshot};
            } else {
                $finishable_bkpjobs{$bkpjob->{jobid}} = $bkpjob;
            }
            # Push unique rsync errors to array
            unless( grep { $_ == $bkpjob->{rsync_err} } @{ $finishable_bkpjobs{$bkpjob->{jobid}}->{rsync_errs} } ) {
                push( @{ $finishable_bkpjobs{$bkpjob->{jobid}}->{rsync_errs} }, $bkpjob->{rsync_err} );
            }
        }
    }

    foreach my $finishable_bkpjob (sort keys %finishable_bkpjobs) {
        _finish_rsync_backupjob($finishable_bkpjobs{$finishable_bkpjob});
    }

    return 0;
}

#################################
# Helper subroutines
#
sub _check_rsync_status {
    my ( $rsync_err ) = @_;
    my $status = 1;

    if ( scalar grep $rsync_err eq $_, @{ $serverconfig{'rsync_err_ok'} }) {
        $status = 0;
    }

    return $status;
}

sub _eval_rsync_options {
    my ( $host, $group, $taskid ) = @_;
    my $rsync_options = '';
    my $hostconfig    = $hosts{"$host-$group"}->{hostconfig};

    $rsync_options .= '--stats ';
    $rsync_options .= '-a '              if $hostconfig->{BKP_RSYNC_ARCHIV};
    $rsync_options .= '-x '              if $hostconfig->{BKP_RSYNC_ONE_FS};
    $rsync_options .= '-R '              if $hostconfig->{BKP_RSYNC_RELATIV};
    $rsync_options .= '-H '              if $hostconfig->{BKP_RSYNC_HLINKS};
    $rsync_options .= '-W '              if $hostconfig->{BKP_RSYNC_WHOLEFILE};
    $rsync_options .= '-z '              if $hostconfig->{BKP_RSYNC_COMPRESS};
    $rsync_options .= '--delete '        if $hostconfig->{BKP_RSYNC_DELETE};
    $rsync_options .= '--ignore-errors ' if $hostconfig->{BKP_RSYNC_IGNORE_ERRORS};
    $rsync_options .= '--force '         if $hostconfig->{BKP_RSYNC_DELETE_FORCE};
    $rsync_options .= '--numeric-ids '   if $hostconfig->{BKP_RSYNC_NUM_IDS};
    $rsync_options .= '--inplace '       if $hostconfig->{BKP_RSYNC_INPLACE};
    $rsync_options .= '-S '              if $hostconfig->{BKP_RSYNC_SPARSE};
    $rsync_options .= '-A '              if $hostconfig->{BKP_RSYNC_ACL};
    $rsync_options .= '-X '              if $hostconfig->{BKP_RSYNC_XATTRS};
    $rsync_options .= '--no-D '          if $hostconfig->{BKP_RSYNC_NODEVICES};
    $rsync_options .= '-v '              if ( $serverconfig{verbose} && ( $serverconfig{verboselevel} == 3 ) );
    $rsync_options .= "-M '$hostconfig->{BKP_RSYNC_REMOTE_OPT}' "          if $hostconfig->{BKP_RSYNC_REMOTE_OPT};
    $rsync_options .= "--sockopts '$hostconfig->{BKP_RSYNC_SOCKOPTS}' "    if $hostconfig->{BKP_RSYNC_SOCKOPTS};
    $rsync_options .= "--rsync-path=$hostconfig->{BKP_RSYNC_RSHELL_PATH} " if $hostconfig->{BKP_RSYNC_RSHELL_PATH};

    if ( $hostconfig->{BKP_EXCLUDE_FILE} ) {
        my $excludefile = "$serverconfig{path_excludes}/$hostconfig->{BKP_EXCLUDE_FILE}";
        if ( -e $excludefile ) {
            $rsync_options .= "--exclude-from=$serverconfig{path_excludes}/$hostconfig->{BKP_EXCLUDE_FILE} ";
        } else {
            logit( $taskid, $host, $group, "Warning: could not find excludefile $excludefile." );
        }
    }

    # use links if told to
    if ( $hostconfig->{BKP_STORE_MODUS} eq 'links' ) {
        if ( -e targetpath( $host, $group ) . "/current" ) {
            $rsync_options .= '--link-dest ' . targetpath( $host, $group ) . "/current ";
        } else {
            logit( $taskid, $host, $group, "Warning: --link-dest not ok, make full backup!");
        }
    }

    if ( $hostconfig->{BKP_RSYNC_RSHELL} ) {
        if ( $hostconfig->{BKP_GWHOST} ) {
            $rsync_options .= "-e '$hostconfig->{BKP_RSYNC_RSHELL} $hostconfig->{BKP_GWHOST}' '$hostconfig->{BKP_RSYNC_RSHELL} $host'";
        } else {
            $rsync_options .= "-e '$hostconfig->{BKP_RSYNC_RSHELL}' $host";
        }
    }

    $rsync_options =~ s/\s+$//;    # remove trailing space

    return $rsync_options;
}

sub _eval_rsync_target {
    my ( $host, $group, $bkptimestamp ) = @_;
    my $rsync_target = targetpath( $host, $group );

    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
        $rsync_target .= '/current';
    } else {
        $rsync_target .= "/$bkptimestamp";
    }

    return $rsync_target;
}

sub _eval_rsync_generic_exclude_cmd {
    my ( $host, $group, $jobid ) = @_;
    my $exclsubfolderfilename = "generated.${host}_${group}_${jobid}";
    my $exclsubfolderopt      = "--exclude-from=$serverconfig{path_excludes}/$exclsubfolderfilename";

    return $exclsubfolderopt;
}
    sub _glob2pat {
        my $globstr = shift;
        my %patmap = (
            '*' => '.*',
            '?' => '.',
            '[' => '[',
            ']' => ']',
        );
        $globstr =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
        return '^' . $globstr . '$';
    }
sub _queue_remote_subfolders {
    my ( $taskid, $jobid, $host, $group, $bkptimestamp, $dosnapshot, $srcfolder, $dryrun, $cron, $noreport ) = @_;

    $srcfolder =~ s/://;
    my $remoteshell      = $hosts{"$host-$group"}->{hostconfig}->{BKP_RSYNC_RSHELL};
    my $excludes;
    my @excludeslist;
    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_EXCLUDE_FILE} ) {
        my $excludefile = "$serverconfig->{path_excludes}/$hostconfig->{BKP_EXCLUDE_FILE}";
        if ( -e $excludefile ) {
            $excludes = $excludefile;
        } else {
            logit( $taskid, $host, $group, "Warning: could not find excludefile $excludefile." );
            $excludes = "";
        }
    }
    if (-e $excludes) {
        open(my $fh,"<",$excludes);
        while(<$fh>) {
            if (($_) =~ s/^- (.*)$/$1/) {
                chomp;
                push @excludeslist, "\! -name \"$_\"";
            }
        }
    }
    my $findexcludes = join " ", @excludeslist;
    my @remotesubfolders = `$remoteshell $host find $srcfolder -xdev -type d -mindepth 1 -maxdepth 1 -not -empty $findexcludes | grep - sort`;

    # if @remotesubfolders empty (rsh troubles?) then use the $srcfolder
    if ( $#remotesubfolders == -1 ) {
        push( @remotesubfolders, $srcfolder );
        logit( $taskid, $host, $group, "ERROR: eval subfolders failed, use now with:\n ". decode('utf-8', @remotesubfolders) );
    } else {
        logit( $taskid, $host, $group, "eval subfolders:\n ". decode('utf-8', @remotesubfolders) );
    }

    my $exclsubfolderfile = create_generic_exclude_file($taskid, $host, $group, $jobid);

    open(my $fhExcludeFile, '>>', $exclsubfolderfile) unless $serverconfig{dryrun};

    foreach my $remotesubfolder (@remotesubfolders) {
        chomp $remotesubfolder;
        $remotesubfolder =~ s| |\\ |g;
        $remotesubfolder =~ s|\&|\\&|g;
        $remotesubfolder =~ s|\(|\\\(|g;
        $remotesubfolder =~ s|\)|\\\)|g;

        my $bkpjob = {
            taskid       => $taskid,
            jobid        => $jobid,
            host         => $host,
            group        => $group,
            path         => ":'". decode('utf-8',${remotesubfolder}) ."'",
            bkptimestamp => $bkptimestamp,
            srcfolder    => ":$srcfolder",
            dosnapshot   => 0,
            dryrun       => $dryrun,
            cron         => $cron,
            noreport     => $noreport,
        };
        push( @queue, $bkpjob );

        $remotesubfolder =~ s|^/||g;
        print $fhExcludeFile "- $remotesubfolder/\n" unless $serverconfig{dryrun};
        print "- $remotesubfolder/\n" if $serverconfig{verbose};
    }
    close $fhExcludeFile unless $serverconfig{dryrun};

    # add bkp job for files only
    my $bkpjob = {
        taskid         => $taskid,
        jobid          => $jobid,
        host           => $host,
        group          => $group,
        path           => ":'${srcfolder}'",
        bkptimestamp   => $bkptimestamp,
        srcfolder      => ":$srcfolder",
        dosnapshot     => $dosnapshot,
        dryrun         => $dryrun,
        cron           => $cron,
        noreport       => $noreport,
        exclsubfolders => 1,
    };
    push( @queue, $bkpjob );

    return 1;
}

sub _rsync_thread_work {
    my ($Q) = @_;
    my @finishable_bkpjobs_in_thread;

    while ( my $bkpjob = $Q->dequeue ) {
        my $tid            = threads->tid;
        my $taskid         = $bkpjob->{taskid};
        my $jobid          = $bkpjob->{jobid};
        my $host           = $bkpjob->{host};
        my $group          = $bkpjob->{group};
        my $path           = $bkpjob->{path};
        my $bkptimestamp   = $bkpjob->{bkptimestamp};
        my $srcfolder      = $bkpjob->{srcfolder};
        my $dosnapshot     = $bkpjob->{'dosnapshot'};
        my $dryrun         = $bkpjob->{'dryrun'};
        my $cron           = $bkpjob->{'cron'};
        my $noreport       = $bkpjob->{'noreport'};
        my $exclsubfolders = $bkpjob->{'exclsubfolders'} || 0;

        my $random_integer = int( rand(7) ) + 1;
        $random_integer    = 0 if ( $dryrun );

        return unless create_lockfile( $taskid, $host, $group, $path );
        writeto_lockfile( $taskid, $host, $group, $path, "cron", $cron);
        logit( $taskid, $host, $group, "Thread $tid sleep $random_integer sec. for $host-$group ($path)" );
        sleep($random_integer);
        logit( $taskid, $host, $group, "Thread $tid working on $host-$group ($path)" );
        my $rsync_err = _execute_rsync( $taskid, $jobid, $noreport, $host, $group, $bkptimestamp, $path, $srcfolder ,$exclsubfolders );
        logit( $taskid, $host, $group, "Thread $tid finished with $host-$group ($path) ErrCode: $rsync_err" );
        my $bkpjob = {
            taskid       => $taskid,
            jobid        => $jobid,
            host         => $host,
            group        => $group,
            bkptimestamp => $bkptimestamp,
            dosnapshot   => $dosnapshot,
            rsync_err    => $rsync_err,
            has_failed   => _check_rsync_status( $rsync_err ),
        };
        push(@finishable_bkpjobs_in_thread, $bkpjob);
        remove_lockfile( $taskid, $host, $group, $path );
    }

    return (@finishable_bkpjobs_in_thread);
}

sub _finish_rsync_backupjob {
    my ($bkpjob)     = @_;
    my $taskid       = $bkpjob->{'taskid'};
    my $jobid        = $bkpjob->{'jobid'};
    my $host         = $bkpjob->{'host'};
    my $group        = $bkpjob->{'group'};
    my $bkptimestamp = $bkpjob->{'bkptimestamp'};
    my $dosnapshot   = $bkpjob->{'dosnapshot'};
    my $noreport     = $bkpjob->{'noreport'};
    my $has_failed   = $bkpjob->{'has_failed'};
    my $rsync_err    = join(', ', sort @{ $bkpjob->{'rsync_errs'} });
    my @rsync_pass   = @{ $serverconfig{'rsync_err_ok'} };

    if (( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) &&  ( $dosnapshot )) {
        my $rsync_target = targetpath( $host, $group );
        create_btrfs_snapshot( $host, $group, $bkptimestamp, $taskid, $rsync_target);

        if ( $has_failed ) {
            logit( $taskid, $host, $group, "rsync in snapshot-mode failed with code $rsync_err for host $host group $group" ) if $serverconfig{verbose};
            rename_failed_backup( $taskid, $host, $group, $bkptimestamp );
        } else {
            logit( $taskid, $host, $group, "rsync in snapshot-mode successfully finished with (code $rsync_err) for host $host group $group" ) if $serverconfig{verbose};
        }
    }

    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'links' ) {
        if ( $has_failed ) {
            logit( $taskid, $host, $group, "rsync in links-mode failed with code $rsync_err for host $host group $group" ) if $serverconfig{verbose};
            rename_failed_backup( $taskid, $host, $group, $bkptimestamp );
        } else {
            logit( $taskid, $host, $group, "rsync in links-mode successfully finished with (code $rsync_err) for host $host group $group" ) if $serverconfig{verbose};
            create_link_current( $taskid, $host, $group, $bkptimestamp );
        }
    }

    # report finished job to DB, jobstatus => 2
    bangstat_finish_backupjob( $taskid, $jobid, $host, $group, '2' ) unless $noreport;

    my %RecentBackups = bangstat_recentbackups($host);
    unless ($noreport) {
        xymon_report( $taskid, $host, $group, %RecentBackups );
        mail_report( $taskid, $host, $group, %RecentBackups ) if $serverconfig{report_to};
    }

    logit( $taskid, $host, $group, "Backup successful for host $host group $group!" );

    remove_generic_exclude_file($taskid, $host, $group, $jobid) if $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS};

    return 1;
}

1;
