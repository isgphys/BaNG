package BaNG::Routes;

use Dancer ':syntax';
use BaNG::Common;
use BaNG::Config;
use BaNG::Hosts;
use BaNG::Reporting;
use BaNG::Routes_Config;
use BaNG::Routes_Docs;
use BaNG::Routes_Host;
use BaNG::Routes_Reporting;
use BaNG::Routes_Restore;
use BaNG::Routes_Schedule;
use BaNG::Routes_Statistics;

prefix undef;

get '/' => sub {
    get_serverconfig();

    template 'dashboard' => {
        section      => 'dashboard',
        remotehost   => request->remote_host,
        remoteuser   => request->user,
        webDancerEnv => config->{run_env},
        fsinfo       => get_fsinfo(),
        lockfiles    => get_LockFiles(),
    };
};

get '/error_report' => sub {
    get_serverconfig();

    template 'dashboard-error_report' => {
        RecentBackupsAll => bangstat_recentbackups_all(),
    },{ layout => 0 };
};

1;
