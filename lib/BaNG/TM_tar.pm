package BaNG::TM_tar;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BackupServer;

use Exporter 'import';
our @EXPORT = qw(
    queue_tar_backup
    run_tar_threads
);

sub queue_tar_backup {
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

    if ( !-e ($serverconfig{path_tar} || "") ) {

        logit( $taskid, 'LTS', $group, "TAR command " . ($serverconfig{path_tar} || "") . " not found!" );

        return 1;
    }

    print "source_path: $source_path\n" if $serverconfig{verbose};

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
    logit( $taskid, 'LTS', $group, "End of queueing backup of group $group" );

    return 1;
}

sub run_tar_threads {
    my ($group, $nthreads_arg, $dryrun_arg) = @_;
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

    my $Q = Thread::Queue->new;
    my @threads = map { threads->create( \&_tar_thread_work, $Q ) } ( 1 .. $nthreads );

    # fill the threading queue
    $Q->enqueue($_) for @queue;

    # Signal that there is no more work to be sent
    $Q->end();

    print "/////////////////////////////////////////////////////\n";
    print "Queuing of threads finished, wait for joining...\n";
    print "/////////////////////////////////////////////////////\n";

    my @final_data;
    # loop until all threads are done
    while ( threads->list() ) {
        foreach my $tj (threads->list(threads::joinable) ) {
            print "\nThread ". $tj->tid() ." finished, joining...\n";

            my (@finishable_ltsjobs_in_thread) = $tj->join;

            foreach my $ltsjob (@finishable_ltsjobs_in_thread) {
                print "$ltsjob->{jobid} $ltsjob->{hostname}\n";
                push (@final_data, $ltsjob );
            }
            my (@remaining) = threads->list(threads::running);
            print "\t",scalar(@remaining)," of $nthreads threads remain\n";
        }

        unless ( threads->list() ) {
            print "\nAll threads are joined! ". $#final_data ." entries found:\n";

            foreach my $ltsjob (sort { $a->{jobid} cmp $b->{jobid} } @final_data) {
                print "$ltsjob->{jobid} $ltsjob->{hostname} $ltsjob->{path}\n";
            }
        }
    }

    return 0;
}

sub _tar_thread_work {
    my ($Q) = @_;
    my @finishable_ltsjobs_in_thread;

    while ( my $ltsjob = $Q->dequeue ) {
        my $tid            = threads->tid;
        my $taskid         = $ltsjob->{taskid};
        my $jobid          = $ltsjob->{jobid};
        my $group          = $ltsjob->{group};
        my $host           = $ltsjob->{host};
        my $path           = $ltsjob->{path};
        my $srcfolder      = $ltsjob->{srcfolder};
        my $dryrun         = $ltsjob->{'dryrun'};
        my $cron           = $ltsjob->{'cron'};
        my $noreport       = $ltsjob->{'noreport'};
        my $exclsubfolders = $ltsjob->{'exclsubfolders'} || 0;

        my $random_integer = int( rand(7) ) + 1;
        $random_integer    = 0 if ( $dryrun );

        logit( $taskid, 'LTS', $group, "Thread $tid sleep $random_integer sec. for $host-$group ($path)" );
        sleep($random_integer);
        logit( $taskid, 'LTS', $group, "Thread $tid working on $group ($path)" );
        my $tar_err = _execute_tar( $taskid, $group, $path, $host );

        my $ltsjob = {
            jobid        => $jobid,
            hostname => $host,
        };
        push(@finishable_ltsjobs_in_thread, $ltsjob);
    }

   return (@finishable_ltsjobs_in_thread);
}

sub _queue_subfolders {
    my ( $taskid, $host, $group, $search_path ) = @_;
    print "search_path: $search_path\n" if $serverconfig{verbose};

    #TODO: add function to create LTS-snaphosts of latest working backup
    my @subfolders = `find "$search_path/current" -mindepth 1 -maxdepth 1 -xdev -type d -not -empty -print | sort`;

    if ( $#subfolders == -1 ) {
        push( @subfolders, $search_path );
        logit( $taskid, 'LTS', $group, "ERROR: eval subfolders failed, use now with:\n @subfolders" );
    } else {
        logit( $taskid, 'LTS', $group, "found subfolders:\n @subfolders" );
    }

    foreach my $subfolder (@subfolders) {
        my $jobid = create_timeid( $taskid, $group );
        my ( $host ) = $subfolder =~ /([a-z0-9-]*)$/;
        chomp $subfolder;
        my $ltsjob = {
            taskid       => $taskid,
            jobid        => $jobid,
            group        => $group,
            host         => $host,
            path         => "$subfolder",
            srcfolder    => "$searchpath",
        };
        print "Push-Queue JobID: $ltsjob->{jobid} Group: $ltsjob->{group} srcfolder: $ltsjob->{srcfolder} path: $ltsjob->{path}\n" if $serverconfig{verbose};
        push( @queue, $ltsjob );
    }
    return 1;
}

sub _eval_tar_options {
    my ($group, $taskid) = @_;
    my $tar_options = $ltsjobs{"$group"}->{ltsconfig}->{lts_tar_options};
    my $tar_helper  = _create_tar_helper();

    logit( $taskid, 'LTS', $group, "tar helper script $tar_helper created" );

    $tar_options .= " -F $tar_helper";

    return ($tar_options, $tar_helper);
}

sub _eval_tar_source {
    my ( $group, $path ) = @_;
    my $tar_source;

    if ( $ltsjobs{"$group"}->{ltsconfig}->{LTS_STORE_MODUS} eq 'snapshots' ) {
        $tar_source = "$path/current";
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

    $tar_target .= "/$ltsconfig->{LTS_PREFIX}/";

    return $tar_target;
}

sub _execute_tar {
    my ( $taskid, $group, $path, $host ) = @_;
    my $ltsconfig  = $ltsjobs{"$group"}->{ltsconfig};

    my ($tar_options, $tar_helper) = _eval_tar_options($group, $taskid);
    my $tar_source                 = _eval_tar_source($group, $path);
    my $tar_target                 = _setup_tar_target($group, $ltsconfig, $taskid);

    $tar_target .= "$host" if $host;

    my $tar_cmd  = $serverconfig{path_tar};

    print "$taskid, $group, Tar Command: $tar_cmd $tar_options -cf $tar_target $tar_source\n" ;
    print "$taskid, $group, Executing tar for group $group\n";

    _delete_tar_helper($tar_helper);
}

1;
