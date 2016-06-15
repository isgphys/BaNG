package BaNG::Common;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::BTRFS;
use Date::Parse;
use POSIX qw( floor );

use Exporter 'import';
our @EXPORT = qw(
    get_automount_paths
    check_target_exists
);

sub check_target_exists {
    my ( $host, $group, $taskid, $create ) = @_;
    my $return_code = 0;
    $taskid ||= 0;
    $create ||= 0;

    my $rsync_target = targetpath( $host, $group );

    print "DEBUG: Check if target $rsync_target available...\n" if $serverconfig{verboselevel} == 3;
    if ( !-d $rsync_target ) {
        $return_code = 1;
        print "DEBUG: Target folder $rsync_target does not exists!\n" if $serverconfig{verboselevel} == 3;
        if ( $create ) {
            print "DEBUG: Creating target folder $rsync_target!\n" if $serverconfig{verboselevel} == 3;
            system("mkdir -p $rsync_target") unless $serverconfig{dryrun};
            $return_code = 0;
        }
    }
    if ( $hosts{"$host-$group"}->{hostconfig}->{BKP_STORE_MODUS} eq 'snapshots' ) {
        $rsync_target .= '/current';

        if ( !-d $rsync_target ) {
            print "DEBUG: Target subvolume $rsync_target does not exists!\n" if $serverconfig{verboselevel} == 3;
            $return_code = 1;
            if ( $create ) {
                print "DEBUG: Creating target subvolume $rsync_target!\n" if $serverconfig{verboselevel} == 3;
                create_btrfs_subvolume( $host, $group, $rsync_target, $taskid );
                $return_code = 0;
            }
        }
    }

    print "DEBUG: Target $rsync_target available!\n" if $serverconfig{verboselevel} == 3 and $return_code == 0;
    return $return_code;
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

1;
