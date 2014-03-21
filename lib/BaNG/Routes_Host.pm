package BaNG::Routes_Host;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Common;
use BaNG::Config;
use BaNG::Reporting;

prefix '/host';

get '/:host' => require_role isg => sub {
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

1;
