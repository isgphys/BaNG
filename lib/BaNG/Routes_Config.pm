package BaNG::Routes_Config;

use Dancer ':syntax';
use BaNG::Config;

prefix '/config';

get '/global' => sub {
    get_global_config();

    template 'global-config' => {
        section        => 'configs',
        remotehost     => request->remote_host,
        webDancerEnv   => config->{run_env},
        serverconfig   => \%serverconfig,
        defaultsconfig => get_default_config(),
        servername     => $servername,
        prefix_path    => $prefix,
        config_path    => $config_path,
    };
};

get '/allhosts' => sub {
    redirect '/config/allhosts/';
};

get '/allhosts/:filter?' => sub {
    get_global_config();
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
    get_global_config();
    get_group_config("*");

    template 'group-configs-overview' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

1;
