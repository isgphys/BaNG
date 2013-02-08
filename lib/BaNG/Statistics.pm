package BaNG::Statistics;
use Dancer ':syntax';
use BaNG::Reporting;
use Date::Parse;
use List::Util qw(min max);
use List::MoreUtils qw(uniq);
use POSIX qw(floor);

use Exporter 'import';
our @EXPORT = qw(
    statistics_json
    statistics_cumulated_json
    statistics_decode_path
    statistics_hosts_shares
    statistics_groupshare_variations
);

my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesTrans NumOfFiles RealRuntime TotRuntime );
my $lastXdays_default    = 150; # retrieve info of last X days from database
my $lastXdays_variations = 10;  # find largest variation of the last X days
my $topX_variations      = 5;   # return the top X shares with largest variations
my $BackupStartHour      = 18;  # backups started after X o'clock belong to next day

sub statistics_decode_path {
    my ($path) = @_;

    $path =~ s|_|/|g;                               # decode underscores to slashes
    $path = '/' . $path unless ($path =~ m|^/|);    # should always start with slash

    return $path;
}

sub statistics_json {
    my ($host, $share, $days) = @_;
    my $lastXdays = $days || $lastXdays_default;

    bangstat_db_connect();
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
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

    bangstat_db_connect();
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
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
    while (my $dbrow=$sth->fetchrow_hashref()) {
        my ($date, $time) = split(/\s+/,$dbrow->{'Start'});

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
        if ($hh >= $BackupStartHour) {
            $epoch += 24*3600;
        }

        # compute wall-clock runtime of backup in minutes with 2 digits
        my $RealRuntime = sprintf("%.2f", (str2time($time_stop)-str2time($time_start)) / 60.);

        # store cumulated statistics for each day
        $CumulateByDate{$epoch}{time_coord}        = $epoch;
        $CumulateByDate{$epoch}{RealRuntime}      += $RealRuntime;
        $CumulateByDate{$epoch}{TotRuntime}       += $dbrow->{'Runtime'}/60.;
        $CumulateByDate{$epoch}{TotFileSize}      += $dbrow->{'TotFileSize'};
        $CumulateByDate{$epoch}{TotFileSizeTrans} += $dbrow->{'TotFileSizeTrans'};
        $CumulateByDate{$epoch}{NumOfFiles}       += $dbrow->{'NumOfFiles'};
        $CumulateByDate{$epoch}{NumOfFilesTrans}  += $dbrow->{'NumOfFilesTrans'};
    }
    $sth->finish();

    # remove first day with incomplete information
    delete $CumulateByDate{(sort keys %CumulateByDate)[0]};

    # reshape data structure similar to BackupsByPath
    my %BackupsByDay;
    foreach my $date (sort keys %CumulateByDate) {
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

    bangstat_db_connect();
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
        SELECT
        DISTINCT BkpFromHost, BkpFromPath
        FROM statistic_all
        WHERE Start > date_sub(now(), interval $lastXdays_default day)
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        AND ( BkpFromPath LIKE '\%export\%' OR BkpFromPath LIKE '%imap%' )
        ORDER BY BkpFromHost;
    ");
    $sth->execute();

    my %hosts_shares;
    while (my $dbrow=$sth->fetchrow_hashref()) {
        my $hostname    = $dbrow->{'BkpFromHost'};
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/\s//g; # remove whitespace
        my ($empty, @shares) = split(/:/, $BkpFromPath);

        push( @{$hosts_shares{$hostname}}, @shares );
    }
    $sth->finish();

    # filter duplicate shares
    foreach my $host (sort keys %hosts_shares) {
        @{$hosts_shares{$host}} = uniq @{$hosts_shares{$host}};
    }

    return %hosts_shares;
}

sub statistics_groupshare_variations {

    bangstat_db_connect();
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
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
    while (my $dbrow=$sth->fetchrow_hashref()) {
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
        foreach my $bkppath (keys %datahash) {
            my $max = sprintf("%.2f", max( map{$_->{$field}} @{$datahash{$bkppath}} ));
            my $min = sprintf("%.2f", min( map{$_->{$field}} @{$datahash{$bkppath}} ));
            $delta{$bkppath} = $max - $min;
        }

        # extract groupshares with largest variations (in absolute values)
        my $count = 1;
        my $base  = 1000.;
        $base     = 1024. if $field =~ /Size/;
        foreach my $bkppath (reverse sort {abs($delta{$a})<=>abs($delta{$b})} keys %delta) {
            (my $sharename = $bkppath) =~ s|/export/||;
            push( @{$largest_variations{$field}}, {
                share => $sharename,
                delta => num2human($delta{$bkppath}, $base),
            });
            last if $count >= $topX_variations;
            $count++;
        }
    }

    return %largest_variations;
}

sub rickshaw_json {
    my %datahash = %{shift()};

    my %rickshaw_data;
    foreach my $bkppath (sort keys %datahash) {
        my (%min, %max);
        foreach my $field (@fields) {
            # find min- and maxima of given fields
            $max{$field}  = sprintf("%.2f", max( map{$_->{$field}} @{$datahash{$bkppath}} ));
            $min{$field}  = sprintf("%.2f", min( map{$_->{$field}} @{$datahash{$bkppath}} ));
        }
        # use same normalization for both runtimes to ensure curves coincide
        foreach my $field (qw(RealRuntime TotRuntime)) {
            $max{$field}  = max( $max{RealRuntime}, $max{TotRuntime} );
            $min{$field}  = min( $min{RealRuntime}, $min{TotRuntime} );
        }

        foreach my $bkp (@{$datahash{$bkppath}}) {
            my $t = $bkp->{'time_coord'}; # monotonically increasing coordinate to have single-valued function

            foreach my $field (@fields) {
                my $normalized = 0.5;
                if( $min{$field} != $max{$field} ) {
                    $normalized = ($bkp->{$field} - $min{$field}) / ($max{$field} - $min{$field});
                }

                my $humanreadable;
                if( $field =~ /Runtime/ ) {
                    $humanreadable = "\"" . time2human($bkp->{$field}) . "\"";
                } elsif( $field =~ /Size/ ) {
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

sub num2human {
    # convert large numbers to K, M, G, T notation
    my ($num, $base) = @_;
    $base = $base || 1000.;

    foreach my $unit ('', qw(K M G T P)) {
        if ($num < $base) {
            if ($num < 10 && $num > 0) {
                return sprintf("\%.1f \%s", $num, $unit);  # print small values with 1 decimal
            }
            else {
                return sprintf("\%.0f \%s", $num, $unit);  # print larger values without decimals
            }
        }
        $num = $num / $base;
    }
}

sub time2human {
    # convert large times in minutes to hours
    my ($minutes) = @_;

    if ($minutes < 60) {
        return sprintf("%d min", $minutes);
    } else {
        return sprintf("\%dh\%02dmin", floor($minutes/60), $minutes%60);
    }
}

1;
