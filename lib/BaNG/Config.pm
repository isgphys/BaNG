package BaNG::Config;

use Dancer ':syntax';
use BaNG::Reporting;
use POSIX qw(strftime);
use File::Find::Rule;
use YAML::Tiny qw(LoadFile Dump);

use Sys::Hostname;
use Cwd 'abs_path';

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    %hosts
    $prefix
    $config_path
    $config_global
    $servername
    get_global_config
    get_default_config
    get_host_config
    read_configfile
    split_configname
);

our %globalconfig;  # App-Settings
our %defaultconfig;
our %hosts;
our $servername       = hostname;
our $prefix           = dirname(abs_path($0));
our $config_path      = "$prefix/etc";
our $config_global    = "$config_path/bang_globals.yaml";


sub get_global_config {

    sanityfilecheck($config_global);

    my $global_settings  = LoadFile($config_global);

    $globalconfig{log_path}            = "$prefix/$global_settings->{LogFolder}";

    #$globalconfig{global_log_date}     =  strftime "$global_settings->{GlobalLogDate}", localtime;
    my $log_date     =  strftime "$global_settings->{GlobalLogDate}", localtime;

    $globalconfig{global_log_date}     = "$global_settings->{GlobalLogDate}";
    $globalconfig{global_log_file}     = "$globalconfig{log_path}/$log_date.log";

    $globalconfig{path_hostconfig}      = "$config_path/$global_settings->{HostConfigFolder}";
    $globalconfig{path_cronjobs}       = "$config_path/$global_settings->{CronJobsFolder}";

    $globalconfig{path_rsync}          = "$global_settings->{RSYNC}";
    $globalconfig{path_btrfs}          = "$global_settings->{BTRFS}";

    $globalconfig{config_default}      = "$config_path/$global_settings->{DefaultConfig}";
    $globalconfig{config_default_nis}  = "$config_path/$global_settings->{DefaultNisConfig}";
}

sub get_default_config {

    sanityfilecheck($config_global);
    sanityfilecheck($globalconfig{config_default});

    my $defaultconfig  = LoadFile($globalconfig{config_default});
    return $defaultconfig;
}

sub sanityfilecheck {
    my ($file) = @_;

    if ( ! -f "$file" ){
#        logit("localhost","INTERNAL", "$file NOT available");
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

sub get_host_config {
    my ($host, $group) = @_;
    $host = $host || '*';
    $group = $group || '*';
    undef %hosts;
    my @hostconfigs = find_host_configs("$host\_$group\.yaml", "$globalconfig{path_hostconfig}" );

    foreach my $hostconfigfile (@hostconfigs) {
        my ($hostname,$group) = split_configname($hostconfigfile);
        my $hostconfig = read_configfile($hostname,$group);
        my $isEnabled  = $hostconfig->{BKP_ENABLED};
        my $css_class  = $isEnabled ? "active " : "";
        my $status     = $isEnabled ? "enabled" : "disabled";

        $hosts{"$hostname-$group"}= {
            'hostname'   => $hostname,
            'group'      => $group,
            'status'     => $status,
            'configfile' => $hostconfigfile,
            'css_class'  => $css_class,
            'hostconfig' => $hostconfig,
            'cronconfig' => read_cronfile($hostname,$group),
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
        $configfile_host  = "$globalconfig{path_hostconfig}/$host\_$group.yaml";
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

sub read_cronfile {
    my ($host, $group) = @_;
    my $cronfile;

    $cronfile  = "$globalconfig{path_cronjobs}/cron_$host\_$group.yaml";

    if ( sanityfilecheck($cronfile) ) {

        my $settings_cron  = LoadFile($cronfile);

        return $settings_cron;
    }
    else{
       return 0;
    }
}

1;
