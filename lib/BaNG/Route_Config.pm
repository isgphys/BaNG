package BaNG::Route_Config;
use Dancer ':syntax';
use BaNG::Config;

prefix '/config';

get '/global' => sub {
    get_global_config();

    template 'global-config' => {
        section       => 'global-config',
        globalconfig  => \%globalconfig,
        defaultsconfig => get_default_config(),
        servername    => $servername,
        portnr        => config->{port},
        envi          => config->{environment},
        prefix_path   => $prefix,
        config_path   => $config_path,
        config_global => $config_global,
    };
};

get '/all' => sub {
    get_global_config();
    find_hosts("*");

    template 'configs-overview' => {
        section  => 'configs-overview',
        hosts    => \%hosts ,
    };
};

