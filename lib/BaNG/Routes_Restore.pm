package BaNG::Routes_Restore;

use Dancer ':syntax';
use BaNG::Config;
use BaNG::Common;

prefix '/restore';

get '/' => sub {
    get_serverconfig();
    get_host_config('*');

    my %hosts_stack;
    foreach my $hostgroup ( sort keys %hosts ) {
        my $host = $hosts{$hostgroup}{hostname};
        $hosts_stack{$host} = backup_folders_stack($host);
    }

    template 'restore' => {
        section      => 'restore',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts,
        backupstack  => \%hosts_stack,
        automount    => get_automount_paths(),
    };
};

1;
