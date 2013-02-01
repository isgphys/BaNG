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
        defaultsconfig => get_default_config(),
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
    find_hosts("*");

    template 'configs-overview' => {
        section  => 'configs-overview',
        hosts    => \%hosts ,
    };
};

get '/host' => sub {

    template 'host-search', {
        section   => 'host',
    };
};


get '/host/:host' => sub {
    get_global_config();
    find_hosts(param('host'));

    template 'host', {
        section   => 'host',
        host      => param('host'),
        hosts     => \%hosts ,
    };
};

get '/host/search' => sub {

    template 'host-search' => {
        section => 'host',
    };
};

post '/host/search' => sub {
    my $host = '';
    if(param('search_text') && param('search_text') =~ /[a-z0-9\-]{1,255}/i)
    {
        $host = param('search_text');
        return redirect sprintf('/host/%s', $host);
    }
    else
    {
        return template 'host' => {
            section => 'host',
            error   => 'Requested host is not available'
        };
    }
};

get '/statistics/json' => sub {
    return statistics_cumulated_json();
};

get '/statistics/:host/:share/json' => sub {
    my $share = statistics_decode_path(param('share'));
    return statistics_json(param('host'),$share);
};

get '/statistics' => sub {
    my %hosts_shares = statistics_hosts_shares();

    template 'statistics', {
        section   => 'statistics',
        title     => 'Cumulated Backup Statistics',
        json_url  => "/statistics/json",
        hosts_shares => \%hosts_shares,
    },{ layout    => 0
    };
};

get '/statistics/:host/:share' => sub {
    my $host     = param('host');
    my $shareurl = param('share');
    my $share    = statistics_decode_path($shareurl);
    my %hosts_shares = statistics_hosts_shares();

    template 'statistics', {
        section   => 'statistics',
        title     => "Statistics for $host:$share",
        host      => $host,
        share     => $share,
        json_url  => "/statistics/$host/$shareurl/json",
        hosts_shares => \%hosts_shares,
    },{ layout    => 0
    };
};
