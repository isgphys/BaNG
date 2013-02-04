package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Route_Config;
use BaNG::Route_Host;
use BaNG::Route_Schedule;
use BaNG::Route_Statistics;

prefix undef;

get '/' => sub {
     template 'index' => {
              section => 'dashboard'
     };
};

