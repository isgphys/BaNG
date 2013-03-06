package BaNG::Reporting;

use Dancer ':syntax';
use POSIX qw(strftime);
use BaNG::Config;
use YAML::Tiny;
use DBI;

use Exporter 'import';
our @EXPORT = qw(
    logit
    $bangstat_dbh
    bangstat_db_connect
);

our %globalconfig;
our $bangstat_dbh;

sub logit {
    my ($hostname, $folder, $msg) = @_;

    my $timestamp = strftime "%b %d %H:%M:%S", localtime;

    open  LOG,">>$globalconfig{'global_log_file'}" or die "$globalconfig{'global_log_file'}: $!";
#    open  LOG,">>BaNG::Config::$globalconfig{global_log_file}" or die ;
#    print LOG "$timestamp $hostname $folder - $msg\n";
    close LOG;
}

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

1;

