package BaNG::Wipe;

use 5.010;
use BaNG::Config;
use BaNG::Reporting;
use Date::Parse;

use Exporter 'import';
our @EXPORT = qw(
    list_folders_to_wipe
);

sub list_folders_to_wipe {
    my ($host, $group, $force, @available_backup_folders) = @_;

    return () if $#available_backup_folders == 0;

    my %maxcount = (
        daily   => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_DAILY},
        weekly  => $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_WEEKLY},
        monthly =>  $hosts{"$host-$group"}->{hostconfig}->{WIPE_KEEP_MONTHLY},
    );
    my %count = (
        daily   => 0,
        weekly  => 0,
        monthly => 0,
    );
    my %seconds = (
        daily   =>  1*24*3600,
        weekly  =>  7*24*3600,
        monthly => 28*24*3600,
    );
    my %previous = (
        daily   => 'available',
        weekly  => 'daily',
        monthly => 'weekly',
    );
    my %stack;
    my %available_backups;
    my @folders_to_wipe;

    # -- prepare list of available backups
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
                $available_backups{$+{date}} = {
                    folder => $folder,
                    epoch  => str2time($+{date}),
                };
            }
        }
    }

    # remaining, single backups per day, define available stack
    foreach my $date ( keys %available_backups ) {
        push( @{$stack{available}}, $available_backups{$date}{epoch} );
    }

    # sort stack to contain oldest backup on top, most recent on bottom
    @{$stack{available}} = sort( @{$stack{available}} );

    # -- fill stacks of daily/weekly/monthly backups
    STACKTYPE: foreach my $type (qw( daily weekly monthly )) {
        STACKITEM: foreach my $i ( reverse( 0 .. $#{$stack{available}} ) ) {

            # determine date of previous backup
            my $lastbkpdate;
            if ( defined $stack{$type}[0] ) {
                $lastbkpdate = $stack{$type}[0];
            } elsif ( $type eq 'daily' ) {
                # force keeping first daily backup
                $lastbkpdate = str2time('2500/01/01');
            } else {
                # oldest backup of previous stack
                $lastbkpdate = ( sort @{$stack{$previous{$type}}} )[0];
                # skip stack if previous stack is empty
                next STACKTYPE unless $lastbkpdate;
            }

            # put backup to stack if enough time has passed
            my $thisbkpdate = @{$stack{available}}[$i];
            if ( $thisbkpdate <= $lastbkpdate - $seconds{$type} ) {
                unshift( @{$stack{$type}}, $thisbkpdate );
                splice( @{$stack{available}}, $i, 1 );
                $count{$type}++;
                last STACKITEM if $count{$type} >= $maxcount{$type};
            }
        }
    }

    # what remains in $stack{available}, is to be wiped
    foreach my $date ( keys %available_backups ) {
        if ( $available_backups{$date}{epoch} ~~ @{$stack{available}} ) {
            push( @folders_to_wipe, $available_backups{$date}{folder} );
        }
    }

    # -- wipe report with content of stacks
    if ( $globalconfig{debuglevel} >= 2 ) {
        my $wipe_report = "Wipe report\n";
        foreach my $type (qw( monthly weekly daily )) {
            $wipe_report .= "\t" . uc($type) . " : " . ( $#{$stack{$type}} + 1 ) . "\n";
            foreach my $epoch ( @{$stack{$type}} ) {
                foreach my $date ( keys %available_backups ) {
                    if ( $epoch eq $available_backups{$date}{epoch} ) {
                        $wipe_report .= "\t$available_backups{$date}{folder}\n";
                    }
                }
            }
        }
        $wipe_report .= "\tWIPE : " . ( $#folders_to_wipe + 1 ) . "\n";
        $wipe_report .= "\t" . join( "\n\t", @folders_to_wipe );
        logit( $host, $group, $wipe_report );
    }

    # -- don't automatically wipe too many backups
    if ( $force ) {
        logit( $host, $group, "Wipe WARNING: forced to wipe, namely " . ( $#folders_to_wipe + 1 ) . "." );
    } else {
        if ( $#folders_to_wipe >= $globalconfig{auto_wipe_limit} ) {
            logit( $host, $group, "Wipe WARNING: too many folders to wipe, namely " . ( $#folders_to_wipe + 1 ) . ". Wipe manually or use --force." );
            return ();
        }
    }

    return @folders_to_wipe;
}

1;
