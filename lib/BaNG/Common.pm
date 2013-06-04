package BaNG::Common;

use POSIX qw( floor );

use BaNG::Config;

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
        my @backup_folders = get_backup_folders($host, $group);
        $count_backup_folders{$group} = $#backup_folders + 1;
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
