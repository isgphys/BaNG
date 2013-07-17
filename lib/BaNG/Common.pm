package BaNG::Common;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use POSIX qw( floor );
use Date::Parse;
use Data::Dumper;

use Exporter 'import';
our @EXPORT = qw(
    backup_folders_stack
    get_backup_folders
    list_groups
    get_automount_paths
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
    my $server = $hosts{"$host-$group"}{hostconfig}{BKP_TARGET_HOST};
    my @backup_folders;

    if ( $server eq $servername) {
        @backup_folders = `find $bkpdir -mindepth 1 -maxdepth 1 -type d -regex '${bkpdir}[0-9\./_]*' 2>/dev/null`;
    } else {
        @backup_folders = &BaNG::Hosts::remoteWrapperCommand( $server, 'BaNG/bang_getBackupFolders', $bkpdir );
    }
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

sub backup_folders_stack {
    my ($host) = @_;

    my %backup_folders_stack;
    foreach my $group ( list_groups($host) ) {
        my @available_backup_folders = get_backup_folders($host, $group);
        my %stack = &BaNG::Wipe::list_folders_to_wipe( $host, $group, @available_backup_folders );
        $backup_folders_stack{$group} = \%stack;
    }

    return \%backup_folders_stack;
}

sub get_automount_paths {
    my ($ypfile) = @_;
    $ypfile ||= 'auto.backup';

    my %automnt;
    my @autfstbl = `ypcat -k $ypfile`;

    foreach my $line ( @autfstbl ) {
        if ( $line =~ qr{
            (?<parentfolder>[^\s]*) \s*
            \-fstype\=autofs \s*
            yp\:(?<ypfile>.*)
            }x )
        {
            # recursively read included yp files
            my $parentfolder = $+{parentfolder};
            my $submounts = get_automount_paths( $+{ypfile} );
            foreach my $mountpt ( keys %{ $submounts } ) {
                $automnt{ $mountpt } = {
                    server => $submounts->{$mountpt}->{server},
                    path   => "$parentfolder/$submounts->{$mountpt}->{path}",
                };
            }
        } elsif ( $line =~ qr{
            (?<mountpt>[^\s]*) \s
            (?<server>[^\:]*) :
            (?<mountpath>.*)
            }x )
        {
            $automnt{$+{mountpath}} = {
                server => $+{server},
                path   => $+{mountpt},
            };
        }
    }

    return \%automnt;
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
