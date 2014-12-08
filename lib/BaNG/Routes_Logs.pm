package BaNG::Routes_Logs;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Common;
use BaNG::Config;
use BaNG::Reporting;

prefix '/logs';

get '/global' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'logs-global', {
        section      => 'logs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        logdata      => read_global_log(),
    };
};

get '/:host/:group/?:showlogsnumber?' => require_role config->{admin_role} => sub {
    get_serverconfig();

    my $show_logs_number = param('showlogsnumber') || $serverconfig{show_logs_number};

    template 'logs-host', {
        section      => 'logs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        host         => param('host'),
        group        => param('group'),
        logdata      => read_log(param('host'), param('group'), $show_logs_number),
    };
};

1;
