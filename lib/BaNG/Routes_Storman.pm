package BaNG::Routes_Storman;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::Common;
use BaNG::Hosts;
use BaNG::Iscsi;

prefix '/storman';

get '/' => require_role isg => sub {

    template 'storman-dashboard.tt', {
    };
};

get '/fsinfo_report' => require_role isg => sub {
    get_serverconfig();

    template 'storman-dashboard-fsinfo' => {
        fsinfo => get_fsinfo(),
        servers => \%servers,
        },{
        layout => 0 };
};

get '/iscsi_session_report' => require_role isg => sub {
    get_serverconfig();

    template 'storman-dashboard-iscsi_sessions' => {
        sessioninfo => get_iscsi_sessions(),
        servers => \%servers,
        },{
        layout => 0 };
};


1;
