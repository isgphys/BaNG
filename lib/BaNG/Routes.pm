package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Config;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

get '/hosts/enabled' => sub {
    get_global_config();
    find_enabled_hosts();

    template 'hostslist' => {
        section => 'hostlist',
        hosts => \%hosts
    };
};
