package BaNG::Routes_Restore;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::Common;

prefix '/restore';

get '/?:hostname?' => require_login sub {

    my $showhost = param('hostname') || '*';

    template 'restore' => {
        section    => 'restore',
        servername => $servername,
        showhost   => $showhost,
        servers    => \%servers,
    };
};

get '/restore_content/:showhost' => require_login sub {
    get_serverconfig();
    get_host_config(param('showhost'));

    my %hosts_stack;
    foreach my $hostgroup ( sort keys %hosts ) {
        my $host = $hosts{$hostgroup}{hostname};
        $hosts_stack{$host} = backup_folders_stack($host);
    }

    template 'restore-content' => {
        section      => 'restore',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        servername   => $servername,
        hosts        => \%hosts,
        backupstack  => \%hosts_stack,
        automount    => get_automount_paths(),
        },{ layout => 0 };
    };

1;
