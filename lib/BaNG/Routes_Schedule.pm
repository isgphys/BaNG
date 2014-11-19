package BaNG::Routes_Schedule;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;

prefix '/schedule';

get '/' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config('*');

    template 'schedule', {
        section      => 'schedule',
        servername   => $servername,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts,
        cronjobs     => get_cronjob_config(),
    };
};

1;
