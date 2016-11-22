
package BaNG::TM_rsync;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BackupServer;
use IPC::Open3;

use Exporter 'import';
our @EXPORT = qw(
    execute_rsync
    check_rsync_status
);


sub _eval_rsync_options {
    my ( $host, $group, $taskid ) = @_;
    my $rsync_options = '';
    my $hostconfig    = $hosts{"$host-$group"}->{hostconfig};

    $rsync_options .= '--stats ';
    $rsync_options .= '-a '            if $hostconfig->{BKP_RSYNC_ARCHIV};
    $rsync_options .= '-x '            if $hostconfig->{BKP_RSYNC_ONE_FS};
    $rsync_options .= '-R '            if $hostconfig->{BKP_RSYNC_RELATIV};
    $rsync_options .= '-H '            if $hostconfig->{BKP_RSYNC_HLINKS};
    $rsync_options .= '-W '            if $hostconfig->{BKP_RSYNC_WHOLEFILE};
    $rsync_options .= '-z '            if $hostconfig->{BKP_RSYNC_COMPRESS};
    $rsync_options .= '--delete '      if $hostconfig->{BKP_RSYNC_DELETE};
    $rsync_options .= '--force '       if $hostconfig->{BKP_RSYNC_DELETE_FORCE};
    $rsync_options .= '--numeric-ids ' if $hostconfig->{BKP_RSYNC_NUM_IDS};
    $rsync_options .= '--inplace '     if $hostconfig->{BKP_RSYNC_INPLACE};
    $rsync_options .= '--acls '        if $hostconfig->{BKP_RSYNC_ACL};
    $rsync_options .= '--xattrs '      if $hostconfig->{BKP_RSYNC_XATTRS};
    $rsync_options .= '--no-D '        if $hostconfig->{BKP_RSYNC_NODEVICES};
    $rsync_options .= '-v '            if ( $serverconfig{verbose} && ( $serverconfig{verboselevel} == 3 ) );
    $rsync_options .= "-M '$hostconfig->{BKP_RSYNC_REMOTE_OPT}' "          if $hostconfig->{BKP_RSYNC_REMOTE_OPT};
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

sub check_rsync_status {
    my ( $rsync_err ) = @_;
    my $status = 1;

    if ( scalar grep $rsync_err eq $_, @{ $serverconfig{'rsync_err_ok'} }) {
        $status = 0;
    }

    return $status;
}

sub execute_rsync {
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

1;
