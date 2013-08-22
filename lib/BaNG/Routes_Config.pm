package BaNG::Routes_Config;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;

prefix '/config';

get '/defaults' => require_role isg => sub {
    get_serverconfig();

    template 'configs-defaults' => {
        section        => 'configs',
        remotehost     => request->remote_host,
        webDancerEnv   => config->{run_env},
        serverconfig   => \%serverconfig,
        hostdefaults   => get_host_config_defaults(),
        servername     => $servername,
        prefix_path    => $prefix,
    };
};

get '/allhosts' => require_role isg => sub {
    redirect '/config/allhosts/';
};

get '/allhosts/:filter?' => require_role isg => sub {
    get_serverconfig();
    get_host_config("*");

    template 'configs-hosts' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        filtervalue  => param('filter'),
        hosts        => \%hosts,
    };
};

get '/allgroups' => require_role isg => sub {
    get_serverconfig();
    get_group_config("*");

    template 'configs-groups' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

get '/allservers' => require_role isg => sub {
    get_serverconfig();

    template 'configs-servers' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        servers      => \%servers,
    };
};

1;
