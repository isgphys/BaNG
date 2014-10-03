use strict;
use warnings;
use 5.010;
use Test::More;
use File::Basename;

my $bangcmd = dirname($0) . '/../BaNG -n -p t';
my $output;
my $group;

$output = `$bangcmd -h doesnotexist`;
like(   $output,    qr|Exit because queue is empty|                              , 'Exiting with empty queue for unknown host'          );

$output = `$bangcmd -g doesnotexist`;
like(   $output,    qr|Exit because queue is empty|                              , 'Exiting with empty queue for unknown group'         );

$group = 'snapshot-simple';
$output = `$bangcmd -h localhost -g $group`;
like(   $output,    qr|because target_path does not exist|                       , 'Skip backup target_path does not exist'             );

$group = 'snapshot-simple';
$output = `$bangcmd -h localhost -g $group --initial`;
like(   $output,    qr|Queueing backup for host localhost group $group|          , "Queueing backup for localhost $group"               );
like(   $output,    qr|check_client_connection|                                  , "Check online status of localhost $group"            );
like(   $output,    qr|Number of partitions: 1 \( :/ \)|                         , "Correct partitions for localhost $group"            );
like(   $output,    qr|End of queueing backup of host localhost group $group|    , "End of queueing backup of localhost $group"         );
like(   $output,    qr|Thread \d+ working on|                                    , "Thread XX working on localhost $group"              );
like(   $output,    qr|Created lockfile|                                         , "Created lockfile for localhost $group"              );
like(   $output,    qr|Create btrfs subvolume|                                   , "Create btrfs subvolume for localhost $group"        );
like(   $output,    qr|Found lastbkp = nolastbkp|                                , "No lastbkp found for localhost $group"              );
like(   $output,    qr|Executing rsync for host localhost group $group path :/|  , "Executing rsync for localhost $group"               );
unlike( $output,    qr|\-\-linkdest|                                             , "Rsync without --link-dest for localhost $group"     );
like(   $output,    qr|\-\-exclude\-from=t/etc/excludes/excludelist_system |     , "Rsync with excludefile for localhost $group"        );
like(   $output,    qr|Rsync successful for host localhost group $group|         , "Rsync successful for localhost $group"              );
like(   $output,    qr|Touch current folder for host localhost group $group|     , "Touch current folder for localhost $group"          );
like(   $output,    qr|Create btrfs snapshot for host localhost group $group|    , "Create btrfs snapshot for localhost $group"         );
like(   $output,    qr|Write lastBkpFile:|                                       , "Write lastBkpFile for localhost $group"             );
like(   $output,    qr|Set jobstatus to 1 for host localhost group $group|       , "Set bangstat jobstatus 1 for localhost $group"      );
like(   $output,    qr|Set jobstatus to 2 for host localhost group $group|       , "Set bangstat jobstatus 2 for localhost $group"      );
like(   $output,    qr|xymon report sent|                                        , "xymon report sent for localhost $group"             );
like(   $output,    qr|Backup successful for host localhost group $group|        , "Backup successful for localhost $group"             );
like(   $output,    qr|Removed lockfile|                                         , "Removed lockfile for localhost $group"              );
unlike( $output,    qr|Error|i                                                   , "No error messages for localhost $group"             );
unlike( $output,    qr|Warning|i                                                 , "No warning messages for localhost $group"           );

$group = 'snapshot-subfolders';
$output = `$bangcmd -h localhost -g $group --initial`;
like(   $output,    qr|Backup successful for host localhost group $group|        , "Backup successful for localhost $group"             );
unlike( $output,    qr|Error|i                                                   , "No error messages for localhost $group"             );
unlike( $output,    qr|Warning|i                                                 , "No warning messages for localhost $group"           );
like(   $output,    qr|eval subfolders command|                                  , "Eval subfolders for localhost $group"               );

$group = 'differentserver';
$output = `$bangcmd -h localhost -g $group --initial`;
like(   $output,    qr|Skipping .* for server doesnotexist instead of|           , "Skip backup to different server of localhost $group");

$group = 'missingexclude';
$output = `$bangcmd -h localhost -g $group --initial`;
like(   $output,    qr|Warning: could not find excludefile|                      , "Warn about missing excludefile for localhost $group");

$output = `$bangcmd  --xymon -h localhost -g snapshot-simple --initial`;
like(   $output,    qr|xymon report sent\.\s*Exit because queue is empty|        , "xymon only command argument sends report"          );

done_testing();
