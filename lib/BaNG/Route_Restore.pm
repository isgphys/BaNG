package BaNG::Route_Restore;
use Dancer ':syntax';
use BaNG::Config;

prefix '/restore';

get '/' => sub {
    get_global_config();
    get_host_config('*');

    template 'restore' => {
        section      => 'restore',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        hosts        => \%hosts,
    };
};

1;
