use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNGadm';
my $output;

$output = `$bangcmd`;
ok(     $? == 0,                                'BaNGadm returns without errors'        );
like(   $output,    qr|Check the arguments|,    'BaNGadm prompts to provide arguments'  );

$output = `$bangcmd --help`;
ok(     $? == 0,                                'BaNGadm --help returns without errors' );
like(   $output,    qr|Usage|,                  'BaNGadm --help shows usage information');

done_testing();
