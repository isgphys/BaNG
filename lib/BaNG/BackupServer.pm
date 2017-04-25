package BaNG::BackupServer;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Converter;
use BaNG::RemoteCommand;
use BaNG::Reporting;
use BaNG::BTRFS;
use Date::Parse;
use POSIX qw( floor strftime );
use Time::HiRes qw( gettimeofday );
use Net::Ping;
use YAML::Tiny qw( LoadFile );
use JSON;

use Exporter 'import';
our @EXPORT = qw(
    bkp_to_current_server
    get_fsinfo
    get_lockfiles
    get_backup_folders
    check_client_connection
    check_client_rshell_connection
    get_automount_paths
    check_target_exists
    create_target
    create_lockfile
    remove_lockfile
    check_lockfile
    writeto_lockfile
    eval_bkptimestamp
    create_timeid
    create_link_current
    rename_failed_backup
    create_generic_exclude_file
    remove_generic_exclude_file
    reorder_queue_by_priority
);

sub _check_fill_level {
    my ($level) = @_;
    my $css_class = '';

    if ( $level > 98 ) {
        $css_class = 'alert_red';
    } elsif ( $level > 90 ) {
        $css_class = 'alert_orange';
    } elsif ( $level > 80 ) {
        $css_class = 'alert_yellow';
    }

    return $css_class;
}

sub bkp_to_current_server {
    my ( $host, $group, $taskid ) = @_;

    # make sure backup's target host matches local hostname
    my $bkp_target_host = $hosts{"$host-$group"}->{hostconfig}->{BKP_TARGET_HOST};
    if ( $bkp_target_host ne $servername && $bkp_target_host ne '*' ) {
        logit( $taskid, $host, $group, "Skipping host $host group $group for server $bkp_target_host instead of $servername" ) if $serverconfig{verbose};
        return 0;
    }

    return 1;
}

sub get_fsinfo {
    my %fsinfo;
    foreach my $server ( keys %servers ) {
        my @mounts = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_df" );

        foreach my $mount (@mounts) {
            $mount =~ qr{
                ^(?<filesystem> [\/\w\d-]+)
                \s+(?<fstyp> [\w\d]+)
                \s+(?<blocks> [\d]+)
                \s+(?<used> [\d]+)
                \s+(?<available>[\d]+)
                \s+(?<usedper> [\d]+)
                .\s+(?<mountpt> [\/\w\d-]+)
            }x;

            $fsinfo{$server}{$+{mountpt}} = {
                filesystem => $+{filesystem},
                mount      => $+{mountpt},
                fstyp      => $+{fstyp},
                blocks     => num2human( $+{blocks} ),
                used       => num2human( $+{used} * 1024, 1024 ),
                available  => num2human( $+{available} * 1024, 1024 ),
                freediff   => '',
                rwstatus   => '',
                used_per   => $+{usedper},
                css_class  => _check_fill_level( $+{usedper} ),
            };
        }

        @mounts = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/procmounts" );
        foreach my $mount (@mounts) {
            $mount =~ qr{
                ^(?<device>[\/\w\d-]+)
                \s+(?<mountpt>[\/\w\d-]+)
                \s+(?<fstyp>[\w\d]+)
                \s+(?<mountopt>[\w\d\,\=\/]+)
                \s+(?<dump>[\d]+)
                \s+(?<pass>[\d]+)$
            }x;

            my $mountpt  = $+{mountpt};
            my $mountopt = $+{mountopt};

            $fsinfo{$server}{$mountpt}{rwstatus} = 'check_red' if $mountopt =~ /ro/;
        }

        if ( $server eq $servername ) {
            @mounts = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_di" );
            foreach my $mount (@mounts) {
                $mount =~ qr{
                    ^(?<filesystem> [\/\w\d-]+)
                    \s+(?<fstyp>[\w\d]+)
                    \s+(?<blocks>[\d]+)
                    \s+(?<used>[\d]+)
                    \s+(?<available>[\d]+)
                    \s+(?<free>[\d]+)
                    \s+(?<usedper>[\d]+)
                    .\s+(?<mountpt>[\/\w\d-]+)
                }x;

                my $freediff    = $+{free} - $+{available};
                my $freediffper = 100 / $+{free} * $freediff;

                $fsinfo{$server}{$+{mountpt}}{freediff} = ( $freediffper > 10 ) ? num2human( $freediff * 1024, 1024 ) : '';
            }
        }
    }

    return \%fsinfo;
}

sub check_client_connection {
    my ( $host, $gwhost ) = @_;

    my $state = 0;
    my $msg   = 'Host offline';
    my $p     = Net::Ping->new( 'tcp', 2 );

    if ( $p->ping($host) ) {
        $state = 1;
        $msg   = 'Host online';
    } elsif ($gwhost) {
        $state = 1;
        $msg   = 'Host not pingable because behind a Gateway-Host';
    }
    $p->close();

    return $state, $msg;
}

sub check_client_rshell_connection {
    my ( $host, $rshell, $gwhost ) = @_;

    my $result;
    my $state = 0;
    my $msg   = "$rshell not working correctly";

    if ( $gwhost || $host eq "localhost" ) {
        $state = 1;
        $msg   = 'Could not test RemoteShell because Host is behind a Gateway-Host';
    } else {
        $result = `timeout 10 $rshell $host uname -a 2>&1`;

        if ( $result =~ /^(Linux|Darwin)/) {
            $state = 1;
            $msg   = "$rshell ok";
        }else{
            $msg  .= " - $result";
        }
    }

    return $state, $msg;
}

sub get_backup_folders {
    my ( $host, $group, $folder_type ) = @_;
    $folder_type ||= 0;
    my $bkpdir = targetpath( $host, $group );
    my $server = $hosts{"$host-$group"}{hostconfig}{BKP_TARGET_HOST};
    my @backup_folders;

    my $REGEX = "[0-9\./_]*";                                           # default, show all good folders
    $REGEX    = ".*_failed" if $folder_type == 1;                       # show all *_failed folders
    $REGEX    = "\\([0-9\./_]*\\|.*_failed\$\\)" if $folder_type == 2;  # show all folders, except "current" folder

    if ( $server eq $servername ) {
        @backup_folders = `find $bkpdir -mindepth 1 -maxdepth 1 -type d -regex '${bkpdir}/$REGEX' 2>/dev/null`;
    } else {
        @backup_folders = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_getBackupFolders", $bkpdir );
    }
    return @backup_folders;
}

sub check_target_exists {
    my ( $host, $group ) = @_;
    my $snapshot    = ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) ? 1 : 0 ;
    my $target      = targetpath( $host, $group );
    my $return_code = 0; # 0 = not available, 1 = available

    if ( -e $target ) {
        $return_code = 1;
    }
    if ( $snapshot ) {
        $target .= '/current';

        if ( -e $target ) {
            $return_code = 1;
        }
    }
    return $return_code;
}

sub create_target {
    my ( $host, $group, $taskid ) = @_;
    $taskid       ||= 0;
    my $snapshot    = ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) ? 1 : 0 ;
    my $target      = targetpath( $host, $group );
    my $return_code = 0;
    my $return_msg  = 'Folder still exists';

#    Running as root!!
    if ( $< == 0 ) {
        unless ( -e $target ) {
            system("mkdir -p $target") unless $serverconfig{dryrun};
            $return_code = 1;
            $return_msg  = 'Created folder';
        }

        if ( $snapshot ) {
            if ( -x $serverconfig{path_btrfs} ) {
                $target .= '/current';

                unless ( -e $target ) {
                    system("$serverconfig{path_btrfs} subvolume create $target >/dev/null 2>&1") unless $serverconfig{dryrun};
                    $return_code = 1;
                    $return_msg = 'Created btrfs subvolume';
                }
            }
        }
    } else {
        my $server = $hosts{"$host-$group"}{hostconfig}{BKP_TARGET_HOST};
        my $data   = {
            "dryrun"   => $serverconfig{dryrun},
            "mode"     => "create",
            "snapshot" => $snapshot,
            "target"   => $target,
            };

        my $json_text = to_json($data, { pretty => 0 });
        $json_text    =~ s/"/\\"/g; # needed for correct remotesshwrapper transfer

        my ( $feedback ) = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_worker", $json_text );

        my $feedback_ref = from_json( $feedback );
        my $return_code  = $feedback_ref->{'return_code'};
        my $return_msg   = $feedback_ref->{'return_msg'};
    }

    return ($return_code, $return_msg);
}

sub get_automount_paths {
    my ($ypfile) = @_;
    $ypfile ||= 'auto.backup';

    my %automnt;

    if ( $serverconfig{path_ypcat} && -e $serverconfig{path_ypcat} ) {

        my @autfstbl = `$serverconfig{path_ypcat} -k $ypfile`;

        foreach my $line (@autfstbl) {
            if (
                $line =~ qr{
                (?<parentfolder>[^\s]*) \s*
                \-fstype\=autofs \s*
                yp\:(?<ypfile>.*)
                }x
                )
            {
                # recursively read included yp files
                my $parentfolder = $+{parentfolder};
                my $submounts    = get_automount_paths( $+{ypfile} );
                foreach my $mountpt ( keys %{$submounts} ) {
                    $automnt{$mountpt} = {
                        server => $submounts->{$mountpt}->{server},
                        path   => "$parentfolder/$submounts->{$mountpt}->{path}",
                    };
                }
            } elsif (
                $line =~ qr{
                (?<mountpt>[^\s]*) \s
                (?<server>[^\:]*) :
                (?<mountpath>.*)
                }x
                )
            {
                $automnt{$+{mountpath}} = {
                    server => $+{server},
                    path   => $+{mountpt},
                };
            }
        }
    }

    return \%automnt;
}

sub eval_bkptimestamp {
    my ( $host, $group ) = @_;

    my $bkptimestamp = eval( $hosts{"$host-$group"}->{hostconfig}->{BKP_FOLDER} );
    chomp($bkptimestamp);

    return $bkptimestamp;
}

#################################
# Lockfile
#
sub lockfile {
    my ( $host, $group, $path ) = @_;

    $group = "LTS-$group" if ($serverconfig{bkpmode} eq "lts");

    $path =~ s/^://g;
    $path =~ s/\s:/\+/g;
    $path =~ s/\//%/g;
    my $lockfilename = "${host}_${group}_${path}";
    my $lockfile     = "$serverconfig{path_lockfiles}/$lockfilename.lock";

    return $lockfile;
}

sub create_lockfile {
    my ( $taskid, $host, $group, $path ) = @_;

    my $lockfile = lockfile( $host, $group, $path );

    if ( -e $lockfile ) {
        my @processes = `ps aux | grep -v grep | grep '$host' | grep '$path' | awk '{print \$2}'`;
        if ( @processes ) {
            logit( $taskid, $host, $group, "ERROR: lockfile $lockfile still exists" );
            logit( $taskid, $host, $group, 'ERROR: Backup canceled, still running backup!' );
            return 0;
        }
    }

    logit( $taskid, $host, $group, "Created lockfile $lockfile" );
    writeto_lockfile( $taskid, $host, $group, $path, "taskid", $taskid);

    return 1;
}

sub remove_lockfile {
    my ( $taskid, $host, $group, $path ) = @_;

    my $lockfile = lockfile( $host, $group, $path );
    unlink $lockfile unless $serverconfig{dryrun};
    logit( $taskid, $host, $group, "Removed lockfile $lockfile" );

    return 1;
}

sub split_lockfile_name {
    my ($lockfile) = @_;
    my ( $host, $group, $path, $timestamp ) = $lockfile =~ /^([\w\d\.-]+)_([\w\d-]+)_(.*)\.lock (.*)/;
    my $file = "${host}_${group}_${path}.lock";

    $path =~ s/%/\//g;
    $path =~ s/\'//g;
    $path =~ s/\+/ :/g;
    $path =~ s/^\//:\//g;

    return $host, $group, $path, $timestamp, $file;
}

sub check_lockfile {
    my ( $taskid, $host, $group ) = @_;

    my @lockfiles;
    my $ffr_obj = File::Find::Rule->file()
                                  ->name("${host}_${group}_*.lock")
                                  ->relative
                                  ->maxdepth(1)
                                  ->start($serverconfig{path_lockfiles});

    while ( my $lockfile = $ffr_obj->match() ) {
        push( @lockfiles, $lockfile );
    }

    logit( $taskid, $host, $group, "Check for running backup tasks" );

    if ( $#lockfiles > -1 ) {
        logit( $taskid, $host, $group, 'ERROR: Wipe canceled, still ' . ( $#lockfiles + 1 ) . ' running backup!' );
        return 0;
    }

    return 1;
}

sub get_lockfiles {
    my %lockfiles;

    foreach my $server ( keys %servers ) {
        my @lockfiles = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_getLockFile", "$prefix/$servers{$server}{serverconfig}{path_lockfiles}/" );

        foreach my $lockfile (@lockfiles) {
            my ( $host, $group, $path, $timestamp, $file ) = split_lockfile_name($lockfile);
            my ($lockfile_data) = remote_command( $server, "$servers{$server}{serverconfig}{remote_app_folder}/bang_readLockFile", "$prefix/$servers{$server}{serverconfig}{path_lockfiles}/$lockfile" );

            print "$lockfile_data\n";

            chomp $lockfile_data;
            my ($taskid, $shpid, $cron) = split('-', $lockfile_data);

            $lockfiles{$server}{"$host-$group-$path"} = {
                taskid    => $taskid,
                host      => $host,
                group     => $group,
                path      => $path,
                shpid     => $shpid || '',
                cron      => $cron || '',
                timestamp => $timestamp,
            };
        }
    }

    return \%lockfiles;
}

sub writeto_lockfile {
    my ( $taskid, $host, $group, $path, $key, $value ) = @_;
    my $lockfile = lockfile( $host, $group, $path );

    unless ( $serverconfig{dryrun} ) {
        system("echo \"$key: $value\" >> \"$lockfile\"");
    }
    logit( $taskid, $host, $group, "Write to lockfile $lockfile -- $key: $value" ) if $serverconfig{verbose};
}

#################################
# Helper subroutines
#
sub create_timeid {
    my ( $taskid, $host, $group ) = @_;

    my ( $s, $usec ) = gettimeofday;
    my $timeid = strftime '%Y%m%d%H%M%S', localtime $s;
    $timeid .= sprintf '%06d', $usec;
    $timeid =~ s/\n//g;
    $host   ||= "SERVER";
    $group  ||= "GLOBAL";
    $taskid ||= $timeid;
    logit( $taskid, $host, $group, "Created TimeID: $timeid" );

    return $timeid;
}

sub create_link_current {
    my ( $taskid, $host, $group, $bkptimestamp ) = @_;

    my $link_source  = targetpath( $host, $group ) . '/' . $bkptimestamp;
    my $link_dest    = targetpath( $host, $group ) . '/current';
    my $ln_cmd       = "/bin/ln -s";

    if ( -l $link_dest ){
        unlink $link_dest unless $serverconfig{dryrun};
        logit( $taskid, $host, $group, "Delete existing current symlink for host $host group $group" );
    }

    my $link_cmd = "$ln_cmd $link_source $link_dest >/dev/null 2>&1";
    $link_cmd = "echo $link_cmd" if $serverconfig{dryrun};
    logit( $taskid, $host, $group, "Create symlink for host $host group $group using $link_cmd" );
    system($link_cmd) and logit( $taskid, $host, $group, "ERROR: creating symlink for $host-$group: $!" );

    return 1;
}

sub rename_failed_backup {
    my ( $taskid, $host, $group, $bkptimestamp ) = @_;

    my $failed_source  = targetpath( $host, $group ) . '/' . $bkptimestamp;
    my $failed_dest    = targetpath( $host, $group ) . '/' . $bkptimestamp . "_failed";
    my $mv_cmd       = "/bin/mv";

    if ( -e $failed_source ) {
        my $rename_cmd = "$mv_cmd $failed_source $failed_dest >/dev/null 2>&1";
        $rename_cmd = "echo $rename_cmd" if $serverconfig{dryrun};
        logit( $taskid, $host, $group, "Rename failed folder for host $host group $group using $rename_cmd" );
        system($rename_cmd) and logit( $taskid, $host, $group, "ERROR: renaming failed folder for $host-$group: $!" );
    } else {
        logit( $taskid, $host, $group, "ERROR: $failed_source not exists, skip renaming failed folder for host $host group $group" );
    }

    return 1;
}

sub _generic_exclude_file {
    my ( $host, $group, $jobid ) = @_;
    my $exclsubfolderfilename = "generated.${host}_${group}_${jobid}";
    my $exclsubfolderfile     = "$serverconfig{path_excludes}/$exclsubfolderfilename";

    return $exclsubfolderfile;
}

sub create_generic_exclude_file {
    my ( $taskid, $host, $group, $jobid ) = @_;
    my $exclsubfolderfile        = _generic_exclude_file( $host, $group, $jobid );

    unless ( $serverconfig{dryrun} ) {
        system("touch \"$exclsubfolderfile\"") and logit( $taskid, $host, $group, "ERROR: could not create generated excludefile $exclsubfolderfile" );
    }
    logit( $taskid, $host, $group, "Create generated exclude file $exclsubfolderfile" );
    return $exclsubfolderfile;
}

sub remove_generic_exclude_file {
    my ( $taskid, $host, $group, $jobid ) = @_;
    my $exclsubfolderfile        = _generic_exclude_file( $host, $group, $jobid );

    if ( -e $exclsubfolderfile ) {
        unlink "$exclsubfolderfile";
    }
    logit( $taskid, $host, $group, "Remove generated exclude file $exclsubfolderfile" );

    return 1;
}

sub reorder_queue_by_priority {
    my ( $taskid, $host, $group ) = @_;
    my @prio_queue;
    my @prio_queue_sorted;
    $host  ||= 'SERVER';
    $group ||= 'GLOBAL';

    logit( $taskid, $host, $group, "reorder queue by priority!" );

    # add priority information to all queued backup jobs
    foreach my $bkpjob (@queue) {
        my $host  = $bkpjob->{host};
        my $group = $bkpjob->{group};
        my $path  = $bkpjob->{path};
        $path =~ s/'//g;

        my $prio = $hosts{"$host-$group"}->{hostconfig}->{BKP_PRIORITY}->{"$path"} || 0;
        $bkpjob->{priority} = $prio;
        print "$path set priority to $prio\n" if $serverconfig{verbose};
        push( @prio_queue, $bkpjob );
    }

    # reorder queue by priority
    print "Final queue order: \n" if $serverconfig{verbose};
    foreach my $bkpjob ( sort { $a->{priority} <=> $b->{priority} } @queue ) {
        print "$bkpjob->{priority} $bkpjob->{path} $bkpjob->{dosnapshot}\n" if $serverconfig{verbose};
        push( @prio_queue_sorted, $bkpjob );
    }

    if ( $#queue == $#prio_queue_sorted ) {
        @queue = @prio_queue_sorted;
    } else {
        logit( $taskid, $host, $group, "ERROR: reorder_queue_by_priority queue lengths don't match!" );
    }

    return 1;
}

1;
