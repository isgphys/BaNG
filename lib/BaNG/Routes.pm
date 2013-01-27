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

get '/statistics/json' => sub {
    return statistics_cumulated_json();
};

get '/statistics/:host/:share/json' => sub {
    my $share = statistics_decode_path(param('share'));
    return statistics_json(param('host'),$share);
};

get '/statistics/:host/:share' => sub {
    my $host  = param('host');
    my $share = param('share');

    template 'statistics', {
        section   => 'statistics',
        host      => $host,
        share     => statistics_decode_path(param('share')),
        json_url  => "/statistics/$host/$share/json",
    },{ layout    => 0
    };
};
