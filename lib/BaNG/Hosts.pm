package BaNG::Hosts;
use Dancer ':syntax';
use 5.010;

use Exporter 'import';
our @EXPORT = qw(
    get_fsinfo
    %fsinfo
);

our %fsinfo;

sub get_fsinfo {
    my $i=0;
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
            'blocks'     => $+{blocks},
            'used'       => $+{used},
            'available'  => $+{available},
            'used_per'   => $+{usedper},
        };
    }

    return 1;
}

1;
