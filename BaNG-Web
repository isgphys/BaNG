#!/usr/bin/env perl
use Cwd qw( abs_path );
use Dancer;
use BaNG::Routes;

my $prefix = dirname( abs_path($0) );

if ( -e "$prefix/config.yml" ) {
    Dancer->dance;
} else {
    print "Error config.yml missing!\n";
}
