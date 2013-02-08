package BaNG::Route_Schedule;
use Dancer ':syntax';
use BaNG::Config;

prefix '/schedule';

get '/' => sub {
    get_global_config();
    find_hosts("*");

    template 'schedule-overview', {
        section   => 'schedule',
        hosts     => \%hosts ,
    };
};

