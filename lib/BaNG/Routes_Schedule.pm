package BaNG::Routes_Schedule;

use Dancer ':syntax';
use BaNG::Config;

prefix '/schedule';

get '/' => sub {
    get_serverconfig();
    get_host_config('*');

    template 'schedule', {
        section      => 'schedule',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts,
        cronjobs     => get_cronjob_config(),
    };
};

1;
