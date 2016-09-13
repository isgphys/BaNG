package BaNG::Statistics;

use 5.010;
use strict;
use warnings;
use BaNG::Converter;
use BaNG::Config;
use BaNG::Reporting;
use Date::Parse;
use List::MoreUtils qw( uniq );
use List::Util qw( min max );

use Exporter 'import';
our @EXPORT = qw(
    statistics_json
    statistics_cumulated_json
    statistics_decode_path
    statistics_hosts_shares
    statistics_top_trans
    statistics_top_trans_details
    statistics_work_duration
    statistics_work_duration_details
    statistics_schedule
);

my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesDel NumOfFilesTrans NumOfFiles RealRuntime TotRuntime );
my $lastXdays_default    = 90;  # retrieve info of last X days from database
my $BackupStartHour      = 18;  # backups started after X o'clock belong to next day

sub statistics_decode_path {
    my ($path) = @_;

    $path =~ s|\+|/|g;                          # decode plus to slashes
    $path =~ s|\_|/|g;                          # decode underscores to slashes
    $path = '/' . $path unless $path =~ m|^/|;  # should always start with slash

    return $path;
}

sub statistics_json {
    my ( $host, $share, $days ) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
            TaskID, BkpFromHost, BkpGroup, BkpToHost,
            MAX(JobStatus) as JobStatus,
            COUNT(JobID) as Jobs,
            GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus,
            MIN(Start) as Start, MAX(Stop) as Stop,
            TIMESTAMPDIFF(Second, MIN(Start), MAX(Stop)) as Runtime,
            SUM(TIMESTAMPDIFF(Second, Start, Stop)) as RealRunTime,
            SUM(NumOfFiles) as NumOfFiles, SUM(TotFileSize) as TotFileSize,
            SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
            SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans
        FROM statistic
        WHERE Start > date_sub(now(), interval $lastXdays day)
            AND BkpFromHost = '$host'
            AND BkpFromPathRoot LIKE '\%$share'
        GROUP BY TaskID, BkpToHost, BkpFromHost, BkpGroup
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    my %BackupsByPath;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {

        # reformat timestamp as 'YYYY/MM/DD HH:MM:SS' for cross-browser compatibility
        ( my $time_start = $dbrow->{'Start'} ) =~ s/\-/\//g;

        push( @{$BackupsByPath{$share}}, {
            time_coord       => str2time($time_start),
            RealRuntime      => sprintf( "%.2f", $dbrow->{'Runtime'} / 60. ),
            TotRuntime       => $dbrow->{'RealRunTime'}/60.,
            BkpToPath        => $dbrow->{'BkpToPath'},
            BkpFromHost      => $dbrow->{'BkpFromHost'},
            BkpToHost        => $dbrow->{'BkpToHost'},
            TotFileSize      => $dbrow->{'TotFileSize'},
            TotFileSizeTrans => $dbrow->{'TotFileSizeTrans'},
            NumOfFiles       => $dbrow->{'NumOfFiles'},
            NumOfFilesTrans  => $dbrow->{'NumOfFilesTrans'},
            NumOfFilesDel    => $dbrow->{'NumOfFilesDel'},
        });
    }
    $sth->finish();

    return rickshaw_json( \%BackupsByPath );
}

sub statistics_cumulated_json {
    my ( $BkpServer, $lastXdays ) = @_;
    $BkpServer ||= $servername;
    $lastXdays ||= $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
            TaskID, BkpFromHost, BkpGroup, BkpToHost,
            MAX(JobStatus) as JobStatus,
            COUNT(JobID) as Jobs,
            GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus,
            MIN(Start) as Start, MAX(Stop) as Stop,
            TIMESTAMPDIFF(Second, MIN(Start), MAX(Stop)) as Runtime,
            SUM(TIMESTAMPDIFF(Second, Start, Stop)) as RealRunTime,
            SUM(NumOfFiles) as NumOfFiles, SUM(TotFileSize) as TotFileSize,
            SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
            SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans
        FROM statistic
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpToHost LIKE '$BkpServer'
        GROUP BY TaskID, BkpToHost, BkpFromHost, BkpGroup
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    my %CumulateByDate = ();
    my %realtime_start = ();
    my %realtime_stop  = ();
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my ( $date, $time ) = split( /\s+/, $dbrow->{'Start'} );

        # reformat timestamp as "YYYY/MM/DD HH:MM:SS" for cross-browser compatibility
        ( my $time_start = $dbrow->{'Start'} ) =~ s/\-/\//g;
        ( my $time_stop  = $dbrow->{'Stop'} || $dbrow->{'Start'} )  =~ s/\-/\//g;


        # backups started in the evening belong to next day
        # use epoch as hash key for fast date incrementation
        my $epoch = str2time("$date 00:00:00");
        my ( $ss, $mm, $hh, $DD, $MM, $YY, $zone ) = strptime( $dbrow->{'Start'} );
        if ( $hh >= $BackupStartHour ) {
            $epoch += 24 * 3600;
        }

        # compute wall-clock runtime of backup in minutes with 2 digits
        if ( !$realtime_start{$epoch} && !$realtime_stop{$epoch} ) {

            # initialize reference time interval
            $realtime_start{$epoch} = str2time($time_start);
            $realtime_stop{$epoch}  = str2time($time_stop);
            $CumulateByDate{$epoch}{RealRuntime} += sprintf('%.2f',
                ( $realtime_stop{$epoch} - $realtime_start{$epoch} ) / 60.
            );
        }
        if ( str2time($time_stop) > $realtime_stop{$epoch} ) {
            if ( str2time($time_start) <= $realtime_stop{$epoch} ) {

                # bkp started during reference interval, but finished afterwards
                $CumulateByDate{$epoch}{RealRuntime} += sprintf('%.2f',
                    ( str2time($time_stop) - $realtime_stop{$epoch} ) / 60.
                );
                $realtime_stop{$epoch}  = str2time($time_stop);
            } else {

                # bkp started after end of reference interval, ie there was a gap without running bkps
                $realtime_start{$epoch} = str2time($time_start);
                $realtime_stop{$epoch}  = str2time($time_stop);
                $CumulateByDate{$epoch}{RealRuntime} += sprintf('%.2f',
                    ( $realtime_stop{$epoch} - $realtime_start{$epoch} ) / 60.
                );
            }
        }

        # store cumulated statistics for each day
        $CumulateByDate{$epoch}{time_coord}        = $epoch;
        $CumulateByDate{$epoch}{TotRuntime}       += ( $dbrow->{'RealRunTime'} || 0) / 60.;
        $CumulateByDate{$epoch}{TotFileSize}      += $dbrow->{'TotFileSize'} || 0;
        $CumulateByDate{$epoch}{TotFileSizeTrans} += $dbrow->{'TotFileSizeTrans'} || 0;
        $CumulateByDate{$epoch}{NumOfFiles}       += $dbrow->{'NumOfFiles'} || 0;
        $CumulateByDate{$epoch}{NumOfFilesTrans}  += $dbrow->{'NumOfFilesTrans'} || 0;
        $CumulateByDate{$epoch}{NumOfFilesDel}    += $dbrow->{'NumOfFilesDel'} || 0;
    }
    $sth->finish();

    # only continue if we found any data
    return 0 unless keys %CumulateByDate;

    # remove first day with incomplete information
    delete $CumulateByDate{( sort keys %CumulateByDate )[0]};

    # reshape data structure similar to BackupsByPath
    my %BackupsByDay;
    foreach my $date ( sort keys %CumulateByDate ) {
        push( @{$BackupsByDay{'Cumulated'}}, {
            time_coord       => $CumulateByDate{$date}{time_coord},
            RealRuntime      => $CumulateByDate{$date}{RealRuntime},
            TotRuntime       => $CumulateByDate{$date}{TotRuntime},
            TotFileSize      => $CumulateByDate{$date}{TotFileSize},
            TotFileSizeTrans => $CumulateByDate{$date}{TotFileSizeTrans},
            NumOfFiles       => $CumulateByDate{$date}{NumOfFiles},
            NumOfFilesTrans  => $CumulateByDate{$date}{NumOfFilesTrans},
            NumOfFilesDel    => $CumulateByDate{$date}{NumOfFilesDel},
        });
    }

    return rickshaw_json( \%BackupsByDay );
}

sub statistics_hosts_shares {
    my ($BkpServer) = @_;
    $BkpServer ||= $servername;

    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
        DISTINCT BkpFromHost, BkpFromPathRoot
        FROM statistic
        WHERE Start > date_sub(now(), interval $lastXdays_default day)
        AND BkpToHost LIKE '$BkpServer'
        ORDER BY BkpFromHost;
    ");
    $sth->execute();

    my %hosts_shares;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPathRoot'};
        $BkpFromPath =~ s/\s//g;    # remove whitespace
        my ( $empty, @shares ) = split( /:/, $BkpFromPath );

        # distinguish data and system shares
        foreach my $share (@shares) {
            my $type = 'datashare';
            $type = 'systemshare' unless $share =~ /export|imap|Users/;
            push( @{$hosts_shares{$type}{$hostname}}, $share );
        }
    }
    $sth->finish();

    # filter duplicate shares
    foreach my $type ( keys %hosts_shares ) {
        foreach my $host ( keys %{$hosts_shares{$type}} ) {
            @{$hosts_shares{$type}{$host}} = uniq @{$hosts_shares{$type}{$host}};
        }
    }

    return \%hosts_shares;
}

sub statistics_work_duration {
    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT  TaskID, BkpFromHost, BkpGroup,
            IF(isThread, BkpFromPathRoot, BkpFromPath) as BkpFromPath,
            TIMESTAMPDIFF(Second, MIN(Start) , MAX(Stop)) as Runtime
        FROM statistic
        WHERE Start > date_sub(NOW(), INTERVAL 1 DAY)
        GROUP BY TaskID
        ORDER BY Runtime DESC;
    ");
    $sth->execute();

    my @top_time;
    while ( my ( $taskid, $bkphost, $bkpgroup, $bkppath, $runtime ) = $sth->fetchrow_array() ) {
        next if $runtime < 2;
        $bkppath =~ s/\://g;
        $bkppath =~ s/\//_/g;
        push( @top_time, {
            name  => $bkpgroup,
            value => $runtime,
            label => time2human( $runtime / 60 ),
            url   => "/statistics/barchart/worktime/$taskid",
        });
    }
    $sth->finish();

    return \@top_time;
}

sub statistics_work_duration_details {
    my ($taskid) = @_;
    my ( @top_size, $sth, $sqltranstype, $sqlbkpgroup, $bkpurl, $labeltext );

    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    $sth = $bangstat_dbh->prepare("
        SELECT bkpfromhost, bkpgroup, BkpFromPath, BkpFromPathRoot,
            TIMESTAMPDIFF(Second, Start , Stop) as Runtime
        FROM statistic
        WHERE TaskID = '$taskid'
        GROUP BY bkpfromhost, bkpgroup, BkpFromPath, BkpFromPathRoot
        ORDER BY Runtime DESC
    ");
    $sth->execute();

    while ( my ( $bkphost, $bkpgroup, $bkppath, $bkppathroot, $runtime ) = $sth->fetchrow_array() ) {
        $sqlbkpgroup = $bkpgroup;
        $bkpurl      = ( $bkppath eq $bkppathroot ) ? $bkppath : $bkppathroot;
        my $c = $bkpurl =~ tr/://;

        $labeltext   = $bkphost ." - ". $bkppath;
        $labeltext   =~ s/\://g;
        $bkpurl      =~ s/\://g;
        $bkpurl      =~ s/\//_/g;

        if ( $c > 1 ) {
            $bkpurl = "#";
        } else {
            $bkpurl = "/statistics/$bkphost/$bkpurl";
        }

        push( @top_size, {
            name  => $labeltext,
            value => max( $runtime, 59 ),               # display all values smaller than 1 minute as 59 seconds
            label => time2human( $runtime / 60 ),
            url   => $bkpurl,
        });
    }

    # If we found a single element, the backup was done with subfolder threading, and we need to query using the bkpgroup
    if ( $#top_size == 0 ) {
        @top_size = ();
        $sth = $bangstat_dbh->prepare("
            SELECT bkpfromhost, bkpgroup, BkpFromPath, TIMESTAMPDIFF(Second, Start , Stop) as Runtime
            FROM statistic
            WHERE TaskID = '$taskid' AND bkpgroup LIKE '$sqlbkpgroup'
            ORDER BY Runtime DESC;
        ");
        $sth->execute();

        while ( my ( $bkphost, $bkpgroup, $bkppath, $runtime ) = $sth->fetchrow_array() ) {
            $labeltext   = $bkphost ." - ". $bkppath;
            $labeltext   =~ s/\://g;
            push( @top_size, {
                name  => $labeltext,
                value => max( $runtime, 59 ),           # display all values smaller than 1 minute as 59 seconds
                label => time2human( $runtime / 60 ),
                url   => '#',
            });
        }
    }
    $sth->finish();

    return \@top_size;
}

sub statistics_top_trans {
    my ($transtype) = @_;
    my ( $sqltranstype, $labeltext );
    if ( $transtype eq 'files' ) {
        $sqltranstype = 'NumOfFilesTrans';
    } elsif ( $transtype eq 'size' ) {
        $sqltranstype = 'TotFileSizeTrans';
    }
    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT  TaskID, BkpFromHost, BkpGroup,
            IF(isThread, BkpFromPathRoot, BkpFromPath) as BkpFromPath,
            SUM($sqltranstype) as $sqltranstype
        FROM statistic
        WHERE Start > date_sub(NOW(), INTERVAL 1 DAY)
        GROUP BY TaskID
        ORDER BY $sqltranstype DESC;
    ");
    $sth->execute();

    my @top_size;
    while ( my ( $taskid, $bkphost, $bkpgroup, $bkppath, $size ) = $sth->fetchrow_array() ) {
        next if $size < 2;
        $bkppath =~ s/\://g;
        $labeltext = $bkpgroup;
        $bkppath =~ s/\//_/g;
        push( @top_size, {
            name  => $labeltext,
            value => $size,
            label => num2human( $size, 1024 ),
            url   => "/statistics/barchart/toptrans$transtype/$taskid",
        });
    }
    $sth->finish();

    return \@top_size;
}

sub statistics_top_trans_details {
    my ( $transtype, $taskid ) = @_;
    my ( @top_size, $sth, $sqltranstype, $sqlbkpgroup, $bkpurl, $labeltext );

    if ( $transtype eq 'files' ) {
        $sqltranstype = 'NumOfFilesTrans';
    } elsif ( $transtype eq 'size' ) {
        $sqltranstype = 'TotFileSizeTrans';
    }
    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    $sth = $bangstat_dbh->prepare("
        SELECT bkpfromhost, bkpgroup, BkpFromPath, BkpFromPathRoot,
            SUM($sqltranstype) AS $sqltranstype
        FROM statistic
        WHERE TaskID = '$taskid'
        GROUP BY JobID, bkpfromhost, bkpgroup,BkpFromPath, BkpFromPathRoot
        ORDER BY $sqltranstype DESC;
    ");
    $sth->execute();

    while ( my ( $bkphost, $bkpgroup, $bkppath, $bkppathroot, $size ) = $sth->fetchrow_array() ) {
        $sqlbkpgroup = $bkpgroup;
        $bkpurl      = ( $bkppath eq $bkppathroot ) ? $bkppath : $bkppathroot;
        my $c = $bkpurl =~ tr/://;

        $labeltext   = $bkphost ." - ". $bkppath;
        $labeltext   =~ s/\://g;
        $bkpurl      =~ s/\://g;
        $bkpurl      =~ s/\//_/g;

        if ( $c > 1 ) {
            $bkpurl = "#";
        } else {
            $bkpurl = "/statistics/$bkphost/$bkpurl";
        }

        push( @top_size, {
            name  => $labeltext,
            value => max( $size, 10 ),
            label => num2human( $size, 1024 ),
            url   => $bkpurl,
        });
    }

    if ( $#top_size == 0 ) {
        @top_size = ();
        $sth = $bangstat_dbh->prepare("
            SELECT bkpfromhost, bkpgroup, bkpfrompath, $sqltranstype
            FROM statistic
            WHERE TaskID = '$taskid' AND bkpgroup LIKE '$sqlbkpgroup'
            ORDER BY $sqltranstype desc;
        ");
        $sth->execute();

        while ( my ( $bkphost, $bkpgroup, $bkppath, $size ) = $sth->fetchrow_array() ) {
            $bkppath =~ s/\://g;
            $labeltext = $bkphost ." - ". $bkppath;
            $bkppath =~ s/^.*\/(.*)$/$1/;
            push( @top_size, {
                name  => $labeltext,
                value => max( $size, 10 ),
                label => num2human( $size, 1024 ),
                url   => '#',
            });
        }
    }
    $sth->finish();

    return \@top_size;
}

sub statistics_schedule {
    my ( $days, $sortBy ) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return () unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
            TaskID, BkpFromHost, BkpGroup, BkpToHost, TaskName, Description, Cron,
            MAX(JobStatus) as JobStatus,
            COUNT(JobID) as Jobs,
            GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus,
            MIN(Start) as Start, MAX(Stop) as Stop,
            TIMESTAMPDIFF(Second, MIN(Start), MAX(Stop)) as Runtime,
            SUM(NumOfFiles) as NumOfFiles, SUM(TotFileSize) as TotFileSize,
            SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
            SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans
        FROM statistic
        LEFT JOIN statistic_task_meta USING (TaskID)
        WHERE Start > date_sub(concat(curdate(),' $BackupStartHour:00:00'), interval $lastXdays day)
        AND BkpToHost LIKE '$servername'
        GROUP BY TaskID, BkpToHost, BkpFromHost, BkpGroup, TaskName, Description, Cron
        ORDER BY Start;
    ");
    $sth->execute();

    my %datahash;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        ( my $time_start = $dbrow->{'Start'} ) =~ s/\-/\//g;
        ( my $time_stop  = $dbrow->{'Stop'} || $dbrow->{'Start'} )  =~ s/\-/\//g;
        my $BkpGroup = $dbrow->{'BkpGroup'};

        # flag system backups
        my $systemBkp = 0;
        $systemBkp    = 1 if ( $BkpGroup =~ m%/(system)% );

        # hash constructed by host or time
        my $sortKey = $dbrow->{'BkpFromHost'};
        $sortKey    = $time_start if $sortBy =~ /time/;

        push( @{$datahash{$sortKey}}, {
            time_start       => $time_start,
            time_stop        => $time_stop,
            BkpGroup         => $dbrow->{'BkpGroup'} || 'NoBkpGroup',
            TaskName         => $dbrow->{'TaskName'},
            Description      => $dbrow->{'Description'},
            BkpToPath        => $dbrow->{'BkpToPath'},
            BkpFromHost      => $dbrow->{'BkpFromHost'},
            BkpToHost        => $dbrow->{'BkpToHost'},
            TotFileSize      => num2human($dbrow->{'TotFileSize'}, 1024.),
            TotFileSizeTrans => num2human($dbrow->{'TotFileSizeTrans'}, 1024.),
            NumOfFiles       => num2human($dbrow->{'NumOfFiles'}),
            NumOfFilesTrans  => num2human($dbrow->{'NumOfFilesTrans'}),
            NumOfFilesDel    => num2human($dbrow->{'NumOfFilesDel'}),
            AvgFileSize      => $dbrow->{'NumOfFiles'} ? num2human($dbrow->{'TotFileSize'}/$dbrow->{'NumOfFiles'},1024) : 0,
            SystemBkp        => $systemBkp,
        });
    }
    $sth->finish();

    return %datahash;
}

sub rickshaw_json {
    my ($datahash_ref) = @_;
    my %datahash = %{$datahash_ref};

    my %rickshaw_data;
    foreach my $bkppath ( sort keys %datahash ) {
        my ( %min, %max );
        foreach my $field (@fields) {

            # find min- and maxima of given fields
            $max{$field} = sprintf( '%.2f', max( map { $_->{$field} } @{$datahash{$bkppath}} ) );
            $min{$field} = sprintf( '%.2f', min( map { $_->{$field} } @{$datahash{$bkppath}} ) );
        }

        # use same normalization for both runtimes to ensure curves coincide
        foreach my $field (qw(RealRuntime TotRuntime)) {
            $max{$field} = max( $max{RealRuntime}, $max{TotRuntime} );
            $min{$field} = min( $min{RealRuntime}, $min{TotRuntime} );
        }

        foreach my $bkp ( @{$datahash{$bkppath}} ) {
            my $t = $bkp->{'time_coord'};    # monotonically increasing coordinate to have single-valued function

            foreach my $field (@fields) {
                my $normalized = 0.5;
                if ( $min{$field} != $max{$field} ) {
                    $normalized = ( $bkp->{$field} - $min{$field} ) / ( $max{$field} - $min{$field} );
                }

                my $humanreadable;
                if ( $field =~ /Runtime/ ) {
                    $humanreadable = "\"" . time2human( $bkp->{$field} ) . "\"";
                } elsif ( $field =~ /Size/ ) {
                    $humanreadable = "\"" . num2human( $bkp->{$field}, 1024. ) . "\"";
                } else {
                    $humanreadable = "\"" . num2human( $bkp->{$field} ) . "\"";
                }

                $rickshaw_data{Normalized}{$field}    .= qq|\n        { "x": $t, "y": $normalized },|;
                $rickshaw_data{HumanReadable}{$field} .= qq|\n        { "x": $t, "y": $humanreadable },|;
            }
        }
        last;
    }

    my %color = (
        RealRuntime      => '#00CC00',
        TotRuntime       => '#009900',
        NumOfFiles       => '#0066B3',
        NumOfFilesTrans  => '#330099',
        TotFileSize      => '#FFCC00',
        TotFileSizeTrans => '#FF8000',
        NumOfFilesDel    => '#FF3333',
    );

    my $json = "[\n";
    foreach my $field (@fields) {
        $json .= qq|{\n|;
        $json .= qq|    "name"          : "$field",\n|;
        $json .= qq|    "color"         : "$color{$field}",\n|;
        $json .= qq|    "data"          : [$rickshaw_data{Normalized}{$field}\n    ],\n|;
        $json .= qq|    "humanReadable" : [$rickshaw_data{HumanReadable}{$field}\n    ]\n|;
        $json .= qq|},\n|;
    }
    $json .= "]\n";

    $json =~ s/\},(\s*)\]/\}$1\]/g;    # sanitize json by removing trailing spaces
    $json =~ s/\s+//g;                 # minimize json by removing all whitespaces

    return $json;
}

1;
