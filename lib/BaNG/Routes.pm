package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Route_Config;
use BaNG::Route_Documentation;
use BaNG::Route_Host;
use BaNG::Route_Restore;
use BaNG::Route_Statistics;
use BaNG::Route_Schedule;
use BaNG::Common;
use BaNG::Hosts;
use BaNG::Config;
use BaNG::Reporting;

prefix undef;

get '/' => sub {
    get_global_config();

    template 'dashboard' => {
             'section' => 'dashboard',
             'remotehost' => request->remote_host,
             'remoteuser' => request->user,
             'webDancerEnv' => config->{run_env},
             'msg' => get_flash(),
             'fsinfo' => get_fsinfo(),
             'lockfiles' => getLockFiles(),
    };
};

get '/bkpreport-overview' => sub {
    get_global_config();

    template 'bkpreport-overview' => {
             'RecentBackupsAll' => bangstat_recentbackups_all(),
    },{ layout => 0
    };
};
