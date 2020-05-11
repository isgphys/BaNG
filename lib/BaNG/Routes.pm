package BaNG::Routes;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::BackupServer;
use BaNG::Wipe;
use BaNG::Reporting;
use BaNG::Routes_Config;
use BaNG::Routes_Docs;
use BaNG::Routes_Host;
use BaNG::Routes_Group;
use BaNG::Routes_Logs;
use BaNG::Routes_Reporting;
use BaNG::Routes_Restore;
use BaNG::Routes_Schedule;
use BaNG::Routes_Statistics;

prefix undef;

get '/' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'dashboard' => {
        section      => "dashboard",
        servername   => $servername,
        servers      => \%servers,
        xymon_server => $serverconfig{xymon_server},
        perf_mon_url => $serverconfig{perf_mon_url},
    };
};

get '/status_cron' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my $diff = status_cron();
    return '' unless $diff;

    template 'status_cron' => {
        section      => "dashboard",
        servername   => $servername,
        servers      => \%servers,
        xymon_server => $serverconfig{xymon_server},
        cron_diff => $diff,
    },{ layout => 0 };
};

get '/fsinfo_report' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'dashboard-fsinfo' => {
        fsinfo       => get_fsinfo(),
        servers      => \%servers,
    },{ layout => 0 };
};

get '/lockfile_report' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'dashboard-running_jobs' => {
        lockfiles    => get_lockfiles(),
    },{ layout => 0 };
};

get '/error_report' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'dashboard-error_report' => {
        RecentBackups24h => bangstat_recentbackups_hours(),
        xymon_server     => $serverconfig{xymon_server},
    },{ layout => 0 };
};

get '/wipe_status' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config('*');

    my %hosts_stack;
    foreach my $hostgroup ( sort keys %hosts ) {
        my $host = $hosts{$hostgroup}{hostname};
        $hosts_stack{$host} = backup_folders_stack($host);
    }

    template 'dashboard-wipe_status' => {
        hosts        => \%hosts,
        servers      => \%servers,
        backupstack  => \%hosts_stack,
        },{ layout => 0 };
};

get '/oob_status' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config('*');
    my $get_oob_snapshots_mode = params->{get_oob_snapshots_mode} || 1;
    my %oobsd = get_oob_snapshot_dirs(\%hosts,$get_oob_snapshots_mode);

    template 'dashboard-oob_status' => {
        hosts        => \%hosts,
        oobsd        => \%oobsd,
        },{ layout => 0 };
};


get '/perf_mon' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'perf-mon' => {
        servername   => $servername,
        perf_mon_url => $serverconfig{perf_mon_url},
    },{
        layout => 0 };
};

get '/login' => sub {
    session 'return_url' => params->{return_url} || '/';

    template 'login' => {};
};

post '/login' => sub {
    my ( $authenticated, $realm ) = authenticate_user( params->{username}, params->{password} );

    if ($authenticated) {
        session logged_in_user_realm => $realm;
        session logged_in_user       => param('username');
        session logged_in_fullname   => logged_in_user()->{'cn'};
        session logged_in_admin      => user_has_role( param('username'), config->{admin_role} ) ? 1 : 0;

        if ( !session('logged_in_admin') && session('return_url') eq '/' ) {
            redirect '/restore';
        } else {
            redirect session('return_url');
        }

    } else {
        debug( 'Login failed - password incorrect for ' . param('username') );
        redirect '/';
    }
};

get '/login/denied' => sub {
    template 'denied' => {};
};

get '/logout' => sub {
    session->destroy;
    return redirect '/';
};

1;
