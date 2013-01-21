package BaNG::Config;

use Dancer ':syntax';
use BaNG::Reporting;
use POSIX qw(strftime);
use YAML::Tiny qw(LoadFile Dump);

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    get_global_config
);

our %globalconfig;

sub get_global_config {

    my $prefix           = dirname($0);
    my $config_path      = "$prefix/etc";
    my $config_global    = "$config_path/bang_globals.yaml";

    sanityfilecheck($config_global);

    my $global_settings  = LoadFile($config_global);

    $globalconfig{log_path}            = "$prefix/$global_settings->{LogFolder}";
    $globalconfig{global_log_date}     =  strftime "$global_settings->{GlobalLogDate}", localtime;
    $globalconfig{global_log_file}     = "$globalconfig{log_path}/$globalconfig{global_log_date}.log";

    $globalconfig{path_available}      = "$config_path/$global_settings->{AvailableFolder}";
    $globalconfig{path_enabled}        = "$config_path/$global_settings->{EnabledFolder}";
    $globalconfig{path_special}        = "$config_path/$global_settings->{SpecialFolder}";

    $globalconfig{rsync}               = "$global_settings->{RSYNC}";
    $globalconfig{btrfs}               = "$global_settings->{BTRFS}";

    $globalconfig{config_default}      = "$config_path/$global_settings->{DefaultConfig}";
    $globalconfig{config_default_nis}  = "$config_path/$global_settings->{DefaultNisConfig}";
}

sub sanityfilecheck {
    my ($file) = @_;

    if ( ! -f "$file" ){
        logit("localhost","INTERNAL", "$file NOT available");
        return 0; #Need exit 0 for CLI
    }
    else {
        return 1;
    }
}

1;
