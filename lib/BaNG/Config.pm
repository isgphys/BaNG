package BaNG::Config;

use Dancer ':syntax';

use Exporter 'import';
our @EXPORT = qw(
    $prefix
    $config_path
    $config_global
);

our $prefix          = dirname($0);
our $config_path     = "$prefix/etc";
our $config_global   = "$config_path/bang_globals.yaml";


1;
