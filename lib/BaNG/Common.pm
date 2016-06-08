package BaNG::Common;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::BTRFS;
use Date::Parse;
use POSIX qw( floor );

use Exporter 'import';
our @EXPORT = qw(
    list_groups
    list_groupmembers
    get_automount_paths
    num2human
    targetpath
    check_target_exists
    time2human
);

sub targetpath {
    my ( $host, $group ) = @_;

    my $hostconfig  = $hosts{"$host-$group"}->{hostconfig};
    my $target_path = "$hostconfig->{BKP_TARGET_PATH}/$hostconfig->{BKP_PREFIX}/$host";

    return $target_path;
}

sub check_target_exists {
    my ( $host, $group, $taskid, $create ) = @_;
    my $return_code = 0;
    $taskid ||= 0;
    $create ||= 0;

    my $rsync_target = targetpath( $host, $group );

    if ( !-d $rsync_target ) {
        $return_code = 1;
        if ( $create ) {
            system("mkdir -p $rsync_target") unless $serverconfig{dryrun};
            $return_code = 0;
        }
    }
    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
        $rsync_target .= '/current';

        if ( !-d $rsync_target ) {
            $return_code = 1;
            if ( $create ) {
                create_btrfs_subvolume( $host, $group, $rsync_target, $taskid );
                $return_code = 0;
            }
        }
    }

    return $return_code;
}

sub list_groups {
    my ($host) = @_;

    my @groups;
    foreach my $hostgroup ( keys %hosts ) {
        if ( $hosts{$hostgroup}->{hostname} eq $host ) {
            push( @groups, $hosts{$hostgroup}->{group} );
        }
    }

    return @groups;
}

sub list_groupmembers {
    my ($group) = @_;

    my @groupmembers;
    foreach my $hostgroup ( keys %hosts ) {
        if ( $hosts{$hostgroup}->{group} eq $group ) {
            push( @groupmembers, $hosts{$hostgroup}->{hostname} );
        }
    }

    return \@groupmembers;
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

sub num2human {
    my ( $num, $base ) = @_;
    $base ||= 1000.;

    # convert large numbers to K, M, G, T notation
    foreach my $unit ( '', qw(k M G T P) ) {
        if ( $num < $base ) {
            if ( $num < 10 && $num > 0 ) {
                return sprintf( '%.2f %s', $num, $unit );    # print small values with 1 decimal
            } else {
                return sprintf( '%.1f %s', $num, $unit );    # print larger values without decimals
            }
        }
        $num = $num / $base;
    }
}

sub time2human {
    my ($minutes) = @_;

    # convert large times in minutes to hours
    if ( $minutes eq '-' ) {
        return '-';
    } else {
        if ( $minutes < 60 ) {
            if ( $minutes < 1 ) {
                return sprintf( '< 1 min', $minutes );
            } else {
                return sprintf( '%d min', $minutes );
            }
        } else {
            return sprintf( '%dh%02dmin', floor( $minutes / 60 ), $minutes % 60 );
        }
    }
}

1;
