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

    template 'reporting-tasks' => {
        section      => 'reporting',
        servername   => $servername,
        servers      => \%servers,
        RecentTasks  => bangstat_recent_tasks(),
        xymon_server => $serverconfig{xymon_server},
    };
};

get '/task/:taskid' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-task_jobs' => {
        section      => 'reporting',
        servername   => $servername,
        servers      => \%servers,
        taskid       => param('taskid'),
        jobs         => bangstat_task_jobs( param('taskid') ),
        xymon_server => $serverconfig{xymon_server},
    };
};

post '/task/:taskid' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my $taskid = param('taskid');
    my $deletedby  = session('logged_in_user');

    bangstat_task_delete( param('taskid'));
    warning "Task $taskid deleted by $deletedby!";
};

get '/jobs' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-jobs' => {
        section           => 'reporting',
        servername        => $servername,
        servers           => \%servers,
        RecentBackupsLast => bangstat_recentbackups_hours(),
        xymon_server      => $serverconfig{xymon_server},
    };
};

get '/job/:jobid' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-task_jobs' => {
        section      => 'reporting',
        servername   => $servername,
        servers      => \%servers,
        jobid        => param('jobid'),
        jobs         => bangstat_recentbackups_job_details(param('jobid')),
        xymon_server => $serverconfig{xymon_server},
    };
};

get '/lasttransfer' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'reporting-lasttransfer' => {
        section           => 'reporting',
        servername        => $servername,
        servers           => \%servers,
        LastTransferDate  => bangstat_last_transfer(),
        xymon_server      => $serverconfig{xymon_server},
    };
};

1;
