package BaNG::Routes_Config;

use 5.010;
use strict;
use warnings;
use POSIX qw( strftime );
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;

prefix '/config';

get '/defaults' => require_role isg => sub {
    get_serverconfig();

    template 'configs-defaults' => {
        section        => 'configs',
        remotehost     => request->remote_host,
        webDancerEnv   => config->{run_env},
        serverconfig   => \%serverconfig,
        hostdefaults   => get_host_config_defaults(),
        servername     => $servername,
        prefix_path    => $prefix,
    };
};

get '/allhosts' => require_role isg => sub {
    redirect '/config/allhosts/';
};

get '/allhosts/:filter?' => require_role isg => sub {
    get_serverconfig();
    get_host_config("*");

    template 'configs-hosts' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        filtervalue  => param('filter'),
        hosts        => \%hosts,
    };
};

get '/allgroups' => require_role isg => sub {
    get_serverconfig();
    get_group_config("*");

    template 'configs-groups' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

get '/allservers' => require_role isg => sub {
    get_serverconfig();

    template 'configs-servers' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        servers      => \%servers,
    };
};

get '/new/?:errmsg?' => require_role isg => sub {
    get_serverconfig();
    get_group_config("*");

    my $errmsg = param('errmsg') ? "You try to create a still existing configfile!" : "";

    template 'configs-create' => {
        section      => 'configs',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
        errmsg       => $errmsg,
    };
};

post '/new' => require_role isg => sub {
    my $hostname  = param('hostname');
    my $bkpgroup  = param('newgroup') ? param('newgroup') : param('bkpgroup');
    my $createdby = session('logged_in_user');
    my $timestamp = strftime("%Y/%m/%d %H:%M:%S", localtime);

    my $settings;
    $settings->{'COMMENT'} = "Created by $createdby at $timestamp";

    my ($return_code, $return_msg) = write_host_config("$hostname", "$bkpgroup", $settings);

    if ( $return_code ) {
        info "Configfile $return_msg created by $createdby";
        redirect "/host/$hostname";
     } else {
        warning "You tried to override $return_msg!";
        redirect "/config/new/-1";
     }

};

post '/delete/:file' => require_role isg => sub {
    my $file  = param('file');
    my $deletedby = session('logged_in_user');

    delete_host_config("$file");
    warning "Configfile $file deleted by $deletedby!";

    redirect '/config/allhosts';
};

1;
