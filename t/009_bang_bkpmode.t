use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNG -n -p t';
my $output;
my $group;

$group = 'test';

$output = `$bangcmd -g $group --bkpmode 2>&1`;
like(   $output,    qr|Option bkpmode requires an argument|         , 'Option bkpmode requires an argument'         );

$output = `$bangcmd -g $group --bkpmode test`;
like(   $output,    qr|Wrong Backup Mode|                           , 'Wrong Backup Mode, please use rsync or lts'  );

$output = `$bangcmd -g $group --bkpmode rsync`;
like(   $output,    qr|BaNG run in rsync mode|                      , 'BaNG run in rsync mode'                      );

$output = `$bangcmd -g $group --bkpmode lts`;
like(   $output,    qr|BaNG run in lts mode|                        , 'BaNG run in LTS mode'                        );

done_testing();
