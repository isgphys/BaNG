package BaNG::Route_Config;
use Dancer ':syntax';
use BaNG::Config;

prefix '/config';

get '/global' => sub {
    get_global_config();

    template 'global-config' => {
        section        => 'global-config',
        remotehost     => request->remote_host,
        globalconfig   => \%globalconfig,
        defaultsconfig => get_default_config(),
        servername     => $servername,
        prefix_path    => $prefix,
        config_path    => $config_path,
        config_global  => $config_global,
    };
};

get '/all' => sub {
    get_global_config();
    get_host_config("*");

    template 'configs-overview' => {
        section    => 'configs-overview',
        remotehost => request->remote_host,
        hosts      => \%hosts ,
    };
};

