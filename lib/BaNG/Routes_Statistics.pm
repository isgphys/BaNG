package BaNG::Routes_Statistics;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Reporting;
use BaNG::Statistics;

prefix '/statistics';

get '/' => require_login sub {
    redirect '/statistics/phd-bkp-gw';
};

get '/schedule.json' => require_login sub {
    my %schedule = statistics_schedule(1,'time');
    error404('Could not fetch data') unless %schedule;
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule-all.json' => require_login sub {
    my %schedule = statistics_schedule(60,'host');
    error404('Could not fetch data') unless %schedule;
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule' => require_login sub {
    template 'statistics-schedule', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Backup schedule of last night",
        fullplot     => 0,
        json_url     => "/statistics/schedule.json",
    },{ layout       => 0 };
};

get '/schedule-all' => require_login sub {
    template 'statistics-schedule', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Backup schedule by host",
        fullplot     => 1,
        json_url     => "/statistics/schedule-all.json",
    },{ layout       => 0 };
};

get '/variations' => require_login sub {
    template 'statistics-variations', {
        section            => 'statistics',
        remotehost         => request->remote_host,
        webDancerEnv       => config->{run_env},
        largest_variations => statistics_groupshare_variations(),
    };
};

get '/barchart/:name.json' => require_login sub {
    my $chartname = param('name');
    my $json = qq% [ {"name": "bar1", "value": "20", "url": "/"}, {"name": "bar2", "value": "15", "url": "/"} ] %;
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/barchart/:name' => require_login sub {
    template 'statistics-barchart', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        chartname    => param('name'),
        sorted       => 0,
    },{ layout       => 0 };
};

get '/:bkpserver.json' => require_login sub {
    my $json = statistics_cumulated_json(param('bkpserver'));
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/:host/:share.json' => require_login sub {
    my $share = statistics_decode_path(param('share'));
    my $json  = statistics_json(param('host'),$share);
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/:bkpserver' => require_login sub {
    my $bkpserver = param('bkpserver');

    template 'statistics', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Cumulated Backup Statistics of $bkpserver",
        json_url     => "/statistics/$bkpserver.json",
        hosts_shares => statistics_hosts_shares($bkpserver),
    },{ layout       => 0 };
};

get '/:host/:share' => require_login sub {
    my $host     = param('host');
    my $shareurl = param('share');
    my $share    = statistics_decode_path($shareurl);

    template 'statistics', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Statistics for $host:$share",
        host         => $host,
        share        => $share,
        json_url     => "/statistics/$host/$shareurl.json",
        hosts_shares => statistics_hosts_shares(),
    },{ layout       => 0 };
};

1;
