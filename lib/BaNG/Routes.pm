package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Config;
use BaNG::Statistics;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

get '/config/global' => sub {
    get_global_config();

    template 'global-config' => {
        section       => 'global-config',
        globalconfig  => \%globalconfig,
        servername    => $servername,
        portnr        => config->{port},
        envi          => config->{environment},
        prefix_path   => $prefix,
        config_path   => $config_path,
        config_global => $config_global,

    };
};

get '/config/all' => sub {
    get_global_config();
    find_hosts();

    template 'configs-overview' => {
        section  => 'configs-overview',
        hosts    => \%hosts ,
    };
};

get '/statistics' => sub {
    template 'statistics-overview', {
        section   => 'statistics',
    };
};

get '/statistics/:host/:share/json' => sub {
    my %json = statistics_json(param('host'),param('share'));

    set serializer => 'JSON';
    return \%json;
};

get '/statistics/:host/:share' => sub {
    template 'statistics', {
        section   => 'statistics',
        plothost  => param('host'),
        plotshare => param('share'),
    },{ layout    => 0
    };
};
