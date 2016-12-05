use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNG -n -p t';
my $output;
my $group;

$group = 'snapshot-simple';
$output = `$bangcmd -h localhost -g $group --bkpmode 2>&1`;
like(   $output,    qr|Option bkpmode requires an argument|         , 'Option bkpmode requires an argument'         );

$output = `$bangcmd -h localhost -g $group --bkpmode test`;
like(   $output,    qr|Wrong Backup Mode|                           , 'Wrong Backup Mode, please use rsync or tar'  );

$output = `$bangcmd -h localhost -g $group --bkpmode tar`;
like(   $output,    qr|BaNG run in tar mode|                        , 'BaNG run in TAR mode'                        );

$output = `$bangcmd -h localhost -g $group --bkpmode tar`;
like(   $output,    qr|BaNG run in tar mode|                        , 'BaNG run in TAR mode'                        );

done_testing();
