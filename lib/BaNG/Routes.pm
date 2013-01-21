package BaNG::Routes;
use Dancer ':syntax';

get '/' => sub {
     template 'index' => {
                 section => 'dashboard'
     };
};
