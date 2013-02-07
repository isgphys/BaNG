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
);

my @fields = qw( TotFileSizeTrans TotFileSize NumOfFilesTrans NumOfFiles Runtime );
my $lastXdays_default = 150;    # retrieve info of last 150 days from database
my $BackupStartHour   = 18;     # backups started after 18:00 belong to next day

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
    my %BackupsByShare = bangstat_db_query_statistics($host, $share, $lastXdays);

    return rickshaw_json(\%BackupsByShare);
}

sub statistics_cumulated_json {
    my ($days) = @_;
    my $lastXdays = $days || $lastXdays_default;

    bangstat_db_connect();
    my %BackupsByDay = bangstat_db_query_statistics_cumulated($lastXdays);

    return rickshaw_json(\%BackupsByDay);
}

sub statistics_hosts_shares {

    bangstat_db_connect();
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
        SELECT
        DISTINCT BkpFromHost, BkpFromPath
        FROM statistic_all
        WHERE Start > date_sub(now(), interval 10000 day)
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

    # filter duplicate shares
    foreach my $host (sort keys %hosts_shares) {
        @{$hosts_shares{$host}} = uniq @{$hosts_shares{$host}};
    }

    return %hosts_shares;
}

sub bangstat_db_query_statistics {
    my ($host, $share, $lastXdays) = @_;

    # query database
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

        # compute runtime of backup in minutes with 2 digits
        my $Runtime = sprintf("%.2f", (str2time($time_stop)-str2time($time_start)) / 60.);

        push( @{$BackupsByPath{$BkpFromPath}}, {
            time_coord       => str2time($time_start),
            Runtime          => $Runtime,
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
    # disconnect database
    $sth->finish();

    return %BackupsByPath;
}

sub bangstat_db_query_statistics_cumulated {
    my ($lastXdays) = @_;

    # query database
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

        # store cumulated statistics for each day
        $CumulateByDate{$epoch}{time_coord}        = $epoch;
        $CumulateByDate{$epoch}{Runtime}          += $dbrow->{'Runtime'}/60.;
        $CumulateByDate{$epoch}{TotFileSize}      += $dbrow->{'TotFileSize'};
        $CumulateByDate{$epoch}{TotFileSizeTrans} += $dbrow->{'TotFileSizeTrans'};
        $CumulateByDate{$epoch}{NumOfFiles}       += $dbrow->{'NumOfFiles'};
        $CumulateByDate{$epoch}{NumOfFilesTrans}  += $dbrow->{'NumOfFilesTrans'};
    }
    # disconnect database
    $sth->finish();

    # remove first day with incomplete information
    delete $CumulateByDate{(sort keys %CumulateByDate)[0]};

    # reshape data structure similar to BackupsByPath
    my %BackupsByDay;
    foreach my $date (sort keys %CumulateByDate) {
        push( @{$BackupsByDay{'Cumulated'}}, {
            time_coord       => $CumulateByDate{$date}{time_coord},
            Runtime          => $CumulateByDate{$date}{Runtime},
            TotFileSize      => $CumulateByDate{$date}{TotFileSize},
            TotFileSizeTrans => $CumulateByDate{$date}{TotFileSizeTrans},
            NumOfFiles       => $CumulateByDate{$date}{NumOfFiles},
            NumOfFilesTrans  => $CumulateByDate{$date}{NumOfFilesTrans},
        });
    }

    return %BackupsByDay;
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
        foreach my $bkp (@{$datahash{$bkppath}}) {
            my $t = $bkp->{'time_coord'}; # monotonically increasing coordinate to have single-valued function

            foreach my $field (@fields) {
                my $normalized = 0.5;
                if( $min{$field} != $max{$field} ) {
                    $normalized = ($bkp->{$field} - $min{$field}) / ($max{$field} - $min{$field});
                }

                my $humanreadable;
                if( $field eq 'Runtime' ) {
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
        "Runtime"          => "#00CC00",
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
        return "$minutes min";
    } else {
        return sprintf("\%dh\%02dmin", floor($minutes/60), $minutes%60);
    }
}

1;
