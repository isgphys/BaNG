package BaNG::Route_Statistics;
use Dancer ':syntax';
use BaNG::Statistics;

prefix '/statistics';

get '/' => sub {
    my %hosts_shares = statistics_hosts_shares();

    template 'statistics', {
        section   => 'statistics',
        title     => 'Cumulated Backup Statistics',
        json_url  => "/statistics/json",
        hosts_shares => \%hosts_shares,
    },{ layout    => 0
    };
};

get '/json' => sub {
    return statistics_cumulated_json();
};

get '/:host/:share/json' => sub {
    my $share = statistics_decode_path(param('share'));
    return statistics_json(param('host'),$share);
};

get '/:host/:share' => sub {
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

get '/variations' => sub {
    my %largest_variations = statistics_groupshare_variations();

    template 'largest_variations', {
        section => 'statistics',
        largest_variations => \%largest_variations,
    };
};

get '/schedule.json' => sub {
    my %schedule = statistics_schedule(1,'time');
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule-all.json' => sub {
    my %schedule = statistics_schedule(60,'host');
    my %json_options = ( canonical => 1 );
    return to_json(\%schedule, \%json_options);
};

get '/schedule' => sub {
    template 'statistics-schedule', {
        section   => 'statistics',
        title     => "Backup schedule of last night",
        fullplot  => 0,
        json_url  => "/statistics/schedule.json",
    },{ layout    => 0
    };
};

get '/schedule-all' => sub {
    template 'statistics-schedule', {
        section   => 'statistics',
        title     => "Backup schedule by host",
        fullplot  => 1,
        json_url  => "/statistics/schedule-all.json",
    },{ layout    => 0
    };
};
