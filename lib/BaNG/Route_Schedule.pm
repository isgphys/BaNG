package BaNG::Route_Schedule;
use Dancer ':syntax';

prefix '/schedule';

get '/' => sub {

    template 'schedule-overview', {
        section   => 'schedule',
    };
};

