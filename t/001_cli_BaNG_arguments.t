use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNG';
my $output;

$output = `$bangcmd`;
ok(     $? == 0,                                'BaNG returns without errors'           );
like(   $output,    qr|provide some arguments|, 'BaNG prompts to provide arguments'     );

$output = `$bangcmd --help`;
ok(     $? == 0,                                'BaNG --help returns without errors'    );
like(   $output,    qr|Usage|,                  'BaNG --help shows usage information'   );

$output = `$bangcmd --version`;
ok(     $? == 0,                                'BaNG --version returns without errors' );
like(   $output,    qr|version number|,         'BaNG --version shows version number'   );

done_testing();
