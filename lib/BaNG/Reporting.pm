package BaNG::Reporting;

use Dancer ':syntax';
use BaNG::Config;
use Date::Parse;
use YAML::Tiny;
use IO::Socket;
use DBI;

use Exporter 'import';
our @EXPORT = qw(
    $bangstat_dbh
    bangstat_db_connect
    bangstat_recentbackups
    send_hobbit_report
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

sub bangstat_recentbackups {
    my ($host) = @_;

    my $lastXdays    = 5;
    my $BkpStartHour = 18;

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
        SELECT *
        FROM recent_backups
        WHERE Start > date_sub(concat(curdate(),' $BkpStartHour:00:00'), interval $lastXdays day)
        AND BkpFromHost = '$host'
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        ORDER BY Start DESC;
    ");
    $sth->execute();

    my %RecentBackups;
    my %RecentBackupTimes;
    while (my $dbrow=$sth->fetchrow_hashref()) {
        my $BkpGroup = $dbrow->{'BkpGroup'} || 'NA';
        push( @{$RecentBackups{"$host-$BkpGroup"}}, {
            Starttime   => $dbrow->{'Start'},
            Stoptime    => $dbrow->{'Stop'},
            BkpFromPath => $dbrow->{'BkpFromPath'},
            BkpToPath   => $dbrow->{'BkpToPath'},
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

1;
