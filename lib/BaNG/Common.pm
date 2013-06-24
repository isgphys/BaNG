package BaNG::Common;

use BaNG::Config;
use POSIX qw( floor );
use Date::Parse;

use Exporter 'import';
our @EXPORT = qw(
    count_backup_folders
    get_backup_folders
    list_groups
    num2human
    targetpath
    time2human
);

sub targetpath {
    my ($host, $group) = @_;

    my $hostconfig  = $hosts{"$host-$group"}->{hostconfig};
    my $target_path = "$hostconfig->{BKP_TARGET_PATH}/$hostconfig->{BKP_PREFIX}/$host";

    return $target_path;
}

sub get_backup_folders {
    my ($host, $group) = @_;

    my $bkpdir = targetpath( $host, $group );
    my @backup_folders = `find $bkpdir -mindepth 1 -maxdepth 1 -type d -regex '${bkpdir}[0-9\./_]*' 2>/dev/null`;

    return @backup_folders;
}

sub list_groups {
    my ($host) = @_;

    my @groups;
    foreach my $hostgroup (keys %hosts) {
        if ( $hosts{$hostgroup}->{hostname} eq $host ) {
            push( @groups, $hosts{$hostgroup}->{group} );
        }
    }

    return @groups;
}

sub count_backup_folders {
    my ($host) = @_;

    my %count_backup_folders;
    foreach my $group ( list_groups($host) ) {
        my @available_backup_folders = get_backup_folders($host, $group);
        my %available_backups;
        foreach my $folder (@available_backup_folders) {
            chomp $folder;
            if ( $folder =~ qr{ .*/(?<date>[^_]*) _ (?<time>\d*) }x ) {

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

        my %maxcount = %{ &BaNG::Wipe::wipe_maxcount($host, $group) };
        my %stack = &BaNG::Wipe::fill_stacks( \@available, \%maxcount );
        $count_backup_folders{$group} = {
            daily   => ($#{$stack{daily}}   + 1) . '/' . $maxcount{daily},
            weekly  => ($#{$stack{weekly}}  + 1) . '/' . $maxcount{weekly},
            monthly => ($#{$stack{monthly}} + 1) . '/' . $maxcount{monthly},
        };
    }

    return \%count_backup_folders;
}

sub num2human {
    # convert large numbers to K, M, G, T notation
    my ($num, $base) = @_;
    $base ||= 1000.;

    foreach my $unit ( '', qw(K M G T P) ) {
        if ( $num < $base ) {
            if ( $num < 10 && $num > 0 ) {
                return sprintf( "\%.1f \%s", $num, $unit );    # print small values with 1 decimal
            } else {
                return sprintf( "\%.0f \%s", $num, $unit );    # print larger values without decimals
            }
        }
        $num = $num / $base;
    }
}

sub time2human {

    # convert large times in minutes to hours
    my ($minutes) = @_;

    if ( $minutes < 60 ) {
        return sprintf( "%d min", $minutes );
    } else {
        return sprintf( "\%dh\%02dmin", floor( $minutes / 60 ), $minutes % 60 );
    }
}

1;
