package BaNG::Config;

use Dancer ':syntax';
use BaNG::Reporting;
use POSIX qw(strftime);
use File::Find::Rule;
use YAML::Tiny qw(LoadFile Dump);

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    %hosts
    %settings
    get_global_config
    find_enabled_configs
    find_enabled_hosts
    read_configfile
    split_configname
);

our %globalconfig;  # App-Settings
our %settings;      # Host-Settings
our %hosts;

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

sub find_enabled_configs {
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

sub find_enabled_hosts {
    my @configfiles = find_enabled_configs("*_*.yaml", "$globalconfig{path_enabled}" );

    foreach my $configfile (@configfiles) {
        my ($hostname,$group) = split_configname($configfile);
        debug "$hostname $group";
        #$hosts{$hostname}->{group} = $group;
        $hosts{$hostname}= {
            group      => $group,
            configfile => $configfile,
        };
        debug "sub $hosts{inferius}{group}";
    }
    return 1;
}


sub read_configfile {
    my ($host, $group) = @_;
    my $configfile_host;

    if ($group eq "NIS"){
        $configfile_host  = $globalconfig{config_default_nis};
    }
    else{
        $configfile_host  = "$globalconfig{path_enabled}/$host\_$group.yaml";
    }

    if ( sanityfilecheck($configfile_host) ) {

        $settings{$host}  = LoadFile($globalconfig{config_default});

        my $settings_host  = LoadFile($configfile_host);

        foreach my $key ( keys %{ $settings_host } ){
            next if !$settings_host->{$key};
            $settings{$host}->{$key} = $settings_host->{$key};
        }

    }
    return $settings{$host};
}


1;
