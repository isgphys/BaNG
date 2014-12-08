package BaNG::Routes_Group;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use BaNG::Config;

prefix '/group';

get '/:group' => require_role config->{admin_role} => sub {
    get_serverconfig();
    get_group_config( param('group') );

    template 'group', {
        section      => 'group',
        servername   => $servername,
        servers      => \%servers,
        webDancerEnv => config->{run_env},
        group        => param('group'),
        groups       => \%groups,
    };
};

1;
