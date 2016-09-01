package BaNG::Reporting;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use BaNG::Converter;
use DBI;
use Date::Parse;
use IO::Socket;
use MIME::Lite;
use POSIX qw( strftime );
use Template;
use YAML::Tiny;

use Exporter 'import';
our @EXPORT = qw(
    $bangstat_dbh
    bangstat_db_connect
    bangstat_recentbackups
    bangstat_recentbackups_hours
    bangstat_recentbackups_last
    bangstat_recent_tasks
    bangstat_task_jobs
    bangstat_start_backupjob
    bangstat_set_taskmeta
    bangstat_update_backupjob
    bangstat_finish_backupjob
    send_xymon_report
    mail_report
    xymon_report
    logit
    read_log
    read_global_log
    delete_logfiles
    error404
);

our %serverconfig;
our $bangstat_dbh;

sub bangstat_db_connect {
    my ($ConfigBangstat) = @_;

    my $yaml       = YAML::Tiny->read($ConfigBangstat);
    my $DBhostname = $yaml->[0]{DBhostname};
    my $DBusername = $yaml->[0]{DBusername};
    my $DBdatabase = $yaml->[0]{DBdatabase};
    my $DBpassword = $yaml->[0]{DBpassword};

    $bangstat_dbh = DBI->connect(
        "DBI:mysql:database=$DBdatabase:host=$DBhostname:port=3306", $DBusername, $DBpassword,
        { PrintError => 0 }
    );

    return 0 unless $bangstat_dbh;
    return 1;
}

sub bangstat_recentbackups {
    my ( $host, $lastXdays ) = @_;

    $lastXdays ||= 14;
    my $BkpStartHour = 18;

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return () unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM recent_backups
        WHERE Start > date_sub(concat(curdate(),' $BkpStartHour:00:00'), interval $lastXdays day)
        AND BkpFromHost like '$host'
        ORDER BY BkpGroup, Start DESC;
    ");
    $sth->execute();

    my %RecentBackups;
    my %RecentBackupTimes;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $BkpGroup    = $dbrow->{'BkpGroup'} || 'NA';
        my $Runtime     = $dbrow->{'Runtime'} ? $dbrow->{'Runtime'} / 60 : '-';
        my $BkpFromPath = $dbrow->{'BkpFromPathRoot'};
        $BkpFromPath    =~ s/^:$/:\//g;
        push( @{$RecentBackups{"$host-$BkpGroup"}}, {
            TaskID       => $dbrow->{'TaskID'},
            JobID        => $dbrow->{'JobID'},
            Starttime    => $dbrow->{'Start'},
            Stoptime     => $dbrow->{'Stop'},
            Runtime      => time2human($Runtime),
            BkpFromPath  => $BkpFromPath,
            BkpToPath    => $dbrow->{'BkpToPath'} ,
            isThread     => $dbrow->{'isThread'},
            ErrStatus    => $dbrow->{'ErrStatus'},
            JobStatus    => $dbrow->{'JobStatus'},
            BkpGroup     => $BkpGroup,
            BkpHost      => $dbrow->{'BkpFromHost'},
            FilesCreated => num2human($dbrow->{'NumOfFilesCreated'}),
            FilesDel     => num2human($dbrow->{'NumOfFilesDel'}),
            FilesTrans   => num2human($dbrow->{'NumOfFilesTrans'}),
            SizeTrans    => num2human($dbrow->{'TotFileSizeTrans'},1024),
            TotFileSize  => num2human($dbrow->{'TotFileSize'},1024),
            NumOfFiles   => num2human($dbrow->{'NumOfFiles'}),
        });
        push( @{$RecentBackupTimes{"$host-$dbrow->{'BkpFromPathRoot'}"}}, {
            TaskID      => $dbrow->{'TaskID'},
            JobID       => $dbrow->{'JobID'},
            Starttime   => $dbrow->{'Start'},
            BkpFromPath => $dbrow->{'BkpFromPathRoot'},
            BkpToPath   => $dbrow->{'BkpToPath'},
            Host        => $host,
            BkpGroup    => $BkpGroup,
        });
    }
    $sth->finish();

    # depending on the current time, define when the next backup period starts
    my $now      = time;
    my $today    = `$serverconfig{path_date} -d \@$now +"%Y-%m-%d"`;
    my $one_day  = 24 * 3600;
    my $next_bkp = str2time("$today $BkpStartHour:00:00");
    $next_bkp += $one_day if ( $next_bkp < $now );

    # scan for missing backups
    foreach my $hostpath ( keys %RecentBackupTimes ) {
        my $nextBkpStart = $next_bkp;
        my $prevBkpStart = $nextBkpStart - $one_day;

        my @bkp                = @{$RecentBackupTimes{$hostpath}};
        my $missingBkpFromPath = $bkp[0]->{BkpFromPathRoot} || 'NA';
        my $missingBkpToPath   = $bkp[0]->{BkpToPath}   || 'NA';
        my $missingBkpGroup    = $bkp[0]->{BkpGroup}    || 'NA';
        my $missingHost        = $bkp[0]->{Host}        || 'NA';

        foreach my $Xdays ( 1 .. $lastXdays ) {
            my $isMissing = 0;

            if ( !@bkp ) {
                # a backup is missing if list is already empty
                $isMissing = 1;
            } else {
                # or if no backup occured during that day
                my $latestbkp = str2time( $bkp[0]->{Starttime} );
                unless ( $latestbkp > $prevBkpStart
                      && $latestbkp < $nextBkpStart )
                {
                    $isMissing = 1;
                }
            }

            if ($isMissing) {
                # add empty entry for missing backups
                my $missingepoch = $prevBkpStart;
                my $missingday   = `$serverconfig{path_date} -d \@$missingepoch +"%Y-%m-%d"`;
                chomp $missingday;
                my $nobkp = {
                    Starttime   => $missingday,
                    Stoptime    => '',
                    Runtime     => '',
                    BkpFromPath => $missingBkpFromPath,
                    BkpToPath   => $missingBkpToPath,
                    JobStatus   => '',
                    isThread    => '',
                    ErrStatus   => 99,
                    BkpGroup    => $missingBkpGroup,
                };
                splice( @{$RecentBackups{"$missingHost-$missingBkpGroup"}}, $Xdays - 1, 0, $nobkp );
            } else {
                # remove successful backups of that day from list
                while ( @bkp && str2time( $bkp[0]->{Starttime} ) > $prevBkpStart ) {
                    shift @bkp;
                }
            }

            # then look at previous day
            $nextBkpStart -= $one_day;
            $prevBkpStart -= $one_day;
        }
    }

    return %RecentBackups;
}

sub bangstat_recentbackups_hours {
    my ($lastXhours) = @_;
    $lastXhours ||= 24;

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
    SELECT JobID, BkpGroup, MIN(Start) as Start, TIMESTAMPDIFF(Second, MIN(Start), MAX(Stop)) as Runtime,
        BkpFromHost, BkpToHost, isThread,
        SUM(NumOfFiles) as NumOfFiles, SUM(TotFileSize) as TotFileSize,
        SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
        SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans,
        GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus, MIN(JobStatus) as JobStatus
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL $lastXhours HOUR)
        AND BkpFromHost like '%'
    GROUP BY JobID, BkpGroup, BkpFromHost, BkpToHost, isThread;
    ");
    $sth->execute();

    my %RecentBackupsAll;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $Runtime     = $dbrow->{'Runtime'} ? $dbrow->{'Runtime'} / 60 : '-';
        push( @{$RecentBackupsAll{'Data'}}, {
            JobID        => $dbrow->{'JobID'},
            JobStatus    => $dbrow->{'JobStatus'},
            isThread     => $dbrow->{'isThread'},
            BkpHost      => $dbrow->{'BkpFromHost'},
            BkpGroup     => $dbrow->{'BkpGroup'} || 'NA',
            BkpToHost    => $dbrow->{'BkpToHost'},
            ErrStatus    => $dbrow->{'ErrStatus'},
            Starttime    => $dbrow->{'Start'},
            Runtime      => time2human($Runtime),
            FilesCreated => num2human($dbrow->{'NumOfFilesCreated'}),
            FilesDel     => num2human($dbrow->{'NumOfFilesDel'}),
            FilesTrans   => num2human($dbrow->{'NumOfFilesTrans'}),
            SizeTrans    => num2human($dbrow->{'TotFileSizeTrans'},1024),
            NumOfFiles   => num2human($dbrow->{'NumOfFiles'}),
            TotFileSize  => num2human($dbrow->{'TotFileSize'},1024),
        });
    }
    $sth->finish();

    return \%RecentBackupsAll;
}

sub bangstat_recentbackups_last {
    my ($lastXhours) = @_;
    $lastXhours ||= 24;

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *
        FROM recent_backups
        WHERE Start > date_sub(NOW(), INTERVAL $lastXhours HOUR)
        AND BkpFromHost like '%'
        ORDER BY Start DESC;
    ");
    $sth->execute();

    my %RecentBackupsLast;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $Runtime     = $dbrow->{'Runtime'} ? $dbrow->{'Runtime'} / 60 : '-';
        my $BkpFromPath = $dbrow->{'BkpFromPathRoot'};
        $BkpFromPath    =~ s/^:$/:\//g;
        push( @{$RecentBackupsLast{'Data'}}, {
            TaskID       => $dbrow->{'TaskID'},
            JobID        => $dbrow->{'JobID'},
            Starttime    => $dbrow->{'Start'},
            Stoptime     => $dbrow->{'Stop'},
            Runtime      => time2human($Runtime),
            BkpFromPath  => $BkpFromPath ,
            BkpToPath    => $dbrow->{'BkpToPath'},
            isThread     => $dbrow->{'isThread'},
            ErrStatus    => $dbrow->{'ErrStatus'},
            JobStatus    => $dbrow->{'JobStatus'},
            BkpGroup     => $dbrow->{'BkpGroup'} || 'NA',
            BkpHost      => $dbrow->{'BkpFromHost'},
            BkpToHost    => $dbrow->{'BkpToHost'},
            FilesCreated => num2human($dbrow->{'NumOfFilesCreated'}),
            FilesDel     => num2human($dbrow->{'NumOfFilesDel'}),
            FilesTrans   => num2human($dbrow->{'NumOfFilesTrans'}),
            SizeTrans    => num2human($dbrow->{'TotFileSizeTrans'},1024),
            TotFileSize  => num2human($dbrow->{'TotFileSize'},1024),
            NumOfFiles   => num2human($dbrow->{'NumOfFiles'}),
        });
    }
    $sth->finish();

    return \%RecentBackupsLast;
}

sub bangstat_recent_tasks {

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT
            statistic.TaskID, COUNT(JobID) as Jobs, MIN(Start) as Start, MAX(Stop) as Stop,
            TIMESTAMPDIFF(Second, MIN(Start), MAX(Stop)) as Runtime, TaskName, Description, Cron,
            BkpToHost, isThread, MAX(JobStatus) as JobStatus,
            GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus,
            SUM(NumOfFiles) as NumOfFiles, SUM(TotFileSize) as TotFileSize,
            SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
            SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans
        FROM statistic
        LEFT JOIN statistic_task_meta USING (TaskID)
        WHERE Start > date_sub(NOW(), INTERVAL 24 HOUR)
        GROUP BY TaskID
        ORDER BY TaskID DESC
    ");
    $sth->execute();

    my %RecentTasks;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $Runtime     = $dbrow->{'Runtime'} ? $dbrow->{'Runtime'} / 60 : '-';
        my $BkpFromPath = $dbrow->{'BkpFromPathRoot'};
        push( @{$RecentTasks{'Data'}}, {
            TaskID       => $dbrow->{'TaskID'},
            Jobs         => $dbrow->{'Jobs'},
            Taskname     => $dbrow->{'TaskName'},
            Description  => $dbrow->{'Description'},
            Cron         => $dbrow->{'Cron'},
            Starttime    => $dbrow->{'Start'},
            Stoptime     => $dbrow->{'Stop'},
            Runtime      => time2human($Runtime),
            isThread     => $dbrow->{'isThread'},
            ErrStatus    => $dbrow->{'ErrStatus'},
            JobStatus    => $dbrow->{'JobStatus'},
            BkpToHost    => $dbrow->{'BkpToHost'},
            FilesCreated => num2human($dbrow->{'NumOfFilesCreated'}),
            FilesDel     => num2human($dbrow->{'NumOfFilesDel'}),
            FilesTrans   => num2human($dbrow->{'NumOfFilesTrans'}),
            SizeTrans    => num2human($dbrow->{'TotFileSizeTrans'},1024),
            TotFileSize  => num2human($dbrow->{'TotFileSize'},1024),
            NumOfFiles   => num2human($dbrow->{'NumOfFiles'}),
        });
    }
    $sth->finish();

    return \%RecentTasks;
}

sub bangstat_task_jobs {
    my ($taskid) = @_;

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    return '' unless $conn;

    my $sth = $bangstat_dbh->prepare("
        SELECT *, TIMESTAMPDIFF(Second, Start , Stop) as Runtime
        FROM statistic
        WHERE TaskID = '$taskid'
        ORDER BY JobStatus, Start;
    ");
    $sth->execute();

    my %TaskJobs;
    while ( my $dbrow = $sth->fetchrow_hashref() ) {
        my $Runtime     = $dbrow->{'Runtime'} ? $dbrow->{'Runtime'} / 60 : '-';
        my $BkpFromPath = $dbrow->{'BkpFromPath'};
        $BkpFromPath    =~ s/^:$/:\//g;
        push( @{$TaskJobs{'Data'}}, {
            TaskID       => $dbrow->{'TaskID'},
            JobID        => $dbrow->{'JobID'},
            Starttime    => $dbrow->{'Start'},
            Stoptime     => $dbrow->{'Stop'},
            Runtime      => time2human($Runtime),
            BkpFromPath  => $BkpFromPath ,
            BkpToPath    => $dbrow->{'BkpToPath'},
            isThread     => $dbrow->{'isThread'},
            ErrStatus    => $dbrow->{'ErrStatus'},
            JobStatus    => $dbrow->{'JobStatus'},
            BkpGroup     => $dbrow->{'BkpGroup'} || 'NA',
            BkpHost      => $dbrow->{'BkpFromHost'},
            BkpToHost    => $dbrow->{'BkpToHost'},
            FilesCreated => num2human($dbrow->{'NumOfFilesCreated'}),
            FilesDel     => num2human($dbrow->{'NumOfFilesDel'}),
            FilesTrans   => num2human($dbrow->{'NumOfFilesTrans'}),
            SizeTrans    => num2human($dbrow->{'TotFileSizeTrans'},1024),
            TotFileSize  => num2human($dbrow->{'TotFileSize'},1024),
            NumOfFiles   => num2human($dbrow->{'NumOfFiles'}),
        });
    }
    $sth->finish();

    return \%TaskJobs;
}

sub send_xymon_report {
    my ($report) = @_;

    return 1 unless $serverconfig{xymon_server};

    my @xymon_servers = split(' ', $serverconfig{xymon_server});

    foreach my $xymon_server (@xymon_servers) {
        my $socket = IO::Socket::INET->new(
            PeerAddr => $xymon_server,
            PeerPort => '1984',
            Proto    => 'tcp',
        );

        if ( defined $socket and $socket != 0 ) {
            $socket->print($report);
            $socket->close();
        }
    }
    return 1;
}

sub bangstat_start_backupjob {
    my ( $taskid, $jobid, $host, $group, $startstamp, $endstamp, $path, $srcfolder, $targetpath, $errcode, $jobstatus, @outlines ) = @_;

    $path =~ s/'//g;    # rm quotes to avoid errors in sql syntax
    my $isSubfolderThread = $hosts{"$host-$group"}->{hostconfig}->{BKP_THREAD_SUBFOLDERS} ? 'true' : 'NULL';

    my $sql = qq(
        INSERT INTO statistic (
            TaskID, JobID, BkpFromHost, BkpGroup, BkpFromPath, BkpFromPathRoot, BkpToHost, BkpToPath,
            isThread, ErrStatus, JobStatus, Start
        ) VALUES (
            '$taskid', '$jobid', '$host', '$group', '$path', '$srcfolder', '$servername', '$targetpath',
            $isSubfolderThread , '$errcode', '$jobstatus', FROM_UNIXTIME('$startstamp')
        )
    );
    logit( $taskid, $host, $group, "DB Report SQL command: $sql" ) if ( $serverconfig{verboselevel} >= 2 );

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    if ( !$conn ) {
        logit( $taskid, $host, $group, "ERROR: Could not connect to DB to send bangstat report." );
        return 1;
    }

    my $sth = $bangstat_dbh->prepare($sql);
    $sth->execute() unless $serverconfig{dryrun};
    $sth->finish();
    $bangstat_dbh->disconnect;

    logit( $taskid, $host, $group, "Bangstat start_backup sent." );

    return 1;
}

sub bangstat_set_taskmeta {
    my ( $taskid, $host, $group, $cron, $override ) = @_;
    $host  ||= 'BULK';
    $group ||= '*';

    my $taskName    = $host ."_". $group;
    my $description = $override || "" ;

    $description = get_taskmeta($host, $group) unless $override;

    print "TaskID: $taskid Taskname: $taskName Description: $description Cron: $cron\n" if $serverconfig{verbose};

    my $sql = qq(
        INSERT INTO statistic_task_meta (
            TaskID, TaskName, Description, Cron
        ) VALUES (
            '$taskid', '$taskName', '$description', '$cron')
    );

    logit( $taskid, $host, $group, "DB Report SQL command: $sql" ) if ( $serverconfig{verboselevel} >= 2 );

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    if ( !$conn ) {
        logit( $taskid, $host, $group, "ERROR: Could not connect to DB to send bangstat report." );
        return 1;
    }

    my $sth = $bangstat_dbh->prepare($sql);
    $sth->execute() unless $serverconfig{dryrun};
    $sth->finish();
    $bangstat_dbh->disconnect;

    logit( $taskid, $host, $group, "Bangstat task_meta sent." );

    return 1;
}

sub bangstat_update_backupjob {
    my ( $taskid, $jobid, $host, $group, $endstamp, $path, $targetpath, $errcode, $jobstatus, @outlines ) = @_;

    my %parse_log_keys = (
        'Number of files'                     => 'NumOfFiles',
        'Number of regular files transferred' => 'NumOfFilesTrans',
        'Number of created files'             => 'NumOfFilesCreated',
        'Number of deleted files'             => 'NumOfFilesDel',
        'Number of files transferred'         => 'NumOfFilesTrans',
        'Total file size'                     => 'TotFileSize',
        'Total transferred file size'         => 'TotFileSizeTrans',
        'Literal data'                        => 'LitData',
        'Matched data'                        => 'MatchData',
        'File list size'                      => 'FileListSize',
        'File list generation time'           => 'FileListGenTime',
        'File list transfer time'             => 'FileListTransTime',
        'Total bytes sent'                    => 'TotBytesSent',
        'Total bytes received'                => 'TotBytesRcv',
    );

    my %log_values;
    foreach my $logkey ( keys %parse_log_keys ) {
        $log_values{$parse_log_keys{$logkey}} = 'NULL';
    }

    foreach my $outline (@outlines) {
        next unless $outline =~ m/:/;
        chomp $outline;
        my ( $key, $value ) = split( ': ', $outline );
        foreach my $logkey ( keys %parse_log_keys ) {
            if ( $logkey eq $key ) {
                $value =~ s/^\D*([\d\.,]+).*?$/$1/;
                $value =~ s/,//g;
                $log_values{$parse_log_keys{$logkey}} = $value;
            }
        }
    }

    $path =~ s/'//g;    # rm quotes to avoid errors in sql syntax

    my $SQL = qq(
        UPDATE statistic
        SET JobStatus         = '$jobstatus',
            ErrStatus         = '$errcode',
            Stop              = FROM_UNIXTIME('$endstamp'),
            NumOfFiles        = '$log_values{NumOfFiles}',
            NumOfFilesTrans   = '$log_values{NumOfFilesTrans}',
            NumOfFilesCreated = '$log_values{NumOfFilesCreated}',
            NumOfFilesDel     = '$log_values{NumOfFilesDel}',
            TotFileSize       = '$log_values{TotFileSize}',
            TotFileSizeTrans  = '$log_values{TotFileSizeTrans}',
            LitData           = '$log_values{LitData}',
            MatchData         = '$log_values{MatchData}',
            FileListSize      = '$log_values{FileListSize}',
            FileListGenTime   = '$log_values{FileListGenTime}',
            FileListTransTime = '$log_values{FileListTransTime}',
            TotBytesSent      = '$log_values{TotBytesSent}',
            TotBytesRcv       = '$log_values{TotBytesRcv}'
        WHERE TaskID          = '$taskid'
            AND JobID         = '$jobid'
            AND BkpFromHost   = '$host'
            AND BkpGroup      = '$group'
            AND BkpFromPath   = '$path';
    );

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    if ( !$conn ) {
        logit( $taskid, $host, $group, 'ERROR: Could not connect to DB to send bangstat report.' );
        return 1;
    }

    my $sth = $bangstat_dbh->prepare($SQL);
    $sth->execute() unless $serverconfig{dryrun};
    $sth->finish();
    $bangstat_dbh->disconnect;

    $SQL =~ s/;.*/;/sg;
    logit( $taskid, $host, $group, "Set jobstatus SQL command: $SQL" ) if ( $serverconfig{verbose} && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "Set jobstatus to $jobstatus for host $host group $group jobid $jobid" );

    return 1;
}

sub bangstat_finish_backupjob {
    my ( $taskid, $jobid, $host, $group, $jobstatus ) = @_;

    my $SQL = qq(
        UPDATE statistic
            SET JobStatus = '$jobstatus'
        WHERE BkpFromHost = '$host'
            AND BkpGroup  = '$group'
            AND JobID     = '$jobid';
    );

    my $conn = bangstat_db_connect( $serverconfig{config_bangstat} );
    if ( !$conn ) {
        logit( $taskid, $host, $group, "ERROR: Could not connect to DB to set jobstatus to $jobstatus for host $host group $group" );
        return 1;
    }

    my $sth = $bangstat_dbh->prepare($SQL);
    $sth->execute() unless $serverconfig{dryrun};
    $sth->finish();

    $SQL =~ s/;.*/;/sg;
    logit( $taskid, $host, $group, "Set jobstatus SQL command: $SQL" ) if ( $serverconfig{verbose} && $serverconfig{verboselevel} >= 2 );
    logit( $taskid, $host, $group, "Set jobstatus to $jobstatus for host $host group $group jobid $jobid" );

    return 1;
}

sub mail_report {
    my ( $taskid, $host, $group, %RecentBackups ) = @_;

    my $status = $hosts{"$host-$group"}->{errormsg} ? 'warnings' : 'success';

    unless ( $status eq 'success' ) {
        my $RecentBackups = {
            RecentBackups => \%RecentBackups,
            Group         => "$host-$group",
            Errormsg      => $hosts{"$host-$group"}->{errormsg},
        };

        my $tt = Template->new(
            START_TAG    => '<%',
            END_TAG      => '%>',
            INCLUDE_PATH => "$prefix/views",
        );

        my $mail_msg = MIME::Lite->new(
            From    => 'root@phys.ethz.ch',
            To      => $serverconfig{report_to},
            Type    => 'multipart/alternative',
            Subject => "Backup report of ($host-$group): $status",
        );

        foreach my $mailtype (qw(plain html)) {
            my $report;
            $tt->process( "report-mail_$mailtype.tt", $RecentBackups, \$report )
                or logit( $taskid, $host, $group, 'ERROR generating mail report template: ' . $tt->error() );

            my $mail_att = MIME::Lite->new(
                Type     => 'text',
                Data     => $report,
                Encoding => 'quoted-printable',
            );
            $mail_att->attr( 'content-type' => "text/$mailtype; charset=UTF-8" );
            $mail_msg->attach($mail_att);
        }

        unless ( $serverconfig{dryrun} ) {
            $mail_msg->send or logit( $taskid, $host, $group, 'mail_report error' );
        }

        logit( $taskid, $host, $group, 'Mail report sent.' );
    }
    return 1;
}

sub xymon_report {
    my ( $taskid, $host, $group, %RecentBackups ) = @_;

    my $topcolor = 'green';
    my $errcode;
    foreach my $key ( sort keys %RecentBackups ) {
        if ( $RecentBackups{$key}[0]{JobStatus} eq "-1" ) {
            $topcolor = 'clear';
        }else{
            $errcode = $RecentBackups{$key}[0]{ErrStatus};
            my @errorcodes = split( ',', $errcode );
            foreach my $code (@errorcodes) {
                next if $code eq '0';     # no errors
                next if $code eq '24';    # vanished source files
                next if $code eq '99';    # no last_bkp
                if ( $code eq '23' || $code eq '12' ) {
                    $topcolor = 'yellow'; # partial transfer
                    next;
                }
                $topcolor = 'red';
            }
        }
    }
    $topcolor = 'yellow' unless %RecentBackups;

    my $RecentBackups = {
        RecentBackups => \%RecentBackups,
        Group         => "$host-$group",
        xymonTopColor => $topcolor,
        Errormsg      => $hosts{"$host-$group"}->{errormsg},
    };

    my $STATUSTTL = 2160;     # (2160=>1.5d) Time in min until page becomes purple
    my $DATE      = `$serverconfig{path_date}`;
    chomp $DATE;

    my $xymonreport = "status+$STATUSTTL $host.bkp $topcolor $DATE (TTL=$STATUSTTL min)\n";

    my $tt = Template->new(
        START_TAG    => '<%',
        END_TAG      => '%>',
        INCLUDE_PATH => "$prefix/views",
    );
    my $report;
    $tt->process( 'report-xymon.tt', $RecentBackups, \$report )
        or logit( $taskid, $host, $group, "ERROR generating xymon report template: " . $tt->error() );
    $xymonreport .= $report;

    send_xymon_report($xymonreport) unless $serverconfig{dryrun};
    print "Xymon Report: $xymonreport\n" if $serverconfig{dryrun};
    logit( $taskid, $host, $group, "xymon report sent." );

    return 1;
}

sub logit {
    my ( $taskid, $host, $group, $msg ) = @_;
    $host  ||= '*';
    $group ||= '*';
    my $timestamp     = strftime '%b %d %H:%M:%S', localtime;
    my $logmonth      = strftime '%Y-%m',          localtime;
    my $logdate       = strftime $serverconfig{global_log_date}, localtime;
    my $logfolder     = "$serverconfig{path_logs}/${host}_${group}";
    my $globallogfile = "$serverconfig{path_logs}/global_$logmonth.log";
    my $logfile       = "$logfolder/$logdate.log";
    my $logmessage    = "$timestamp $host-$group($taskid) : $msg";
    $logmessage .= "\n" unless ( $logmessage =~ m/\n$/ );

    # write selection of messages to global logfile
    my $selection = qr{
        Queueing \s backup \s for |
        Skipping \s because |
        reorder \s queue |
        sleep |
        NOCACHE \s selected |
        working \s on |
        PID |
        finished \s with |
        Backup \s successful |
        ERROR |
        Wipe \s host |
        Wipe \s existing |
        Wipe \s successful |
        Wipe \s WARNING |
        Delete \s logfile |
        Delete \s btrfs \s subvolume
    }x;

    if ( $serverconfig{verbose} ) {
        if ( $serverconfig{dryrun} ) {
            unless ( $group eq 'GLOBAL' || $host eq 'SERVER' ) {

                # write into daily logfile per host_group
                print "Write to HOST log: $logmessage";
            }
            if ( $logmessage =~ /$selection/ || $group eq 'GLOBAL' || $host eq 'SERVER' ) {
                print "Write to GLOBAL log: $logmessage";
            }
        } else {
            print $logmessage;
        }
    }

    unless ( $serverconfig{dryrun} ) {
        unless ( $group eq 'GLOBAL' || $host eq 'SERVER' ) {

            # write into daily logfile per host_group
            mkdir($logfolder) unless -d $logfolder;
            open my $log, '>>', $logfile or print "ERROR opening logfile $logfile: $!\n";
            print {$log} $logmessage;
            close $log;
        }

        if ( $logmessage =~ /$selection/ || $group eq 'GLOBAL' || $host eq "SERVER" ) {
            open my $log, '>>', $globallogfile or print "ERROR opening logfile $globallogfile: $!\n";
            print {$log} $logmessage;
            close $log;
        }
    }

    if ( $logmessage =~ /warn|error/i ) {
        $hosts{"$host-$group"}{errormsg} .= $logmessage;
    }

    return 1;
}

sub read_log {
    my ( $host, $group, $show_logs_number ) = @_;

    my %parsed_logdata;
    my $logfolder = "$serverconfig{path_logs}/${host}_${group}";
    my @logfiles  = glob("$logfolder/*.log");
    $show_logs_number = $#logfiles + 1 if ( $#logfiles < $show_logs_number );

    foreach my $logfile ( @logfiles[ -$show_logs_number .. -1 ] ) {
        open LOGDATA, '<', $logfile or print "ERROR opening logfile $logfile: $!\n";
        my @logdata = <LOGDATA>;
        close LOGDATA;

        foreach my $logline (@logdata) {
            if ( $logline =~ qr{
                    (?<logdate> \w{3}\s\d{2} ) \s
                    (?<logtime> \d{2}:\d{2}:\d{2} ) \s
                    (?<hostgroup> [^:]* )\s:\s
                    (?<message> .* )
                }x )
            {
                push( @{ $parsed_logdata{$+{logdate}} }, {
                    date      => $+{logdate},
                    time      => $+{logtime},
                    hostgroup => $+{hostgroup},
                    message   => $+{message},
                });
            } else {
                $parsed_logdata{( sort keys %parsed_logdata )[-1]}[-1]->{message} .= "<br />$logline";
            }
        }
    }

    return \%parsed_logdata;
}

sub read_global_log {

    my %parsed_logdata;
    my $logmonth = strftime '%Y-%m', localtime;
    my $globallogfile = "$serverconfig{path_logs}/global_$logmonth.log";

    open LOGDATA, '<', $globallogfile or print "ERROR opening logfile $globallogfile: $!\n";
    my @logdata = <LOGDATA>;
    close LOGDATA;

    foreach my $logline (@logdata) {
        if ( $logline =~ qr{
                (?<logdate> \w{3}\s\d{2} ) \s
                (?<logtime> \d{2}:\d{2}:\d{2} ) \s
                (?<hostgroup> [^:]* )\s:\s
                (?<message> .* )
            }x )
        {
            my $msg       = $+{message};
            my $logdate   = $+{logdate};
            my $logtime   = $+{logtime};
            my $hostgroup = $+{hostgroup};

            if ( $msg =~ /ERR/ ) {
                push( @{ $parsed_logdata{$logdate} }, {
                    date      => $logdate,
                    time      => $logtime,
                    hostgroup => $hostgroup,
                    message   => $msg,
                });
            }
        }
    }

    return \%parsed_logdata;
}

sub delete_logfiles {
    my ( $host, $group, $taskid, @wipedirs ) = @_;
    $taskid ||= 0;

    foreach my $dir (@wipedirs) {
        my ($logdate) = $dir =~ /.*\/(\d{4}\.\d{2}\.\d{2})/;
        $logdate =~ s/\./\-/g;
        my $today = `$serverconfig{path_date} +"%Y-%m-%d"`;
        chomp $today;
        unless ( $logdate eq $today ) {
            my $logfolder = "$serverconfig{path_logs}/${host}_${group}";
            my $logfile   = "$logfolder/$logdate.log";
            my $rmcmd     = 'rm -f';
            $rmcmd = "echo $rmcmd" if $serverconfig{dryrun};

            logit( $taskid, $host, $group, "Delete logfile $logfile" );
            system("$rmcmd $logfile") and logit( $taskid, $host, $group, "ERROR: deleting logfile $logfile: $!" );
        }
    }

    return 1;
}

sub error404 {
    my ($title) = @_;
    $title ||= 'An error occured.';

    Dancer::Continuation::Route::ErrorSent->new(
        return_value => Dancer::Error->new(
            code  => 404,
            title => $title,
        )->render()
    )->throw;
}

1;
