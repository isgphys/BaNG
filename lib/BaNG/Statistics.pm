package BaNG::Statistics;

use 5.010;
use strict;
use warnings;
use BaNG::Common;
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
    statistics_diffpreday
    statistics_groupshare_variations
    statistics_schedule
);

my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesTrans NumOfFiles RealRuntime TotRuntime );
my $lastXdays_default    = 90;  # retrieve info of last X days from database
my $lastXdays_variations = 30;  # find largest variation of the last X days
my $lastXdays_diffperday = 5;   # show TotOfFiles difference to previous day from the last X days
my @variation_intervals  = (2, 5, 10, 30); # largest variations for these intervals of days
my $topX_variations      = 5;   # return the top X shares with largest variations
my $BackupStartHour      = 18;  # backups started after X o'clock belong to next day

sub statistics_decode_path {
    my ($path) = @_;

    $path =~ s|_|/|g;                           # decode underscores to slashes
    $path = '/' . $path unless $path =~ m|^/|;  # should always start with slash

    return $path;
}

sub statistics_json {
    my ($host, $share, $days) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpFromHost = '$host'
        AND BkpFromPath LIKE '\%$share'
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    my %BackupsByPath;
    while (my $dbrow=$sth->fetchrow_hashref()) {
        # reformat timestamp as "YYYY/MM/DD HH:MM:SS" for cross-browser compatibility
        (my $time_start = $dbrow->{'Start'}) =~ s/\-/\//g;
        (my $time_stop  = $dbrow->{'Stop' }) =~ s/\-/\//g;
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/://g; # remove colon separators

        # compute wall-clock runtime of backup in minutes with 2 digits
        my $RealRuntime = sprintf("%.2f", (str2time($time_stop)-str2time($time_start)) / 60.);

        push( @{$BackupsByPath{$BkpFromPath}}, {
            time_coord       => str2time($time_start),
            RealRuntime      => $RealRuntime,
            TotRuntime       => $dbrow->{'Runtime'}/60.,
            BkpFromPath      => $BkpFromPath,
            BkpToPath        => $dbrow->{'BkpToPath'},
            BkpFromHost      => $dbrow->{'BkpFromHost'},
            BkpToHost        => $dbrow->{'BkpToHost'},
            TotFileSize      => $dbrow->{'TotFileSize'},
            TotFileSizeTrans => $dbrow->{'TotFileSizeTrans'},
            NumOfFiles       => $dbrow->{'NumOfFiles'},
            NumOfFilesTrans  => $dbrow->{'NumOfFilesTrans'},
        });
    }
    $sth->finish();

    return rickshaw_json(\%BackupsByPath);
}

sub statistics_cumulated_json {
    my ($BkpServer, $lastXdays) = @_;
    $BkpServer ||= 'phd-bkp-gw';
    $lastXdays ||= $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpToHost LIKE '$BkpServer'
        AND isThread is NULL
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    my %CumulateByDate = ();
    my %realtime_start = ();
    my %realtime_stop  = ();
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my ($date, $time) = split( /\s+/, $dbrow->{'Start'} );

        # reformat timestamp as "YYYY/MM/DD HH:MM:SS" for cross-browser compatibility
        (my $time_start = $dbrow->{'Start'}) =~ s/\-/\//g;
        (my $time_stop  = $dbrow->{'Stop' }) =~ s/\-/\//g;
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/://g; # remove colon separators

        # backups started in the evening belong to next day
        # use epoch as hash key for fast date incrementation
        my $epoch = str2time("$date 00:00:00");
        my ($ss,$mm,$hh,$DD,$MM,$YY,$zone) = strptime($dbrow->{'Start'});
        if ( $hh >= $BackupStartHour ) {
            $epoch += 24 * 3600;
        }

        # compute wall-clock runtime of backup in minutes with 2 digits
        if( !$realtime_start{$epoch} && !$realtime_stop{$epoch} ) {
            # initialize reference time interval
            $realtime_start{$epoch} = str2time($time_start);
            $realtime_stop{$epoch}  = str2time($time_stop);
            $CumulateByDate{$epoch}{RealRuntime} += sprintf("%.2f",
                ( $realtime_stop{$epoch} - $realtime_start{$epoch} ) / 60.
            );
        }
        if( str2time($time_stop) > $realtime_stop{$epoch} ) {
            if ( str2time($time_start) <= $realtime_stop{$epoch} ) {
                # bkp started during reference interval, but finished afterwards
                $CumulateByDate{$epoch}{RealRuntime} += sprintf("%.2f",
                    ( str2time($time_stop) - $realtime_stop{$epoch} ) / 60.
                );
                $realtime_stop{$epoch}  = str2time($time_stop);
            } else {
                # bkp started after end of reference interval, ie there was a gap without running bkps
                $realtime_start{$epoch} = str2time($time_start);
                $realtime_stop{$epoch}  = str2time($time_stop);
                $CumulateByDate{$epoch}{RealRuntime} += sprintf("%.2f",
                    ( $realtime_stop{$epoch} - $realtime_start{$epoch} ) / 60.
                );
            }
        }

        # store cumulated statistics for each day
        $CumulateByDate{$epoch}{time_coord}        = $epoch;
        $CumulateByDate{$epoch}{TotRuntime}       += $dbrow->{'Runtime'} / 60.;
        $CumulateByDate{$epoch}{TotFileSize}      += $dbrow->{'TotFileSize'};
        $CumulateByDate{$epoch}{TotFileSizeTrans} += $dbrow->{'TotFileSizeTrans'};
        $CumulateByDate{$epoch}{NumOfFiles}       += $dbrow->{'NumOfFiles'};
        $CumulateByDate{$epoch}{NumOfFilesTrans}  += $dbrow->{'NumOfFilesTrans'};
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
        });
    }

    return rickshaw_json(\%BackupsByDay);
}

sub statistics_hosts_shares {
    my ($BkpServer) = @_;
    $BkpServer ||= 'phd-bkp-gw';

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
        DISTINCT BkpFromHost, BkpFromPath
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays_default day)
        AND BkpToHost LIKE '$BkpServer'
        ORDER BY BkpFromHost;
    ");
    $sth->execute();

    my %hosts_shares;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/\s//g; # remove whitespace
        my ($empty, @shares) = split( /:/, $BkpFromPath );

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

sub statistics_diffpreday {
    my ($host, $group, $lastXdays) = @_;
    $host ||= "%";
    $group ||= "%";
    $lastXdays ||= $lastXdays_diffperday;

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT * , a.NumOfFiles - a.NumOfFilesTrans -
            (SELECT b.NumOfFiles
            FROM statistic_job_sum b
            WHERE b.BkpGroup = a.BkpGroup
                AND b.BkpFromHost = a.BkpFromHost
                AND b.BkpFromPath = a.BkpFromPath
                AND b.TaskID < a.TaskID
                AND b.Runtime > 0
            ORDER BY b.BkpFromHost, b.BkpFromPath DESC, b.TaskID DESC
            LIMIT 1
            ) as DiffPreDay
        FROM statistic_job_sum a
        WHERE a.bkpgroup like '$group'
            AND a.BkpFromHost like '$host'
            AND a.Runtime > 0
            AND a.Start > date_sub(NOW(), INTERVAL $lastXdays DAY)
        ORDER BY a.BkpFromHost, a.BkpFromPath DESC, a.TaskID DESC;
        ");
    $sth->execute();

    my $hash_ref = $sth->fetchall_hashref('JobID');

    $sth->finish();

    return $hash_ref;
}

sub statistics_top_trans {
    my ($transtype) = @_;
    my $sqltranstype;
    if ( $transtype eq 'files' ) {
        $sqltranstype =  'NumOfFilesTrans' ;
    } elsif ($transtype eq 'size') {
        $sqltranstype =  'TotFileSizeTrans' ;
    }
    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT  TaskID, BkpFromHost, BkpGroup, IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),
                BkpFromPath) as BkpFromPath, SUM($sqltranstype) as $sqltranstype
        FROM statistic
        WHERE Start > date_sub(NOW(), INTERVAL 1 DAY)
        GROUP BY TaskID
        ORDER BY $sqltranstype DESC;
        ");
        $sth->execute();

        my @top_size;
        while ( my ( $taskid, $bkphost, $bkpgroup, $bkppath, $size )  = $sth->fetchrow_array() ) {
            next if $size < 2;
            $bkppath =~ s/\://g;
            $bkppath =~ s/\//_/g;
            push( @top_size, {
                    name  => $bkpgroup,
                    value => $size,
                    label => num2human($size, 1024),
                    url   => "/statistics/barchart/toptrans$transtype/$taskid",
                });
        }
        $sth->finish();

        return \@top_size;
}

sub statistics_top_trans_details {
    my ($transtype, $taskid) = @_;
    my (@top_size, $sth, $sqltranstype, $sqlbkpgroup);

    if ( $transtype eq 'files' ) {
        $sqltranstype =  'NumOfFilesTrans' ;
    } elsif ($transtype eq 'size') {
        $sqltranstype =  'TotFileSizeTrans' ;
    }
    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    $sth = $bangstat_dbh->prepare("
        SELECT bkpfromhost, bkpgroup,
            IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))), BkpFromPath) as BkpFromPath,
            SUM($sqltranstype) AS $sqltranstype
        FROM statistic
        WHERE TaskID = '$taskid'
        GROUP BY JobID
        ORDER BY $sqltranstype DESC;
        ");
    $sth->execute();

    while ( my ( $bkphost, $bkpgroup, $bkppath, $size )  = $sth->fetchrow_array() ) {
        next if $size < 2;
        $sqlbkpgroup = $bkpgroup;
        $bkppath =~ s/\://g;
        $bkppath =~ s/\//_/g;
        push( @top_size, {
            name  => $bkphost,
            value => $size,
            label => num2human($size, 1024),
            url   => "/statistics/$bkphost/$bkppath",
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

        while ( my ( $bkphost, $bkpgroup, $bkppath, $size )  = $sth->fetchrow_array() ) {
            next if $size < 2;
            $bkppath =~ s/\://g;
            $bkppath =~ s/^.*\/(.*)$/$1/;
            push( @top_size, {
                name  => $bkppath,
                value => $size,
                label => num2human($size, 1024),
                url   => "#",
            });
        }
    }
    $sth->finish();

    return \@top_size;
}

sub statistics_groupshare_variations {

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT BkpFromPath, TotFileSize, NumOfFiles
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays_variations day)
        AND BkpFromHost = 'phd-san-gw2'
        AND BkpFromPath LIKE '\%export/groupdata/\%'
        ORDER BY Start;
    ");
    $sth->execute();

    my %datahash;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s%:/export/groupdata/%%g;

        push( @{$datahash{$BkpFromPath}}, {
            TotFileSize => $dbrow->{'TotFileSize'},
            NumOfFiles  => $dbrow->{'NumOfFiles'},
        });
    }
    $sth->finish();

    my %largest_variations;
    foreach my $N (@variation_intervals) {
        foreach my $field (qw(TotFileSize NumOfFiles)) {
            # compute maximal variation for each share
            my %delta;
            foreach my $bkppath ( keys %datahash ) {
                my @lastXdays = map{$_->{$field}} @{$datahash{$bkppath}};
                my @lastNdays = splice( @lastXdays, 0, $N);
                my $max = sprintf("%.2f", max( @lastNdays ));
                my $min = sprintf("%.2f", min( @lastNdays ));
                $delta{$N}{$bkppath} = $max - $min;
            }

            # extract groupshares with largest variations (in absolute values)
            my $count = 1;
            my $base  = $field =~ /Size/ ? 1024. : 1000.;
            foreach my $bkppath ( reverse sort {abs($delta{$N}{$a})<=>abs($delta{$N}{$b})} keys %{ $delta{$N} } ) {
                push( @{$largest_variations{$N}{$field}}, {
                    share => $bkppath,
                    delta => num2human($delta{$N}{$bkppath}, $base),
                });
                last if $count >= $topX_variations;
                $count++;
            }
        }
    }

    return \%largest_variations;
}

sub statistics_schedule {
    my ($days, $sortBy) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_serverconfig();
    my $conn = bangstat_db_connect($serverconfig{config_bangstat});
    return () unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(concat(curdate(),' $BackupStartHour:00:00'), interval $lastXdays day)
        AND isThread is Null
        AND BkpToHost LIKE 'phd-bkp-gw'
        ORDER BY Start;
    ");
    $sth->execute();

    my %datahash;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        (my $time_start = $dbrow->{'Start'}) =~ s/\-/\//g;
        (my $time_stop  = $dbrow->{'Stop' }) =~ s/\-/\//g;
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/://g; # remove colon separators

        # flag system backups
        my $systemBkp = 0;
        $systemBkp    = 1 if ( $BkpFromPath !~ m%/(export|var/imap)% );

        # hash constructed by host or time
        my $sortKey = $dbrow->{'BkpFromHost'};
        $sortKey    = $time_start if $sortBy =~ /time/;

        push( @{$datahash{$sortKey}}, {
            time_start       => $time_start,
            time_stop        => $time_stop,
            BkpFromPath      => $BkpFromPath,
            BkpToPath        => $dbrow->{'BkpToPath'},
            BkpFromHost      => $dbrow->{'BkpFromHost'},
            BkpToHost        => $dbrow->{'BkpToHost'},
            TotFileSize      => num2human($dbrow->{'TotFileSize'}, 1024.),
            TotFileSizeTrans => num2human($dbrow->{'TotFileSizeTrans'}, 1024.),
            NumOfFiles       => num2human($dbrow->{'NumOfFiles'}),
            NumOfFilesTrans  => num2human($dbrow->{'NumOfFilesTrans'}),
            AvgFileSize      => $dbrow->{'NumOfFiles'} ? num2human($dbrow->{'TotFileSize'}/$dbrow->{'NumOfFiles'},1024) : 0,
            SystemBkp        => $systemBkp,
            BkpGroup         => $dbrow->{'BkpGroup'} || 'NoBkpGroup',
        });
    }
    $sth->finish();

    return %datahash;
}

sub rickshaw_json {
    my ($datahash_ref) = @_;
    my %datahash = %{ $datahash_ref };

    my %rickshaw_data;
    foreach my $bkppath ( sort keys %datahash ) {
        my (%min, %max);
        foreach my $field (@fields) {
            # find min- and maxima of given fields
            $max{$field}  = sprintf("%.2f", max( map{$_->{$field}} @{$datahash{$bkppath}} ));
            $min{$field}  = sprintf("%.2f", min( map{$_->{$field}} @{$datahash{$bkppath}} ));
        }
        # use same normalization for both runtimes to ensure curves coincide
        foreach my $field (qw(RealRuntime TotRuntime)) {
            $max{$field} = max( $max{RealRuntime}, $max{TotRuntime} );
            $min{$field} = min( $min{RealRuntime}, $min{TotRuntime} );
        }

        foreach my $bkp ( @{$datahash{$bkppath}} ) {
            my $t = $bkp->{'time_coord'}; # monotonically increasing coordinate to have single-valued function

            foreach my $field (@fields) {
                my $normalized = 0.5;
                if ( $min{$field} != $max{$field} ) {
                    $normalized = ($bkp->{$field} - $min{$field}) / ($max{$field} - $min{$field});
                }

                my $humanreadable;
                if ( $field =~ /Runtime/ ) {
                    $humanreadable = "\"" . time2human($bkp->{$field}) . "\"";
                } elsif ( $field =~ /Size/ ) {
                    $humanreadable = "\"" . num2human($bkp->{$field}, 1024.) . "\"";
                } else {
                    $humanreadable = "\"" . num2human($bkp->{$field})  . "\"";
                }

                $rickshaw_data{Normalized}{$field}    .= qq|\n        { "x": $t, "y": $normalized },|;
                $rickshaw_data{HumanReadable}{$field} .= qq|\n        { "x": $t, "y": $humanreadable },|;
            }
        }
        last;
    }

    my %color = (
        "RealRuntime"      => "#00CC00",
        "TotRuntime"       => "#009900",
        "NumOfFiles"       => "#0066B3",
        "NumOfFilesTrans"  => "#330099",
        "TotFileSize"      => "#FFCC00",
        "TotFileSizeTrans" => "#FF8000",
    );

    my $json .= "[\n";
    foreach my $field (@fields) {
        $json .= qq|{\n|;
        $json .= qq|    "name"          : "$field",\n|;
        $json .= qq|    "color"         : "$color{$field}",\n|;
        $json .= qq|    "data"          : [$rickshaw_data{Normalized}{$field}\n    ],\n|;
        $json .= qq|    "humanReadable" : [$rickshaw_data{HumanReadable}{$field}\n    ]\n|;
        $json .= qq|},\n|;
    }
    $json .= "]\n";

    $json =~ s/\},(\s*)\]/\}$1\]/g; # sanitize json by removing trailing spaces
    $json =~ s/\s+//g;              # minimize json by removing all whitespaces

    return $json;
}

1;
