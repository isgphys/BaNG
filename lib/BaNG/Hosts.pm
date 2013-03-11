package BaNG::Hosts;
use Dancer ':syntax';
use 5.010;
use BaNG::Common;
use Net::Ping;

use Exporter 'import';
our @EXPORT = qw(
    get_fsinfo
    chkClientConn
);


sub get_fsinfo {
    my $df;
    my @mounts;
    my %fsinfo;

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

    return \%fsinfo;
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

sub chkClientConn {
    my ($host, $gwhost) = @_;

    my $state = 0;
    my $msg   = "Host offline";
    my $p     = Net::Ping->new("tcp",2);

    if ($p->ping("$host.ethz.ch")){
        $state = 1;
        $msg   = "Host online";
    }
    elsif($gwhost){
        $state = 1;
        $msg   = "Host not pingable because behind a Gateway-Host";
    }
    $p->close();

    return $state, $msg;
}

1;
