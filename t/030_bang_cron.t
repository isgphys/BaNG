use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNGadm --crontab -n -p t';
my @crontab = `$bangcmd`;

ok( grep( /# Automatically generated/                                            , @crontab ) , 'Crontab contains notice that it is generated'   );
ok( grep( /# created on/                                                         , @crontab ) , 'Crontab contains notice when it was generated'  );
ok( grep( /MAILTO=admin\@example\.com/                                           , @crontab ) , 'Crontab contains optional mailto header'        );
ok( grep( /PATH=\/usr\/local\/bin:\/usr\/bin:\/bin/                              , @crontab ) , 'Crontab contains optional path header'          );
ok( grep( /#--- backup ---/                                                      , @crontab ) , 'Crontab contains a section for backups'         );
ok( grep( /0  2  \*  \*  \*     root    t\/BaNG -g somegroup -t 1/               , @crontab ) , 'Crontab contains an entry for a backup'         );
ok( grep( /#--- backup_missingonly ---/                                          , @crontab ) , 'Crontab contains a section for missing backups' );
ok( grep( /0 12  \*  \*  \*     root    t\/BaNG -g somegroup -t 1 --missingonly/ , @crontab ) , 'Crontab contains an entry for a backup'         );
ok( grep( /#--- wipe ---/                                                        , @crontab ) , 'Crontab contains a section for wipes'           );
ok( grep( /0  4  \*  \*  1     root    t\/BaNG -g somegroup --wipe/              , @crontab ) , 'Crontab contains an entry for a wipe'           );

done_testing();
