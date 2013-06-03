package BaNG::Routes_Host;

use Dancer ':syntax';
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
        cronjobs      => get_cronjob_config(),
        RecentBackups => \%RecentBackups,
    };
};

1;
