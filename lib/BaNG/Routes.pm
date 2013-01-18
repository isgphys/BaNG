package BaNG::Routes;
use Dancer ':syntax';

get '/' => sub {
    template 'main.tt', {
    };
};
