#!/usr/bin/env perl
use lib '/opt/BaNG/lib';
use Dancer;

use BaNG::Routes;

if ( -e "config.yml" ) {
    Dancer->dance;
} else {
    print "Error config.yml missing!\n";
}
