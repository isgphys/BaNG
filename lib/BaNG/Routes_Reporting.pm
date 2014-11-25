package BaNG::Routes_Reporting;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::Reporting;

prefix '/reporting';

get '/' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-bkpreport' => {
        section           => 'reporting',
        servername        => $servername,
        RecentBackupsLast => bangstat_recentbackups_last(),
        xymon_server      => $serverconfig{xymon_server},
    };
};

get '/task/:taskid' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-task_jobs' => {
        section      => 'reporting',
        servername   => $servername,
        taskid       => param('taskid'),
        taskjobs     => bangstat_task_jobs( param('taskid') ),
        xymon_server => $serverconfig{xymon_server},
    };
};

1;
