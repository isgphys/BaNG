package BaNG::Common;

use POSIX qw(floor);

use Exporter 'import';
our @EXPORT = qw(
    num2human
    time2human
);

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
