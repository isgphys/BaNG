package BaNG::Routes_Restore;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use BaNG::Config;
use BaNG::Common;

prefix '/restore';

get '/' => sub {
    template 'restore' => {
        section      => 'restore',
    };
};

get '/restore_content' => sub {
    get_serverconfig();
    get_host_config('*');

    my %hosts_stack;
    foreach my $hostgroup ( sort keys %hosts ) {
        my $host = $hosts{$hostgroup}{hostname};
        $hosts_stack{$host} = backup_folders_stack($host);
    }

    template 'restore-content' => {
        section      => 'restore',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts,
        backupstack  => \%hosts_stack,
        automount    => get_automount_paths(),
        },{ layout => 0 };
    };

1;
