package BaNG::Routes_Statistics;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::Reporting;
use BaNG::Statistics;

prefix '/statistics';

get '/' => require_login sub {
    redirect "/statistics/$servername";
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
        servername   => $servername,
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
        servername   => $servername,
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
        servername         => $servername,
        remotehost         => request->remote_host,
        webDancerEnv       => config->{run_env},
        largest_variations => statistics_groupshare_variations(),
    };
};

get '/diffpreday/:host/:group' => require_login sub {
    my $host    = param('host');
    my $group   = param('group');
    my $predays = "14";
    template 'statistics-diffpreday', {
        section      => 'statistics',
        servername   => $servername,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        predays      => $predays,
        diffPreDay   => statistics_diffpreday("$host","$group",$predays),
    };
};

get '/barchart/:name/:taskid.json' => require_login sub {
    my $chartname = param('name');
    my $json;
    if ( $chartname eq 'toptranssize'  ) {
        if( param('taskid') eq 'all' ) {
            $json = to_json(statistics_top_trans('size'));
        } else {
            $json = to_json(statistics_top_trans_details('size', param('taskid')));
        }
    } elsif ( $chartname eq 'toptransfiles'  ) {
        if( param('taskid') eq 'all' ) {
            $json = to_json(statistics_top_trans('files'));
        } else {
            $json = to_json(statistics_top_trans_details('files', param('taskid')));
        }
    } elsif ( $chartname eq 'worktime'  ) {
        if( param('taskid') eq 'all' ) {
            $json = to_json(statistics_work_duration());
        } else {
            $json = to_json(statistics_work_duration_details(param('taskid')));
        }
    }
    error404('Could not fetch data') unless $json;
    return $json;
};

get '/barchart/:name/:taskid' => require_login sub {
    my $chartname = param('name') . '/' . param('taskid');
    my $title = "Bar Chart";
    if ( $chartname =~ /toptranssize/  ) {
       $title = "Top Transfered Filesize - last 24h";
    }elsif ( $chartname =~ /toptransfiles/  ) {
       $title = "Top Transfered Number of Files - last 24h";
    }elsif ( $chartname =~ /worktime/  ) {
       $title = "Duration of Tasks - last 24h";
    }
    template 'statistics-barchart', {
        section      => 'statistics',
        servername   => $servername,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        chartname    => $chartname,
        title        => $title,
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
        servername   => $servername,
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
        servername   => $servername,
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
