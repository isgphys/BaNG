package BaNG::Reporting;

use Dancer ':syntax';
use BaNG::Config;
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

    bangstat_db_connect($globalconfig{config_bangstat});
    my $sth = $BaNG::Reporting::bangstat_dbh->prepare("
        SELECT *
        FROM recent_backups
        WHERE Start > date_sub(now(), interval 5 day)
        AND BkpFromHost = '$host'
        AND BkpToHost LIKE 'phd-bkp-gw\%'
        ORDER BY Start DESC;
    ");
    $sth->execute();

    my %RecentBackups;
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
    }
    $sth->finish();

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
