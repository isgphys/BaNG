package BaNG::Routes_Host;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::BackupServer;
use BaNG::Wipe;
use BaNG::Reporting;

prefix '/host';

get '/:host' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config( param('host') );
    my ( $conn_status, $conn_msg ) = check_client_connection( param('host'), '' );

    template 'host', {
        section       => 'host',
        servername    => $servername,
        servers       => \%servers,
        remotehost    => request->remote_host,
        webDancerEnv  => config->{run_env},
        host          => param('host'),
        conn_status   => $conn_status,
        conn_msg      => $conn_msg,
        hosts         => \%hosts,
        backupstack   => backup_folders_stack( param('host') ),
        cronjobs      => get_cronjob_config(),
        xymon_server  => $serverconfig{xymon_server},
    };
};

get '/:host/bkpreport/?:lastXdays?' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my %RecentBackups = bangstat_recentbackups( param('host'), param('lastXdays') );

    template 'host-bkpreport', {
        section       => 'host',
        RecentBackups => \%RecentBackups,
    },{ layout => 0 };
};

1;
