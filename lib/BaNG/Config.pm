package BaNG::Config;

use Cwd 'abs_path';
use Dancer ':syntax';
use File::Find::Rule;
use POSIX qw(strftime);
use Sys::Hostname;
use YAML::Tiny qw(LoadFile Dump);

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    %hosts
    %cronjobs
    $prefix
    $config_path
    $config_global
    $servername
    get_global_config
    get_default_config
    get_host_config
    get_cronjob_config
    read_configfile
    split_configname
);

our %globalconfig;
our %defaultconfig;
our %hosts;
our %cronjobs;
our $config_path;
our $config_global;
our $servername = hostname;
our $prefix     = dirname( abs_path($0) );

sub get_global_config {
    my ($prefix_arg) = @_;

    $prefix        = $prefix_arg if $prefix_arg;
    $config_path   = "$prefix/etc";
    $config_global = "$config_path/bang_globals.yaml";

    sanityfilecheck($config_global);
    my $global_settings = LoadFile($config_global);
    my $log_date = strftime "$global_settings->{GlobalLogDate}", localtime;

    $globalconfig{log_path}           = "$prefix/$global_settings->{LogFolder}";
    $globalconfig{global_log_file}    = "$globalconfig{log_path}/$log_date.log";
    $globalconfig{global_log_date}    = "$global_settings->{GlobalLogDate}";
    $globalconfig{report_to}          = "$global_settings->{ReportTo}";

    $globalconfig{config_default}     = "$config_path/$global_settings->{DefaultConfig}";
    $globalconfig{config_default_nis} = "$config_path/$global_settings->{DefaultNisConfig}";
    $globalconfig{config_bangstat}    = "$config_path/$global_settings->{BangstatConfig}";

    $globalconfig{path_hostconfig}    = "$config_path/$global_settings->{HostConfigFolder}";
    $globalconfig{path_cronjobs}      = "$config_path/$global_settings->{CronJobsFolder}";
    $globalconfig{path_excludes}      = "$config_path/$global_settings->{ExcludesFolder}";
    $globalconfig{path_lockfiles}     = "$config_path/$global_settings->{LocksFolder}";

    $globalconfig{path_rsync}         = "$global_settings->{RSYNC}";
    $globalconfig{path_btrfs}         = "$global_settings->{BTRFS}";

    $globalconfig{debug}              = "$global_settings->{Debug}";
    $globalconfig{debuglevel}         = "$global_settings->{DebugLevel}";
    $globalconfig{dryrun}             = "$global_settings->{Dryrun}";
}

sub get_default_config {

    sanityfilecheck($config_global);
    sanityfilecheck($globalconfig{config_default});
    my $defaultconfig  = LoadFile($globalconfig{config_default});

    return $defaultconfig;
}

sub sanityfilecheck {
    my ($file) = @_;

    if ( !-f "$file" ) {
        # logit("localhost","INTERNAL", "$file NOT available");
        return 0;    # FIXME CLI should check return value
    } else {
        return 1;
    }
}

sub find_host_configs {
    my ($query, $searchpath) = @_;

    my @files;
    my $ffr_obj = File::Find::Rule->file()
                                  ->name($query)
                                  ->relative
                                  ->maxdepth(1)
                                  ->start($searchpath);

    while ( my $file = $ffr_obj->match() ) {
        push( @files, $file );
    }

    return @files;
}

sub split_configname {
    my ($configfile) = @_;

    my ($hostname,$groupname) = $configfile =~ /^([\w\d-]+)_([\w\d-]+)\.yaml/;

    return ($hostname,$groupname);
}

sub get_host_config {
    my ($host, $group) = @_;

    $host  = $host  || '*';
    $group = $group || '*';
    undef %hosts;
    my @hostconfigs = find_host_configs("$host\_$group\.yaml", "$globalconfig{path_hostconfig}" );

    foreach my $hostconfigfile (@hostconfigs) {
        my ($hostname,$group)           = split_configname($hostconfigfile);
        my ($hostconfig, $confighelper) = read_configfile($hostname, $group);
        my $isEnabled                   = $hostconfig->{BKP_ENABLED};
        my $isBulkbkp                   = $hostconfig->{BKP_BULK_ALLOW};
        my $isBulkwipe                  = $hostconfig->{WIPE_BULK_ALLOW};
        my $status                      = $isEnabled ? "enabled" : "disabled";
        my $css_class                   = $isEnabled ? "active " : "";
        my $nobulk_css_class            = ( $isBulkbkp == 0 && $isBulkwipe == 0 ) ? "nobulk " : "";

        $hosts{"$hostname-$group"} = {
            'hostname'         => $hostname,
            'group'            => $group,
            'status'           => $status,
            'configfile'       => $hostconfigfile,
            'css_class'        => $css_class,
            'nobulk_css_class' => $nobulk_css_class,
            'hostconfig'       => $hostconfig,
            'confighelper'     => $confighelper,
        };
    }

    return 1;
}

sub get_cronjob_config {

    my $cronjobsfile = "$globalconfig{path_cronjobs}/cronjobs.yaml";
    my %sortedcronjobs;

    if ( sanityfilecheck($cronjobsfile) ) {

        undef %cronjobs;
        my $cronjobslist = LoadFile($cronjobsfile);

        foreach my $cronjob ( keys %{$cronjobslist} ) {
            my ($host, $group) = split( /_/, $cronjob );

            $cronjobs{"$cronjob"} = {
                'hostname' => $host,
                'group'    => $group,
                'ident'    => "$host-$group",
                'BACKUP'   => $cronjobslist->{$cronjob}->{BACKUP},
                'WIPE'     => $cronjobslist->{$cronjob}->{WIPE},
            };
        }

        my $id = 1;
        foreach my $cronjob ( sort sort_cronjob_by_backup_time keys %cronjobs ) {
            my $PastMidnight = ( $cronjobs{$cronjob}->{BACKUP}->{HOUR} >= 18 ) ? 0 : 1;
            $sortedcronjobs{sprintf("$PastMidnight%05d", $id)} = $cronjobs{$cronjob};
            $id++;
        }
    }

    return \%sortedcronjobs;
}

sub sort_cronjob_by_backup_time {
    sprintf("%02d%02d", $cronjobs{$a}->{BACKUP}->{HOUR}, $cronjobs{$a}->{BACKUP}->{MIN})
    <=>
    sprintf("%02d%02d", $cronjobs{$b}->{BACKUP}->{HOUR}, $cronjobs{$b}->{BACKUP}->{MIN})
    ;
}

sub read_configfile {
    my ($host, $group) = @_;

    my $configfile_host;
    my $settings;
    my $settingshelper;

    if ( $group eq "NIS" ) {
        $configfile_host = $globalconfig{config_default_nis};
    } else {
        $configfile_host = "$globalconfig{path_hostconfig}/$host\_$group.yaml";
    }

    if ( sanityfilecheck($configfile_host) ) {

        $settings         = LoadFile($globalconfig{config_default});
        my $settings_host = LoadFile($configfile_host);

        foreach my $key ( keys %{$settings_host} ) {
            next unless $settings_host->{$key};
            $settings->{$key} = $settings_host->{$key};
            $settingshelper->{$key} = 1;
        }
    }

    return $settings, $settingshelper;
}

1;
