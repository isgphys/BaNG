package BaNG::Reporting;

use Dancer ':syntax';
use POSIX qw(strftime);
use BaNG::Config;

use Exporter 'import';
our @EXPORT = qw(
    logit
);

our %globalconfig;

sub logit {
    my ($hostname, $folder, $msg) = @_;

    my $timestamp = strftime "%b %d %H:%M:%S", localtime;

    open  LOG,">>$globalconfig{global_log_file}" or die "$globalconfig{global_log_file}: $!";
#    open  LOG,">>BaNG::Config::$globalconfig{global_log_file}" or die ;
#    print LOG "$timestamp $hostname $folder - $msg\n";
    close LOG;
}

1;

