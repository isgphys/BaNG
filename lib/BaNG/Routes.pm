package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Hosts;
use BaNG::Config;
use BaNG::Reporting;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

get '/hosts/enabled' => sub {
    get_global_config();
    my @hosts = find_enabled_hosts("*_*.yaml", "$globalconfig{path_enabled}" );

    template 'hostslist' => {
        section => 'hostlist',
        hosts => \@hosts
    };
};
