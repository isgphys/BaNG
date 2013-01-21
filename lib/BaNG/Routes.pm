package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Hosts;
use BaNG::Common;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

get '/hosts/enabled' => sub {

     my @hosts = find_enabled_hosts("*_*.yaml", "$config_path/enabled" );

     template 'hostslist' => {
                  section => 'hostlist',
                    hosts => \@hosts
     };
};
