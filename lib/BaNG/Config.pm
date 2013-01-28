package BaNG::Config;

use Dancer ':syntax';
use BaNG::Reporting;
use POSIX qw(strftime);
use File::Find::Rule;
use YAML::Tiny qw(LoadFile Dump);

use Cwd qw(getcwd abs_path);
use Sys::Hostname;

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    %hosts
    $prefix
    $config_path
    $config_global
    $servername
    get_global_config
    find_hosts
    find_available_hosts
    find_enabled_hosts
    read_configfile
    split_configname
);

our %globalconfig;  # App-Settings
our %hosts;
our $servername       = hostname;
our $prefix           = getcwd();
our $config_path      = "$prefix/etc";
our $config_global    = "$config_path/bang_globals.yaml";


sub get_global_config {

    sanityfilecheck($config_global);

    my $global_settings  = LoadFile($config_global);

    $globalconfig{log_path}            = "$prefix/$global_settings->{LogFolder}";
    $globalconfig{global_log_date}     =  strftime "$global_settings->{GlobalLogDate}", localtime;
    $globalconfig{global_log_file}     = "$globalconfig{log_path}/$globalconfig{global_log_date}.log";

    $globalconfig{path_available}      = "$config_path/$global_settings->{AvailableFolder}";
    $globalconfig{path_enabled}        = "$config_path/$global_settings->{EnabledFolder}";
    $globalconfig{path_special}        = "$config_path/$global_settings->{SpecialFolder}";

    $globalconfig{path_rsync}          = "$global_settings->{RSYNC}";
    $globalconfig{path_btrfs}          = "$global_settings->{BTRFS}";

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

sub find_host_configs {
    my ($query, $searchpath) = @_;

    my @files;
    my $ffr_obj = File::Find::Rule->file()
                                  ->name( $query  )
                                  ->relative
                                  ->maxdepth( 1 )
                                  ->start ( $searchpath );

    while (my $file = $ffr_obj->match()){
        push @files, $file;
    }
    return @files;
}

sub split_configname {
    my ($configfile) = @_;

    my ($hostname,$groupname) = $configfile =~ /^([\w\d-]+)_([\w\d-]+)\.yaml/;

    return ($hostname,$groupname) ;
}

sub find_hosts {
    my ($host) = @_;
    undef %hosts;
    my @configsavailable = find_host_configs("$host\_*.yaml", "$globalconfig{path_available}" );
    my @configsenabled   = find_host_configs("$host\_*.yaml", "$globalconfig{path_enabled}" );

    foreach my $configfile (@configsavailable) {
        my ($hostname,$group) = split_configname($configfile);

        $hosts{"$hostname-$group"}= {
            'hostname'   => $hostname,
            'group'      => $group,
            'status'     => "disabled",
            'configfile' => $configfile,
            'css_class'  => '',
            'hostconfig' => read_configfile($hostname,$group),
        };
    }


    foreach my $configfile (@configsenabled) {
        my ($hostname,$group) = split_configname($configfile);

        $hosts{"$hostname-$group"}{'status'} = "enabled";
        $hosts{"$hostname-$group"}{'css_class'} .= "active ";
    }

    return 1;
}

sub find_enabled_hosts {
    my @configfiles = find_host_configs("*_*.yaml", "$globalconfig{path_enabled}" );

    foreach my $configfile (@configfiles) {
        my ($hostname,$group) = split_configname($configfile);

        $hosts{"$hostname-$group"}= {
            group      => $group,
            configfile => $configfile,
        };
    }
    return 1;
}

sub find_available_hosts {
    my @configfiles = find_host_configs("*_*.yaml", "$globalconfig{path_available}" );

    foreach my $configfile (@configfiles) {
        my ($hostname,$group) = split_configname($configfile);

        $hosts{"$hostname-$group"}= {
            group      => $group,
            configfile => $configfile,
        };
    }
    return 1;
}

sub read_configfile {
    my ($host, $group) = @_;
    my $configfile_host;
    my $settings;

    if ($group eq "NIS"){
        $configfile_host  = $globalconfig{config_default_nis};
    }
    else{
        $configfile_host  = "$globalconfig{path_available}/$host\_$group.yaml";
    }

    if ( sanityfilecheck($configfile_host) ) {

        $settings = LoadFile($globalconfig{config_default});

        my $settings_host  = LoadFile($configfile_host);

        foreach my $key ( keys %{ $settings_host } ){
            next if !$settings_host->{$key};
            $settings->{$key} = $settings_host->{$key};
        }

    }
    return $settings;
}

1;
