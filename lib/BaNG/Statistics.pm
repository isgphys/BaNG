package BaNG::Statistics;
use Dancer ':syntax';
use BaNG::Reporting;

use Exporter 'import';
our @EXPORT = qw(
    statistics_json
);

sub statistics_json {
    my ($host, $share) = @_;

    bangstat_db_connect();

    my %statistics = (
        host    => $host,
        share   => $share,
    );

    return %statistics;
}

1;
