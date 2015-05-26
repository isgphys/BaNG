use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNGadm --cron-create -n -p t';
my @cron = `$bangcmd`;

ok( grep( /# Automatically generated/                                            , @cron ) , 'Crontab contains notice that it is generated'   );
ok( grep( /MAILTO=admin\@example\.com/                                           , @cron ) , 'Crontab contains optional mailto header'        );
ok( grep( /PATH=\/usr\/local\/bin:\/usr\/bin:\/bin/                              , @cron ) , 'Crontab contains optional path header'          );
ok( grep( /#--- backup ---/                                                      , @cron ) , 'Crontab contains a section for backups'         );
ok( grep( /0  2  \*  \*  \*     root    t\/BaNG -g somegroup -t 1/               , @cron ) , 'Crontab contains an entry for a backup'         );
ok( grep( /#--- backup_missingonly ---/                                          , @cron ) , 'Crontab contains a section for missing backups' );
ok( grep( /0 12  \*  \*  \*     root    t\/BaNG -g somegroup -t 1 --missingonly/ , @cron ) , 'Crontab contains an entry for a backup'         );
ok( grep( /#--- wipe ---/                                                        , @cron ) , 'Crontab contains a section for wipes'           );
ok( grep( /0  4  \*  \*  1     root    t\/BaNG -g somegroup --wipe/              , @cron ) , 'Crontab contains an entry for a wipe'           );

done_testing();
