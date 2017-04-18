package BaNG::TM_lts;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BackupServer;
use forks;
use IPC::Open3;
use Thread::Queue;

use Exporter 'import';
our @EXPORT = qw(
    queue_lts_backup
    run_lts_threads
);

sub queue_lts_backup {
    my ( $group, $noreport, $taskid ) = @_;
    my $jobid;
    my $source_path;

    logit( $taskid, 'LTS', $group, "Queueing backup for group $group" );

    # make sure backup is enabled
    return unless $ltsjobs{"$group"}->{ltsconfig}->{LTS_ENABLED};

    # make sure LTS_SOURCE_PATH is set
    if ( $ltsjobs{"$group"}->{ltsconfig}->{LTS_SOURCE_PATH} ) {
        $source_path = $ltsjobs{"$group"}->{ltsconfig}->{LTS_SOURCE_PATH};
    } else {
        logit( $taskid, 'LTS', $group, "LTS_SOURCE_PATH not defined for group $group" );
        return;
    }

    if ( !-e ($serverconfig{path_dar} || "") ) {

        logit( $taskid, 'LTS', $group, "dar command " . ($serverconfig{path_dar} || "") . " not found!" );

        return 1;
    }

    print "Hostlist source_path: $source_path\n" if $serverconfig{verbose};

    my @hostslist = `find $source_path -mindepth 1 -maxdepth 1 -xdev -type d -not -empty | sort`;

    if ( $#hostslist == -1 ) {
        logit( $taskid, 'LTS', $group, "ERROR: eval hostslist failed, no hosts found:\n" );
    } else {
        logit( $taskid, 'LTS', $group, "found following hosts ( $#hostslist )\n @hostslist" );
    }

    foreach my $path (@hostslist) {
        chomp($path);
        next unless ( my ( $host ) = $path =~ /\/([a-z0-9-]*)$/ );  # we want only active hosts, ignore '_' in hostnames

        if ( $ltsjobs{"$group"}->{ltsconfig}->{LTS_THREAD_SUBFOLDERS} ) {

            _queue_subfolders( $taskid, $host, $group, $path );

        } else {
            my $jobid = create_timeid( $taskid, $group );
            chomp $path;
            my $ltsjob = {
                taskid       => $taskid,
                jobid        => $jobid,
                group        => $group,
                host         => $host,
                path         => "$path",
                source_path  => "$source_path",
                ifsub        => 0,
            };
            push( @queue, $ltsjob );
        }
    }
    print "Final queued hosts: $#queue\n" if $serverconfig{verbose};
    logit( $taskid, 'LTS', $group, "Queueing of LTS-backup for group $group done." );

    return 1;
}

sub run_lts_threads {
    my ($taskid, $group, $nthreads_arg, $dryrun_arg) = @_;
    my %finishable_ltsjobs;
    # define number of threads
    my $nthreads;

    if ($nthreads_arg) {
        # If nthreads was defined by cli argument, use it
        $nthreads = $nthreads_arg;
        print "Using nthreads = $nthreads from command line argument\n" if $serverconfig{verbose};
    } elsif ( $group ) {
        # If no nthreads was given, get nthreads from its config
        $nthreads = $ltsjobs{"$group"}->{ltsconfig}->{LTS_THREADS_DEFAULT};
        print "Using nthreads = $nthreads from $group config file\n" if $serverconfig{verbose};
    } else {
        $nthreads = 1;
    }

    my ($dar_options) = _eval_dar_options($group, $taskid);

    my $Q = Thread::Queue->new;
    my @threads = map { threads->create( \&_dar_thread_work, $dar_options, $Q ) } ( 1 .. $nthreads );

    # fill the threading queue
    $Q->enqueue($_) for @queue;

    # Signal that there is no more work to be sent
    $Q->end();

    if ( $serverconfig{verbose} && $serverconfig{verboselevel} >= 2 ) {
        print "/////////////////////////////////////////////////////\n";
        print "Queuing of threads finished, wait for joining...\n";
        print "/////////////////////////////////////////////////////\n";
    }

    my @final_data;
    # loop until all threads are done
    while ( threads->list() ) {
        foreach my $tj (threads->list(threads::joinable) ) {
            print "\nThread ". $tj->tid() ." finished, joining...\n" if $serverconfig{verbose};

            my (@finishable_ltsjobs_in_thread) = $tj->join;

            foreach my $ltsjob (@finishable_ltsjobs_in_thread) {
                print "$ltsjob->{jobid} $ltsjob->{hostname}\n";
                push (@final_data, $ltsjob );
            }
            my (@remaining) = threads->list(threads::running);
            print "\t",scalar(@remaining)," of $nthreads threads remain\n" if $serverconfig{verbose};
        }

        unless ( threads->list() ) {
            if ( $serverconfig{verbose} && $serverconfig{verboselevel} >= 2 ) {
                print "\nAll threads are joined! ". $#final_data ." entries found:\n";

                foreach my $ltsjob (sort { $a->{jobid} cmp $b->{jobid} } @final_data) {
                    print "$ltsjob->{jobid} $ltsjob->{hostname} $ltsjob->{path}\n";
                }
            }
        }
    }

    return 0;
}

sub _dar_thread_work {
    my ($dar_options, $Q) = @_;
    my @finishable_ltsjobs_in_thread;

    while ( my $ltsjob = $Q->dequeue ) {
        my $tid            = threads->tid;
        my $taskid         = $ltsjob->{taskid};
        my $jobid          = $ltsjob->{jobid};
        my $group          = $ltsjob->{group};
        my $host           = $ltsjob->{host};
        my $path           = $ltsjob->{path};
        my $dryrun         = $ltsjob->{'dryrun'};
        my $cron           = $ltsjob->{'cron'};

        my $random_integer = int( rand(7) ) + 1;
        $random_integer    = 0 if ( $dryrun );

        return unless create_lockfile( $taskid, $host, $group, $path );
        logit( $taskid, 'LTS', $group, "Thread $tid sleep $random_integer sec. for $host-$group ($path)" );
        sleep($random_integer);
        logit( $taskid, 'LTS', $group, "Thread $tid start working on $group ($path)" );
        my $dar_err = _execute_dar( $ltsjob, $dar_options );

        my $ltsjob = {
            jobid    => $jobid,
            hostname => $host,
            path     => $path,
        };
        push(@finishable_ltsjobs_in_thread, $ltsjob);
        remove_lockfile( $taskid, $host, $group, $path );
    }

   return (@finishable_ltsjobs_in_thread);
}

sub _queue_subfolders {
    my ( $taskid, $host, $group, $search_path ) = @_;
    print "Subfolder search_path: $search_path\n" if $serverconfig{verbose};

    #TODO: add function to create LTS-snaphosts of latest working backup
    my @subfolders = `find "$search_path/current" -mindepth 1 -maxdepth 1 -xdev -type d -not -empty -print | sort`;

    if ( $#subfolders == -1 ) {
        push( @subfolders, $search_path );
        logit( $taskid, 'LTS', $group, "ERROR: eval subfolders failed, use now with:\n @subfolders" );
    } else {
        logit( $taskid, 'LTS', $group, "found subfolders:\n @subfolders" );
    }

    my $jobid = create_timeid( $taskid, $group );
    foreach my $subfolder (@subfolders) {
        chomp $subfolder;
        my $ltsjob = {
            taskid      => $taskid,
            jobid       => $jobid,
            group       => $group,
            host        => $host,
            path        => "$subfolder",
            source_path => "$search_path",
            ifsub       => 1,
        };
        push( @queue, $ltsjob );
    }
    return 1;
}

sub _eval_dar_options {
    my ($group, $taskid) = @_;
    my $dar_options = $ltsjobs{"$group"}->{ltsconfig}->{lts_dar_options};

    return ($dar_options);
}

sub _eval_dar_source {
    my ( $group, $path ) = @_;
    my $dar_source;

    if ( $ltsjobs{"$group"}->{ltsconfig}->{LTS_STORE_MODUS} eq 'snapshots' ) {
        $dar_source = "$path/current";
    } else {
        $dar_source .= "/snap_LTS";
    }

    return $dar_source;
}

sub _setup_dar_target {
    my ( $group, $ltsconfig, $taskid ) = @_;

    my $nfs_share         = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_share};
    my $nfs_mount_options = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_mount_options};
    my $dar_target        = $ltsjobs{"$group"}->{ltsconfig}->{lts_nfs_mount};

    if (`cat /proc/mounts | grep $dar_target`) {
        logit( $taskid, 'LTS', $group, "$dar_target is mounted" ) if $serverconfig{verbose};;
    } else {
        logit( $taskid, 'LTS', $group, "$dar_target is not mounted" ) if $serverconfig{verbose};;
        my $mount_cmd = "mount -t nfs -o $nfs_mount_options $nfs_share $dar_target";
        $mount_cmd = "echo $mount_cmd" if $serverconfig{dryrun};
        my $mount_result = system($mount_cmd);
        if ($mount_result == 0) {
            logit( $taskid, 'LTS', $group, "$dar_target is now mounted" ) if $serverconfig{verbose};;
        } else {
            print "$taskid, $group, Mount error for $dar_target: $mount_result\n";
            logit( $taskid, 'LTS', $group, "Mount error for $dar_target: $mount_result" ) if $serverconfig{verbose};;
            return;
        }
    }

    $dar_target .= "/$ltsconfig->{LTS_PREFIX}/";

    if ( ! -e $dar_target ) {
        print "Create missing dar_target: $dar_target\n";
        system("mkdir -p $dar_target") unless $serverconfig{dryrun};
    }

    return $dar_target;
}

sub _execute_dar {
    my ( $ltsjob, $dar_options ) = @_;
    my $tid            = threads->tid;
    my $taskid         = $ltsjob->{taskid};
    my $jobid          = $ltsjob->{jobid};
    my $group          = $ltsjob->{group};
    my $host           = $ltsjob->{host};
    my $path           = $ltsjob->{path};
    my $source_path    = $ltsjob->{source_path};
    my $ifsub          = $ltsjob->{ifsub};
    my $dryrun         = $ltsjob->{'dryrun'};
    my $cron           = $ltsjob->{'cron'};
    my $noreport       = $ltsjob->{'noreport'};

    my $ltsconfig  = $ltsjobs{"$group"}->{ltsconfig};

    my $dar_source                 = _eval_dar_source($group, $path);
    my $dar_target                 = _setup_dar_target($group, $ltsconfig, $taskid);

    $dar_target .= "$host" if $host;

    my $dar_cmd  = $serverconfig{path_dar};
    $dar_cmd .= " $dar_options -c $dar_target -R $dar_source";

    print "$taskid, $group, Executing dar for group $group\n" if $serverconfig{verbose};
    print "$taskid, $group, dar Command: $dar_cmd\n" ;

    local ( *HIS_IN, *HIS_OUT, *HIS_ERR );
    $dar_cmd = "echo $dar_cmd" if $serverconfig{dryrun};

    my $darpid = open3( *HIS_IN, *HIS_OUT, *HIS_ERR, "$dar_cmd" );

    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    close HIS_IN;
    close HIS_OUT;
    close HIS_ERR;

    waitpid( $darpid, 0 );

    logit( $taskid, $host, $group, "dar[$darpid] STDOUT: @outlines" ) if ( @outlines && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "ERROR: dar[$darpid] STDERR: @errlines" ) if @errlines;
    logit( $taskid, $host, $group, "ERROR: dar[$darpid] child exited with status of $?" ) if $?;

    my $errcode  = 0;
    my $endstamp = time();

    if (@errlines) {
        foreach my $errline (@errlines) {
            if ( $errline =~ /.* \(code (\d+)/ ) {
                $errcode = $1;
                logit( $taskid, $host, $group, "dar errorcode: $errcode" );
            }
        }
    } else {
        logit( $taskid, $host, $group, "dar successful for host $host group $group path $path" );
    }


}

1;
