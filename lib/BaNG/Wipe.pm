package BaNG::Wipe;

use 5.010;
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
    my ($host, $group, $force, @available_backup_folders) = @_;
    my @folders_to_wipe;

    return () if $#available_backup_folders == 0;

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
                    epoch  => str2time($+{date}),
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
    my %stack = fill_stacks( \@available, wipe_maxcount($host, $group) );

    # $stack{wipe} contains the epochs of the folders to be wiped
    foreach my $date ( keys %available_backups ) {
        if ( $available_backups{$date}{epoch} ~~ @{$stack{wipe}} ) {
            push( @folders_to_wipe, $available_backups{$date}{folder} );
        }
    }

    # generate wipe report with content of stacks
    if ( $serverconfig{debuglevel} >= 2 ) {
        my $wipe_report = "Wipe report\n";
        foreach my $type (qw( daily weekly monthly wipe )) {
            $wipe_report .= "\t" . uc($type) . " : " . ( $#{$stack{$type}} + 1 ) . "\n";
            foreach my $epoch ( @{$stack{$type}} ) {
                foreach my $date ( keys %available_backups ) {
                    if ( $epoch eq $available_backups{$date}{epoch} ) {
                        $wipe_report .= "\t$available_backups{$date}{folder}\n";
                    }
                }
            }
        }
        logit( $host, $group, $wipe_report );
    }

    # don't automatically wipe too many backups
    if ( $force ) {
        logit( $host, $group, "Wipe WARNING: forced to wipe, namely " . ( $#folders_to_wipe + 1 ) . "." );
    } elsif ( $#folders_to_wipe >= $serverconfig{auto_wipe_limit} ) {
        logit( $host, $group, "Wipe WARNING: too many folders to wipe, namely " . ( $#folders_to_wipe + 1 ) . ". Wipe manually or use --force." );
        return ();
    }

    return @folders_to_wipe;
}

sub fill_stacks {
    my ($available_ref, $maxcount_ref) = @_;
    my @available = @{$available_ref};
    my %maxcount  = %{$maxcount_ref};

    my %stack;
    my %seconds = (
        daily   =>  1*24*3600,
        weekly  =>  7*24*3600,
        monthly => 28*24*3600,
    );

    # sort stack to contain most recent backup as first element
    @available = reverse sort( @available );

    # start intervals at time of most recent backup
    my $start = $available[0];
    my $end;

    foreach my $type ( qw( daily weekly monthly )) {
        foreach my $interval (1..$maxcount{$type}) {
            $end = $start - $seconds{$type};

            # list backups inside a given interval
            my @inside = grep{ $start >= $_ && $_ > $end } @available;

            # sort to keep oldest backup, except in daily we keep most recent
            @inside = sort @inside unless $type eq 'daily';

            # keep one backup for that interval, wipe the other
            if ( @inside ) {
                push( @{$stack{$type}}, shift(@inside) );
                push( @{$stack{wipe}}, @inside );
            }

            $start = $end;
        }

        # wipe if a backup is even older than last interval
        if ( $type eq 'monthly' ) {
            my @outside = grep{ $_ <= $end } @available;
            push( @{$stack{wipe}}, @outside );
        }
    }

    return %stack;
}

sub wipe_maxcount {
    my ($host, $group) = @_;

    my %maxcount = (
        daily   => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_DAILY},
        weekly  => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_WEEKLY},
        monthly => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_MONTHLY},
    );

    return \%maxcount;
}

1;
