package BaNG::Wipe;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use Date::Parse;

use Exporter 'import';
our @EXPORT = qw(
    list_folders_to_wipe
    wipe_maxcount
    fill_stacks
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
                if ( $available_backups{$+{date}} < $+{time} ) {
                    push( @folders_to_wipe, $available_backups{$+{date}}{folder} );
                } else {
                    push( @folders_to_wipe, $folder );
                }
            }
            if ( ( !exists $available_backups{$+{date}} )
              || ( $available_backups{$+{date}} < $+{time} ) ) {
                # store by date to force same time (midnight) for all
                $available_backups{$+{date}} = {
                    folder => $folder,
                    epoch  => str2time( $+{date} ),
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

1;
