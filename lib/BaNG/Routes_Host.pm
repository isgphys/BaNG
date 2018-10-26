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

get '/:host/?:lastXdays?' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config( param('host') );
    my %RecentBackups = bangstat_recentbackups( param('host'), param('lastXdays') );
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
        RecentBackups => \%RecentBackups,
        xymon_server  => $serverconfig{xymon_server},
    };
};

1;
