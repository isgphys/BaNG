package BaNG::Wipe;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Hosts;
use BaNG::Reporting;
use BaNG::BTRFS;
use Date::Parse;

use Exporter 'import';
our @EXPORT = qw(
    list_folders_to_wipe
    backup_folders_stack
    wipe_maxcount
    fill_stacks
    wipe_worker
);

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
    my %stack = fill_stacks( \@available, wipe_maxcount( $host, $group ) );

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

sub wipe_maxcount {
    my ( $host, $group ) = @_;

    my %maxcount = (
        daily   => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_DAILY},
        weekly  => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_WEEKLY},
        monthly => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_MONTHLY},
    );

    return \%maxcount;
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

1;
