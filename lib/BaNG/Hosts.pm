package BaNG::Hosts;
use Dancer ':syntax';
use 5.010;
use BaNG::Common;

use Exporter 'import';
our @EXPORT = qw(
    get_fsinfo
    %fsinfo
);

our %fsinfo;

sub get_fsinfo {
    my $df;
    my @mounts;

    open(MP, "df -T | grep backup |");
        @mounts = <MP>;
    close(MP);

    foreach my $mount (@mounts){
        #/^([\/\w\d-]+)\s+([\w\d]+)\s+([\d]+)\s+([\d]+)\s+([\d]+)\s+([\d]+).\s+([\/\w\d-]+)$/;
        $mount =~ qr/
                    ^(?<filesystem> [\/\w\d-]+)
                    \s+(?<fstyp> [\w\d]+)
                    \s+(?<blocks> [\d]+)
                    \s+(?<used> [\d]+)
                    \s+(?<available>[\d]+)
                    \s+(?<usedper> [\d]+)
                    .\s+(?<mountpt> [\/\w\d-]+)$
        /x ;

        $fsinfo{$+{mountpt}} = {
            'filesystem' => $+{filesystem},
            'mount'      => $+{mountpt},
            'fstyp'      => $+{fstyp},
            'blocks'     => num2human($+{blocks}),
            'used'       => num2human($+{used}*1024,1024),
            'available'  => num2human($+{available}*1024,1024),
            'used_per'   => $+{usedper},
            'css_class'  => check_fill_level($+{usedper}),
        };
    }

    return 1;
}

sub check_fill_level {
    my ($level) = @_ ;
    my $css_class = '';

    if ( $level > 98 ){
        $css_class = "alert_red";
    } elsif ($level > 90) {
        $css_class = "alert_orange";
    } elsif ($level > 80) {
        $css_class = "alert_yellow";
    }

    return $css_class;
}

1;
