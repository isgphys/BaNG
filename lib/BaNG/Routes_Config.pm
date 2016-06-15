package BaNG::Routes_Config;

use 5.010;
use strict;
use warnings;
use POSIX qw( strftime );
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;
use BaNG::BackupServer;

prefix '/config';

get '/defaults' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'configs-defaults' => {
        section        => 'configs',
        servername     => $servername,
        servers        => \%servers,
        remotehost     => request->remote_host,
        webDancerEnv   => config->{run_env},
        serverconfig   => \%serverconfig,
        serverdefaults => get_server_config_defaults(),
        hostdefaults   => get_host_config_defaults(),
        servername     => $servername,
        prefix_path    => $prefix,
    };
};

get '/allhosts' => require_role config->{admin_role} => sub {
    redirect '/config/allhosts/';
};

get '/allhosts/:filter?' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config('*');

    template 'configs-hosts' => {
        section      => 'configs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        filtervalue  => param('filter'),
        hosts        => \%hosts,
    };
};

get '/allgroups' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_host_config('*');
    get_group_config('*');

    template 'configs-groups' => {
        section      => 'configs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
    };
};

get '/allservers' => require_role config->{admin_role} => sub {
    get_serverconfig();

    template 'configs-servers' => {
        section      => 'configs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        servers      => \%servers,
    };
};

get '/new/:configtype/?:errmsg?' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_group_config('*');
    my $configtype = param('configtype');
    my $errmsg     = '';

    if ( param('errmsg') ) {
        $errmsg = 'You try to create a still existing configfile!' if ( param('errmsg') eq '-3' );
        $errmsg = 'No hostname defined!' if ( param('errmsg') eq '-2' );
    }

    template 'configs-create' => {
        section      => 'configs',
        servername   => $servername,
        servers      => \%servers,
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        groups       => \%groups,
        configtype   => $configtype,
        errmsg       => $errmsg,
    };
};

post '/new/:configtype' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my $hostname   = param('hostname') || '';
    my $bkpgroup   = param('newgroup') ? param('newgroup') : param('bkpgroup');
    my $configtype = param('configtype');
    my $createdby  = session('logged_in_user');
    my $timestamp  = strftime( '%Y/%m/%d %H:%M:%S', localtime );

    my $settings;
    $settings->{'COMMENT'} = "Created by $createdby at $timestamp";

    my ( $return_code, $return_msg ) = write_config( $configtype, 'add', $hostname, $bkpgroup, $settings );

    if ( $return_code eq '1' ) {
        info "Configfile $return_msg created by $createdby";
        if ( $configtype eq 'host' ) {
            get_host_config( $hostname, $bkpgroup );
            check_target_exists( $hostname, $bkpgroup, 0, 1 );
            redirect "/host/$hostname";
        } elsif ( $configtype eq 'group' ) {
            redirect '/config/allgroups';
        }
    } else {
        warning "$return_msg";
        redirect "/config/new/$configtype/-$return_code";
    }

};

post '/modify/:configtype' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my $configtype = param('configtype');
    my $host_arg   = param('host_arg') || '';
    my $group_arg  = param('group_arg');
    my $key_arg    = param('key_arg');
    my $val_arg    = param('val_arg');
    my $updatedby  = session('logged_in_user');

    my ( $return_code, $return_msg ) = update_config( $configtype, $host_arg, $group_arg, $key_arg, $val_arg );
    warning "$return_msg updated by $updatedby!";
};

post '/delete/:configtype/:file' => require_role config->{admin_role} => sub {
    get_serverconfig();
    my $configtype = param('configtype');
    my $file       = param('file');
    my $deletedby  = session('logged_in_user');

    my ( $return_code, $return_msg ) = delete_config( $configtype, $file );
    warning "$return_msg by $deletedby!";
};

1;
