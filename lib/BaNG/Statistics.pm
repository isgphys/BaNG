package BaNG::Statistics;
use Dancer ':syntax';
use BaNG::Reporting;
use BaNG::Common;
use BaNG::Config;
use Date::Parse;
use List::Util qw(min max);
use List::MoreUtils qw(uniq);

use Exporter 'import';
our @EXPORT = qw(
    statistics_json
    statistics_cumulated_json
    statistics_decode_path
    statistics_hosts_shares
    statistics_groupshare_variations
    statistics_schedule
);

my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesTrans NumOfFiles RealRuntime TotRuntime );
my $lastXdays_default    = 150; # retrieve info of last X days from database
my $lastXdays_variations = 10;  # find largest variation of the last X days
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

    get_global_config();
    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpFromHost = '$host'
        AND BkpFromPath LIKE '\%$share'
        AND BkpToHost LIKE 'phd-bkp-gw\%'
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
    my ($days) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_global_config();
    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays day)
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        AND isThread is NULL
        ORDER BY Start;
    ");
    $sth->execute();

    # gather information into hash
    my %CumulateByDate = ();
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
        my $RealRuntime = sprintf("%.2f", (str2time($time_stop)-str2time($time_start)) / 60.);

        # store cumulated statistics for each day
        $CumulateByDate{$epoch}{time_coord}        = $epoch;
        $CumulateByDate{$epoch}{RealRuntime}      += $RealRuntime;
        $CumulateByDate{$epoch}{TotRuntime}       += $dbrow->{'Runtime'} / 60.;
        $CumulateByDate{$epoch}{TotFileSize}      += $dbrow->{'TotFileSize'};
        $CumulateByDate{$epoch}{TotFileSizeTrans} += $dbrow->{'TotFileSizeTrans'};
        $CumulateByDate{$epoch}{NumOfFiles}       += $dbrow->{'NumOfFiles'};
        $CumulateByDate{$epoch}{NumOfFilesTrans}  += $dbrow->{'NumOfFilesTrans'};
    }
    $sth->finish();

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

    get_global_config();
    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT
        DISTINCT BkpFromHost, BkpFromPath
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays_default day)
        AND BkpToHost LIKE 'phd-bkp-gw\%'
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
            $type = 'systemshare' unless $share =~ /export|imap/;
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

sub statistics_groupshare_variations {

    get_global_config();
    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT BkpFromPath, TotFileSize, NumOfFiles
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays_variations day)
        AND BkpFromHost = 'phd-san-gw2'
        AND BkpFromPath LIKE '\%export/groupdata/\%'
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        ORDER BY Start;
    ");
    $sth->execute();

    my %datahash;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/://g; # remove colon separators

        push( @{$datahash{$BkpFromPath}}, {
            BkpFromPath      => $BkpFromPath,
            TotFileSize      => $dbrow->{'TotFileSize'},
            NumOfFiles       => $dbrow->{'NumOfFiles'},
        });
    }
    $sth->finish();

    my %largest_variations;
    foreach my $field (qw(TotFileSize NumOfFiles)) {
        # compute maximal variation for each share
        my %delta;
        foreach my $bkppath ( keys %datahash ) {
            my $max = sprintf("%.2f", max( map{$_->{$field}} @{$datahash{$bkppath}} ));
            my $min = sprintf("%.2f", min( map{$_->{$field}} @{$datahash{$bkppath}} ));
            $delta{$bkppath} = $max - $min;
        }

        # extract groupshares with largest variations (in absolute values)
        my $count = 1;
        my $base  = 1000.;
        $base     = 1024. if $field =~ /Size/;
        foreach my $bkppath ( reverse sort {abs($delta{$a})<=>abs($delta{$b})} keys %delta ) {
            (my $sharename = $bkppath) =~ s|/export/||;
            push( @{$largest_variations{$field}}, {
                share => $sharename,
                delta => num2human($delta{$bkppath}, $base),
            });
            last if $count >= $topX_variations;
            $count++;
        }
    }

    return \%largest_variations;
}

sub statistics_schedule {
    my ($days, $sortBy) = @_;
    my $lastXdays = $days || $lastXdays_default;

    get_global_config();
    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM statistic_all
        WHERE Start > date_sub(concat(curdate(),' $BackupStartHour:00:00'), interval $lastXdays day)
        AND BkpToHost LIKE 'phd-bkp-gw'
        AND isThread is Null
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
    my %datahash = %{shift()};

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
