use strict;
use warnings;
use 5.010;
use Test::More;
use Cwd qw( abs_path );
use File::Basename;
use lib dirname( abs_path($0) ) . "/../lib";
use BaNG::Config;

my $bangadmcmd = dirname($0) . '/../BaNGadm -n -p t';
my $output;

get_serverconfig('t');
ok(%serverconfig, "Serverconfig loaded");

get_host_config('*');
ok(%hosts, "Hostconfig loaded");

subtest 'Check all available configs for failed backups' => sub {
    $output = `$bangadmcmd --failed`;

    foreach my $config (sort keys %hosts ) {
        unless ( $hosts{$config}->{hostconfig}->{BKP_TARGET_HOST} ne $servername ) {
            like( $output, qr|Check $config for failed backups| , "Check $config for failed backups" );
        }
    }
    like(   $output,  qr|Found following folders for localhost - BaNGadm-failed|, 'Found folders for localhost-BaNGadm-failed'                  );
    like(   $output,  qr|2016.01.01_000001_failed|                              , 'Found 2016.01.01_000001_failed for localhost-BaNGadm-failed' );
    unlike( $output,  qr|2016.02.01_000002|                                     , 'no other folders found' );
};


subtest 'Check localhost-BaNGadm-failed for failed backups' => sub {
    $output = `$bangadmcmd --failed -h localhost -g BaNGadm-failed`;

    like(   $output,  qr|Check localhost-BaNGadm-failed for failed backups|     , 'Check localhost-BaNGadm-failed for failed backups'           );
    like(   $output,  qr|Found following folders for localhost - BaNGadm-failed|, 'Found folders for localhost-BaNGadm-failed'                  );
    like(   $output,  qr|2016.01.01_000001_failed|                              , 'Found 2016.01.01_000001_failed for localhost-BaNGadm-failed' );
    unlike( $output,  qr|2016.02.01_000002|                                     , 'not found 2016.02.01_000002 for localhost-BaNGadm-failed'    );
};


subtest 'Delete failed folders for localhost-BaNGadm-failed' => sub {
    $output = `$bangadmcmd --failed --delete -h localhost -g BaNGadm-failed`;

    like(   $output, qr|Check localhost-BaNGadm-failed for failed backups| , 'Delete - check localhost-BaNGadm-failed for failed backups'  );
    like(   $output, qr|2016.01.01_000001_failed|                          , 'Delete - found 01.01.2016_000001_failed for localhost-BaNGadm-failed' );
    like(   $output, qr|Delete failed backup folders for|                  , 'Delete failed backup folders for localhost-BaNGadm-failed'   );
};

done_testing();
