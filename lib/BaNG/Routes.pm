package BaNG::Routes;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Auth::Extensible::Provider::LDAPphys;
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

hook 'before' => sub {
    session request_path => request->path_info;
};

get '/' => require_role isg => sub {
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

get '/error_report' => require_role isg => sub {
    get_serverconfig();

    template 'dashboard-error_report' => {
        RecentBackupsAll => bangstat_recentbackups_all(),
    },{ layout => 0 };
};

get '/login' => sub {
    session 'return_url' => params->{return_url} || '/';

    template 'login' => {
    };
};

post '/login' => sub {
    if ( authenticate_user(param('username'), param('password')) ) {
        session logged_in_user       => param('username');
        session logged_in_fullname   => Dancer::Plugin::Auth::Extensible::Provider::LDAPphys::_user_fullname(param('username'));
        session logged_in_roles      => Dancer::Plugin::Auth::Extensible::Provider::LDAPphys::get_user_roles('',param('username'));
        session logged_in_admin      => 'isg' ~~ session('logged_in_roles') || '0';
        session logged_in_user_realm => 'ldap';

        if ( !session('logged_in_admin') && session('return_url') eq '/' ) {
            redirect '/restore';
        } else {
            redirect session('return_url');
        }

    } else {
        debug("Login failed - password incorrect for " . param('username'));
        redirect '/';
    };
};

get '/login/denied' => sub {
    template 'denied' => {
    };
};

get '/logout' => sub {
    session->destroy;
    return redirect '/';
};

1;
