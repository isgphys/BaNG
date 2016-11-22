package BaNG::Wipe;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::BackupServer;
use BaNG::Reporting;
use BaNG::BTRFS;
use Date::Parse;

use Exporter 'import';
our @EXPORT = qw(
    list_folders_to_wipe
    backup_folders_stack
    fill_stacks
    wipe_worker
);

sub fill_stacks {
    my ( $available_ref, $maxcount_ref ) = @_;
    my @available = @{$available_ref};
    my %maxcount  = %{$maxcount_ref};

    my %stack;
    my %seconds = (
        daily   =>  1 * 24 * 3600,
        weekly  =>  7 * 24 * 3600,
        monthly => 28 * 24 * 3600,
    );

    # sort stack to contain most recent backup as first element
    @available = reverse sort(@available);

    return %stack unless @available;

    # start intervals at time of most recent backup
    my $start = $available[0];
    my $end;

    foreach my $type (qw( daily weekly monthly )) {
        foreach my $interval ( 1 .. $maxcount{$type} ) {
            $end = $start - $seconds{$type};

            # list backups inside a given interval
            my @inside = grep { $start >= $_ && $_ > $end } @available;

            # sort to keep oldest backup, except in daily we keep most recent
            @inside = sort @inside unless $type eq 'daily';

            # keep one backup for that interval, wipe the other
            if (@inside) {
                push( @{$stack{$type}}, shift(@inside) );
                push( @{$stack{wipe}},  @inside );
            }

            $start = $end;
        }

        # wipe if a backup is even older than last interval
        if ( $type eq 'monthly' ) {
            my @outside = grep { $_ <= $end } @available;
            push( @{$stack{wipe}}, @outside );
        }
    }

    return %stack;
}

sub _wipe_maxcount {
    my ( $host, $group ) = @_;

    my %maxcount = (
        daily   => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_DAILY},
        weekly  => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_WEEKLY},
        monthly => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_MONTHLY},
    );

    return \%maxcount;
}

sub list_folders_to_wipe {
    my ( $host, $group, @available_backup_folders ) = @_;
    my @folders_to_wipe;

    return ( wipe => [] ) if $#available_backup_folders == 0;

    # prepare list of available backups
    my %available_backups;
    foreach my $folder (@available_backup_folders) {
        chomp $folder;
        if ( $folder =~ qr{ .*/(?<date>[^_]*) _ (?<time>\d*) }x ) {

            # only keep latest backup of each date, wipe the rest
            if ( exists $available_backups{$+{date}} ) {
                if ( $available_backups{$+{date}}{time} < $+{time} ) {
                    push( @folders_to_wipe, $available_backups{$+{date}}{folder} );
                } else {
                    push( @folders_to_wipe, $folder );
                }
            }
            if ( ( !exists $available_backups{$+{date}} )
              || ( $available_backups{$+{date}}{time} < $+{time} ) ) {
                # store by date to force same time (midnight) for all
                $available_backups{$+{date}} = {
                    folder => $folder,
                    epoch  => str2time( $+{date} ),
                    time   => $+{time},
                };
            }
        }
    }

    # remaining, single backups per day, define list of available epochs
    my @available;
    foreach my $date ( keys %available_backups ) {
        push( @available, $available_backups{$date}{epoch} );
    }

    # determine daily, weekly, monthly and wipe stacks
    my %stack = fill_stacks( \@available, _wipe_maxcount( $host, $group ) );

    # map dates inside stack to corresponding folders
    foreach my $type ( keys %stack ) {
        my @folders;
        foreach my $epoch ( sort @{$stack{$type}} ) {
            foreach my $date ( keys %available_backups ) {
                if ( $epoch == $available_backups{$date}{epoch} ) {
                    push( @folders, $available_backups{$date}{folder} );
                }
            }
        }
        @{$stack{$type}} = @folders;
    }

    # add folders we already marked to be wiped
    push( @{$stack{wipe}}, @folders_to_wipe );

    return %stack;
}

sub backup_folders_stack {
    my ($host) = @_;

    my %backup_folders_stack;
    foreach my $group ( list_groups($host) ) {
        my @available_backup_folders = get_backup_folders( $host, $group );
        my %stack = list_folders_to_wipe( $host, $group, @available_backup_folders );
        $backup_folders_stack{$group} = \%stack;
    }

    return \%backup_folders_stack;
}

sub wipe_worker {
    my ( $host, $group, $taskid, @wipedirs ) = @_;
    $taskid ||= 0;

    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {

        # Limit snapshot wipe to the last x days -> performance issues
        if ( scalar( @wipedirs ) > $serverconfig{snapshot_wipe_limit} ) {
            logit( $taskid, $host, $group, "Wipe WARNING: snapshot limit reached, wipe only oldest $serverconfig{snapshot_wipe_limit} snapshots." );
        }
        @wipedirs = splice( @wipedirs, 0, $serverconfig{snapshot_wipe_limit} );

        delete_btrfs_subvolume( $host, $group, $taskid, join( ' ', @wipedirs ) );
        delete_logfiles( $host, $group, $taskid, @wipedirs );
    } else {
        my $rmcmd = 'rm -Rf';
        $rmcmd = "echo $rmcmd" if $serverconfig{dryrun};
        foreach my $dir (@wipedirs) {
            logit( $taskid, $host, $group, "Wipe $rmcmd $dir for host $host group $group" );
            system("$rmcmd $dir") and logit( $taskid, $host, $group, "ERROR: removing folder $dir for $host-$group: $!" );
        }
    }
    return 1;
}

sub wipe {
    my ( $host, $group, $taskid, $force ) = @_;

    # make sure we are on the correct backup server
    return unless bkp_to_current_server( $host, $group, $taskid );

    # make sure wipe is enabled
    return unless $hosts{"$host-$group"}->{hostconfig}->{WIPE_ENABLED};

    # stop if trying to do bulk wipe if it's not allowed
    #return unless ( ( $group_arg && $host_arg ) || $hosts{"$host-$group"}->{hostconfig}->{WIPE_BULK_ALLOW} );
    return unless ( ( $group && $host ) || $hosts{"$host-$group"}->{hostconfig}->{WIPE_BULK_ALLOW} );

    # check for still running backups
    return unless check_lockfile( $taskid, $host, $group );

    logit( $taskid, $host, $group, "Wipe host $host group $group" );

    my @backup_folders = get_backup_folders( $host, $group );

    # count existing backups
    my $bkpkeep = 0;
    foreach my $type (qw( DAILY WEEKLY MONTHLY )) {
        $bkpkeep += $hosts{"$host-$group"}->{hostconfig}->{"WIPE_KEEP_$type"};
    }
    my $bkpcount = $#backup_folders + 1;

    # get list of folders to wipe
    my %stack = list_folders_to_wipe( $host, $group, @backup_folders );
    my @wipedirs = @{$stack{wipe}};

    logit( $taskid, $host, $group, "Wipe existing: $bkpcount, to wipe: " . ( $#{$stack{wipe}} + 1 ) . ", keeping: $bkpkeep for host $host group $group" );

    # generate wipe report with content of stacks
    if ( $serverconfig{verboselevel} >= 2 ) {
        my $wipe_report = "Wipe report\n";
        foreach my $type ( sort keys %stack ) {
            $wipe_report .= "\t" . uc($type) . " : " . ( $#{$stack{$type}} + 1 ) . "\n";
            foreach my $folder ( @{$stack{$type}} ) {
                $wipe_report .= "\t$folder\n";
            }
        }
        logit( $taskid, $host, $group, $wipe_report );
    }

    # don't automatically wipe too many backups
    if ($force) {
        logit( $taskid, $host, $group, 'Wipe WARNING: forced to wipe, namely ' . ( $#{$stack{wipe}} + 1 ) . '.' );
    } elsif ( $#{$stack{wipe}} >= $serverconfig{auto_wipe_limit} ) {
        logit( $taskid, $host, $group, 'Wipe WARNING: too many folders to wipe, namely ' . ( $#{$stack{wipe}} + 1 ) . '. Wipe manually or use --force.' );
        return ();
    }

    # make sure list contains at least one folder
    if ( !@wipedirs ) {
        logit( $taskid, $host, $group, "Wipe no folder to wipe for host $host group $group" );
        return 1;
    }

    # remove subvolumes or folders
    wipe_worker( $host, $group, ,$taskid, @wipedirs );

    logit( $taskid, $host, $group, "Wipe successful of host $host group $group" );

    return 1;
}

1;
