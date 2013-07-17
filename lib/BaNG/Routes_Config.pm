package BaNG::Routes_Config;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use BaNG::Config;

prefix '/config';

get '/defaults' => sub {
    get_serverconfig();

    template 'configs-defaults' => {
        section        => 'configs',
        remotehost     => request->remote_host,
        webDancerEnv   => config->{run_env},
        serverconfig   => \%serverconfig,
        servername     => $servername,
        prefix_path    => $prefix,
    };
};

get '/allhosts' => sub {
    redirect '/config/allhosts/';
};

get '/allhosts/:filter?' => sub {
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

get '/allgroups' => sub {
    get_serverconfig();
    get_group_config("*");

    template 'configs-groups' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

get '/allservers' => sub {
    get_serverconfig();

    template 'configs-servers' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        servers      => \%servers,
    };
};

1;
