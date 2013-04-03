package BaNG::Reporting;

use Dancer ':syntax';
use BaNG::Config;
use BaNG::Common;
use Date::Parse;
use DBI;
use IO::Socket;
use Mail::Sendmail;
use POSIX qw( strftime );
use Template;
use YAML::Tiny;

use Exporter 'import';
our @EXPORT = qw(
    $bangstat_dbh
    bangstat_db_connect
    bangstat_set_jobstatus
    bangstat_recentbackups
    bangstat_recentbackups_all
    send_hobbit_report
    db_report
    mail_report
    hobbit_report
    logit
);

our %globalconfig;
our $bangstat_dbh;

sub bangstat_db_connect {
    my ($ConfigBangstat) = @_;

    my $yaml = YAML::Tiny->read($ConfigBangstat);
    my $DBhostname = $yaml->[0]{DBhostname};
    my $DBusername = $yaml->[0]{DBusername};
    my $DBdatabase = $yaml->[0]{DBdatabase};
    my $DBpassword = $yaml->[0]{DBpassword};

    $bangstat_dbh = DBI->connect(
        "DBI:mysql:database=$DBdatabase:host=$DBhostname:port=3306", $DBusername, $DBpassword
    );

    return 1;
}

sub bangstat_set_jobstatus {
    my ($host, $group, $lastbkp, $status) = @_;

    my $SQL = qq(
        UPDATE statistic
        SET JobStatus = '$status'
        WHERE BkpFromHost = '$host'
        AND BkpGroup = '$group'
        AND LastBkp = '$lastbkp';
    );

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare($SQL);
    $sth->execute() unless $globalconfig{dryrun};
    $sth->finish();

    $SQL =~ s/;.*/;/sg;
    logit( $host, $group, "Set jobstatus SQL command: $SQL" ) if ( $globalconfig{debug} && $globalconfig{debuglevel} >= 2 );
    logit( $host, $group, "Set jobstatus to $status for host $host group $group" );

    return 1;
}

sub bangstat_recentbackups {
    my ($host, $lastXdays) = @_;

    $lastXdays = $lastXdays || 5;
    my $BkpStartHour = 18;

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT *, TIMESTAMPDIFF(Minute, Start , Stop) as Runtime
        FROM recent_backups
        WHERE Start > date_sub(concat(curdate(),' $BkpStartHour:00:00'), interval $lastXdays day)
        AND BkpFromHost like '$host'
        AND JobStatus = '1'
        ORDER BY BkpGroup, Start DESC;
    ");
    $sth->execute();

    my %RecentBackups;
    my %RecentBackupTimes;
    while (my $dbrow=$sth->fetchrow_hashref()) {
        my $BkpGroup = $dbrow->{'BkpGroup'} || 'NA';
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/^:$/:\//g;
        push( @{$RecentBackups{"$host-$BkpGroup"}}, {
            Starttime   => $dbrow->{'Start'},
            Stoptime    => $dbrow->{'Stop'},
            Runtime     => time2human($dbrow->{'Runtime'}),
            BkpFromPath => $BkpFromPath,
            BkpToPath   => $dbrow->{'BkpToPath'} ,
            isThread    => $dbrow->{'isThread'},
            LastBkp     => $dbrow->{'LastBkp'},
            ErrStatus   => $dbrow->{'ErrStatus'},
            BkpGroup    => $BkpGroup,
        });
        push( @{$RecentBackupTimes{"$host-$dbrow->{'BkpFromPath'}"}}, {
            Starttime   => $dbrow->{'Start'},
            BkpFromPath => $dbrow->{'BkpFromPath'},
            BkpToPath   => $dbrow->{'BkpToPath'},
            Host        => $host,
            BkpGroup    => $BkpGroup,
        });
    }
    $sth->finish();

    # scan for missing backups
    my $now     = time;
    my $today   = `date -d \@$now +"%Y-%m-%d"`;
    my $tonight = str2time( "$today $BkpStartHour:00:00" );
    foreach my $hostpath ( keys %RecentBackupTimes ) {
        my $thatnight = $tonight;
        my @bkp = @{$RecentBackupTimes{$hostpath}};
        my $missingBkpFromPath = $bkp[0]->{BkpFromPath} || 'NA';
        my $missingBkpToPath   = $bkp[0]->{BkpToPath}   || 'NA';
        my $missingBkpGroup    = $bkp[0]->{BkpGroup}    || 'NA';
        my $missingHost        = $bkp[0]->{Host}        || 'NA';

        foreach my $Xdays (1..$lastXdays) {
            my $isMissing = 0;

            if ( !@bkp ) {
                # a backup is missing if list is already empty
                $isMissing = 1;
            } else {
                # or if no backup occured during that day
                my $latestbkp = str2time( $bkp[0]->{Starttime} );
                unless ( $latestbkp > $thatnight - 24*3600
                      && $latestbkp < $thatnight ) {
                    $isMissing = 1;
                }
            }

            if ( $isMissing ) {
                # add empty entry for missing backups
                my $missingepoch = $thatnight - 24*3600;
                my $missingday   = `date -d \@$missingepoch +"%Y-%m-%d"`;
                my $nobkp = {
                    Starttime   => $missingday,
                    Stoptime    => '',
                    Runtime     => '',
                    BkpFromPath => $missingBkpFromPath,
                    BkpToPath   => $missingBkpToPath,
                    isThread    => '',
                    LastBkp     => '',
                    ErrStatus   => 99,
                    BkpGroup    => $missingBkpGroup,
                };
                splice( @{$RecentBackups{"$missingHost-$missingBkpGroup"}}, $Xdays-1, 0, $nobkp);
            } else {
                # remove successful backups of that day from list
                while ( @bkp && str2time($bkp[0]->{Starttime}) > $thatnight - 24*3600 ) {
                    shift @bkp;
                }
            }
            # then look at previous day
            $thatnight -= 24*3600;
        }
    }

    return %RecentBackups;
}

sub bangstat_recentbackups_all {
    my ($host, $lastXhours) = @_;

    $lastXhours = $lastXhours || 24;

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare("
        SELECT *, TIMESTAMPDIFF(Minute, Start , Stop) as Runtime
        FROM recent_backups
        WHERE Start > date_sub(NOW(), INTERVAL $lastXhours HOUR)
        AND BkpFromHost like '%'
        ORDER BY JobStatus, Start DESC;
    ");
    $sth->execute();

    my %RecentBackupsAll;
    while (my $dbrow=$sth->fetchrow_hashref()) {
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath =~ s/^:$/:\//g;
        push( @{$RecentBackupsAll{'Data'}}, {
            Starttime   => $dbrow->{'Start'},
            Stoptime    => $dbrow->{'Stop'},
            Runtime     => time2human($dbrow->{'Runtime'}),
            BkpFromPath => $BkpFromPath ,
            BkpToPath   => $dbrow->{'BkpToPath'},
            isThread    => $dbrow->{'isThread'},
            LastBkp     => $dbrow->{'LastBkp'},
            ErrStatus   => $dbrow->{'ErrStatus'},
            JobStatus   => $dbrow->{'JobStatus'},
            BkpGroup    => $dbrow->{'BkpGroup'} || 'NA',
            BkpHost     => $dbrow->{'BkpFromHost'},
        });
    }
    $sth->finish();

    return \%RecentBackupsAll;
}

sub send_hobbit_report {
    my ($report) = @_;

    my $socket=IO::Socket::INET->new(
        PeerAddr => 'hobbit.phys.ethz.ch',
        PeerPort => '1984',
        Proto    => 'tcp',
    );

    if ( defined $socket and $socket != 0 ) {
        $socket->print("$report");
        $socket->close();
    }

    return 1;
}

sub db_report {
    my ($host, $group, $startstamp, $endstamp, $path, $targetpath, $lastbkp, $errcode, @outlines) = @_;

    my %parse_log_keys = (
        'last backup'                 => 'LastBkp',
        'Number of files'             => 'NumOfFiles',
        'Number of files transferred' => 'NumOfFilesTrans',
        'Total file size'             => 'TotFileSize',
        'Total transferred file size' => 'TotFileSizeTrans',
        'Literal data'                => 'LitData',
        'Matched data'                => 'MatchData',
        'File list size'              => 'FileListSize',
        'File list generation time'   => 'FileListGenTime',
        'File list transfer time'     => 'FileListTransTime',
        'Total bytes sent'            => 'TotBytesSent',
        'Total bytes received'        => 'TotBytesRcv',
    );

    my %log_values;
    foreach my $logkey ( keys %parse_log_keys ) {
        $log_values{$parse_log_keys{$logkey}} = 'NULL';
    }

    foreach my $outline ( @outlines ) {
        next unless $outline =~ m/:/;
        chomp $outline;
        my ($key, $value) = split(': ', $outline);
        foreach my $logkey ( keys %parse_log_keys ) {
            if ( $logkey eq $key ) {
                $value =~ s/^\D*([\d.]+).*?$/$1/;
                $log_values{$parse_log_keys{$logkey}} = $value;
            }
        }
    }

    $path =~ s/'//g;    # rm quotes to avoid errors in sql syntax
    my $isSubfolderThread = $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS} ? 'true' : 'NULL';

    my $sql;
    $sql .= "INSERT INTO statistic (";
    $sql .= " BkpFromHost, BkpGroup,  BkpFromPath, BkpToHost, BkpToPath, LastBkp, isThread, ErrStatus, JobStatus, Start, Stop, ";
    $sql .= " NumOfFiles, NumOfFilesTrans, TotFileSize, TotFileSizeTrans, LitData, MatchData, ";
    $sql .= " FileListSize, FileListGenTime, FileListTransTime, TotBytesSent, TotBytesRcv ";
    $sql .= ") VALUES (";
    $sql .= "'$host', '$group', '$path', '$servername', '$targetpath', '$lastbkp', ";
    $sql .= " $isSubfolderThread , '$errcode', 0, FROM_UNIXTIME('$startstamp'), FROM_UNIXTIME('$endstamp'), ";
    $sql .= "'$log_values{NumOfFiles}'  , '$log_values{NumOfFilesTrans}', ";
    $sql .= "'$log_values{TotFileSize}' , '$log_values{TotFileSizeTrans}', ";
    $sql .= "'$log_values{LitData}'     , '$log_values{MatchData}', ";
    $sql .= "'$log_values{FileListSize}', '$log_values{FileListGenTime}', '$log_values{FileListTransTime}', ";
    $sql .= "'$log_values{TotBytesSent}', '$log_values{TotBytesRcv}' ";
    $sql .= ")";
    logit( $host, $group, "DB Report SQL command: $sql" ) if ( $globalconfig{debuglevel} >=2 );

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $bangstat_dbh->prepare($sql);
    $sth->execute() unless $globalconfig{dryrun};
    $sth->finish();

    logit( $host, $group, "Bangstat report sent.");

    return 1;
}

sub mail_report {
    my ($host, $group, %RecentBackups) = @_;

    my %mail = (
        To      => $globalconfig{report_to},
        From    => 'root@phys.ethz.ch',
        Subject => "Backup report of ($host-$group): success",
        Message => "* * * Backup report * * *\n\nBacking up: $host-$group\n\n* * * Backup successfull * * *\n",
    );
    unless ($globalconfig{dryrun}) {
        sendmail(%mail) or logit( $host, $group, "mail_report error: $Mail::Sendmail::error" );
    }

    logit( $host, $group, "Mail report sent.");

    return 1;
}

sub hobbit_report {
    my ($host, $group, %RecentBackups)  = @_;

    my $RecentBackups = { RecentBackups => \%RecentBackups };

    my $topcolor = 'green';
    my $errcode;
    foreach my $key (keys %RecentBackups) {
        $errcode  = $RecentBackups{$key}[0]{ErrStatus};
        $topcolor = 'red' if ( $errcode gt 0 && !( $errcode eq 23 || $errcode eq 24 || $errcode eq 99 ));
    }

    my $STATUSTTL = 2160;     # (2160=>1.5d) Time in min until page becomes purple
    my $DATE      = `date`;
    chomp $DATE;

    my $hobbitreport = "status+$STATUSTTL $host.bkp $topcolor $DATE (TTL=$STATUSTTL min)\n";

    my $tt = Template->new(
        START_TAG  => '<%',
        END_TAG    => '%>',
        INCLUDE_PATH => "$prefix/views",
    );
    my $report;
    $tt->process('hobbitreport.tt', $RecentBackups, \$report)
        or logit( $host, $group, "Error generating hobbit report template: " . $tt->error() );
    $hobbitreport .= $report;

    send_hobbit_report($hobbitreport) unless $globalconfig{dryrun};
    logit( $host, $group, "Hobbit report sent.");

    return 1;
}

sub logit {
    my ($host, $group, $msg) = @_;

    my $timestamp  = strftime "%b %d %H:%M:%S", localtime;
    my $logdate    = strftime $globalconfig{global_log_date}, localtime;
    my $logfile    = "$globalconfig{'log_path'}/${host}-${group}_$logdate.log";
    my $logmessage = "$timestamp $host-$group : $msg";
    $logmessage   .= "\n" unless ( $logmessage =~ m/\n$/ );

    print $logmessage if $globalconfig{debug};

    unless ($globalconfig{dryrun}) {
        open my $log, ">>", $logfile or print "Error opening logfile $logfile: $!\n";
        print {$log} $logmessage;
        close $log;
    }

    return 1;
}

1;
