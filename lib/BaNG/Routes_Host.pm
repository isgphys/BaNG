package BaNG::Routes_Host;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use BaNG::Common;
use BaNG::Config;
use BaNG::Reporting;

prefix '/host';

get '/:host' => sub {
    get_serverconfig();
    get_host_config(param('host'));
    my %RecentBackups = bangstat_recentbackups( param('host') );

    template 'host', {
        section       => 'host',
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        host          => param('host'),
        hosts         => \%hosts,
        backupstack   => backup_folders_stack(param('host')),
        cronjobs      => get_cronjob_config(),
        RecentBackups => \%RecentBackups,
    };
};

get '/:host/log/:group/?:showlogsnumber?' => sub {
    get_serverconfig();

    my $show_logs_number = param('showlogsnumber') || $serverconfig{show_logs_number};

    template 'host-log', {
        section       => 'host',
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        host          => param('host'),
        group         => param('group'),
        logdata       => read_log(param('host'), param('group'), $show_logs_number),
    };
};

1;
