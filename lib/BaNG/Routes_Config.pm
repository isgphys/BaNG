package BaNG::Routes_Config;

use Dancer ':syntax';
use BaNG::Config;

prefix '/config';

get '/global' => sub {
    get_serverconfig();

    template 'global-config' => {
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

    template 'host-configs-overview' => {
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

    template 'group-configs-overview' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

1;
