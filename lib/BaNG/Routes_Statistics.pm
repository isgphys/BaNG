package BaNG::Routes_Statistics;

use Dancer ':syntax';
use BaNG::Reporting;
use BaNG::Statistics;

prefix '/statistics';

get '/' => sub {
    redirect '/statistics/phd-bkp-gw';
};

get '/schedule.json' => sub {
    my %schedule = statistics_schedule(1,'time');
    error404('Could not fetch data') unless %schedule;
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule-all.json' => sub {
    my %schedule = statistics_schedule(60,'host');
    error404('Could not fetch data') unless %schedule;
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule' => sub {
    template 'statistics-schedule', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Backup schedule of last night",
        fullplot     => 0,
        json_url     => "/statistics/schedule.json",
    },{ layout       => 0 };
};

get '/schedule-all' => sub {
    template 'statistics-schedule', {
        section      => 'statistics',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        title        => "Backup schedule by host",
        fullplot     => 1,
        json_url     => "/statistics/schedule-all.json",
    },{ layout       => 0 };
};

get '/variations' => sub {
    template 'statistics-variations', {
        section            => 'statistics',
        remotehost         => request->remote_host,
        webDancerEnv       => config->{run_env},
        largest_variations => statistics_groupshare_variations(),
    };
};

get '/:bkpserver.json' => sub {
    my $json = statistics_cumulated_json(param('bkpserver'));
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/:host/:share.json' => sub {
    my $share = statistics_decode_path(param('share'));
    my $json  = statistics_json(param('host'),$share);
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/:bkpserver' => sub {
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

get '/:host/:share' => sub {
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
