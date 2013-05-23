package BaNG::Config;

use Cwd 'abs_path';
use File::Basename;
use File::Find::Rule;
use POSIX qw(strftime);
use Sys::Hostname;
use YAML::Tiny qw(LoadFile Dump);

use Exporter 'import';
our @EXPORT = qw(
    %globalconfig
    %hosts
    %groups
    $prefix
    $config_path
    $config_global
    $servername
    get_global_config
    get_default_config
    get_host_config
    get_group_config
    get_cronjob_config
    generated_crontab
    read_host_configfile
    split_configname
);

our %globalconfig;
our %defaultconfig;
our %hosts;
our %groups;
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
    $globalconfig{config_bangstat}    = "$config_path/$global_settings->{BangstatConfig}";

    $globalconfig{path_serverconfig}  = "$config_path/$global_settings->{ServerConfigFolder}";
    $globalconfig{path_groupconfig}   = "$config_path/$global_settings->{GroupConfigFolder}";
    $globalconfig{path_hostconfig}    = "$config_path/$global_settings->{HostConfigFolder}";
    $globalconfig{path_excludes}      = "$config_path/$global_settings->{ExcludesFolder}";
    $globalconfig{path_lockfiles}     = "$config_path/$global_settings->{LocksFolder}";

    $globalconfig{path_date}          = "$global_settings->{DATE}";
    $globalconfig{path_rsync}         = "$global_settings->{RSYNC}";
    $globalconfig{path_btrfs}         = "$global_settings->{BTRFS}";

    $globalconfig{debug}              = "$global_settings->{Debug}";
    $globalconfig{debuglevel}         = "$global_settings->{DebugLevel}";
    $globalconfig{dryrun}             = "$global_settings->{Dryrun}";
    $globalconfig{auto_wipe_limit}    = "$global_settings->{AutoWipeLimit}";

    my $server_globals = "$globalconfig{path_serverconfig}/${servername}_globals.yaml";
    if ( sanityfilecheck($server_globals) ) {
        my $server_settings = LoadFile($server_globals);
        $globalconfig{path_date}          = $server_settings->{DATE};
        $globalconfig{path_rsync}         = $server_settings->{RSYNC};
        $globalconfig{report_to}          = $server_settings->{ReportTo};
    }

    return 1;
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

sub find_configs {
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

sub split_group_configname {
    my ($configfile) = @_;

    my ($groupname) = $configfile =~ /^([\w\d-]+)\.yaml/;

    return ($groupname);
}

sub split_cronconfigname {
    my ($cronconfigfile) = @_;

    my ($server,$jobtype) = $cronconfigfile =~ /^([\w\d-]+)_cronjobs_([\w\d-]+)\.yaml/;

    return ($server,$jobtype);
}

sub get_host_config {
    my ($host, $group) = @_;

    $host  = $host  || '*';
    $group = $group || '*';
    undef %hosts;
    my @hostconfigs = find_configs("$host\_$group\.yaml", "$globalconfig{path_hostconfig}" );

    foreach my $hostconfigfile (@hostconfigs) {
        my ($hostname,$group)           = split_configname($hostconfigfile);
        my ($hostconfig, $confighelper) = read_host_configfile($hostname, $group);
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

sub get_group_config {
    my ($group) = @_;

    $group = $group || '*';
    undef %groups;
    my @groupconfigs = find_configs("$group\.yaml", "$globalconfig{path_groupconfig}" );

    foreach my $groupconfigfile (@groupconfigs) {
        my ($groupname)                  = split_group_configname($groupconfigfile);
        my ($groupconfig, $confighelper) = read_group_configfile($groupname);
        my $isEnabled                    = $groupconfig->{BKP_ENABLED};
        my $isBulkbkp                    = $groupconfig->{BKP_BULK_ALLOW};
        my $isBulkwipe                   = $groupconfig->{WIPE_BULK_ALLOW};
        my $status                       = $isEnabled ? "enabled" : "disabled";
        my $css_class                    = $isEnabled ? "active " : "";
        my $nobulk_css_class             = ( $isBulkbkp == 0 && $isBulkwipe == 0 ) ? "nobulk " : "";

        $groups{"$groupname"} = {
            'status'           => $status,
            'configfile'       => $groupconfigfile,
            'css_class'        => $css_class,
            'nobulk_css_class' => $nobulk_css_class,
            'groupconfig'      => $groupconfig,
            'confighelper'     => $confighelper,
        };
    }

    return 1;
}

sub get_cronjob_config {
    my %unsortedcronjobs;
    my %sortedcronjobs;

    my @cronconfigs = find_configs("*_cronjobs_*.yaml", "$globalconfig{path_serverconfig}" );

    foreach my $cronconfigfile (@cronconfigs) {
        my ($server,$jobtype)  = split_cronconfigname($cronconfigfile);

        foreach my $jobtype ( qw( backup wipe ) ) {
            my $cronjobsfile = "$globalconfig{path_serverconfig}/${server}_cronjobs_$jobtype.yaml";
            return unless sanityfilecheck($cronjobsfile);
            my $cronjobslist = LoadFile($cronjobsfile);

            foreach my $cronjob ( keys %{$cronjobslist} ) {
                my ($host, $group) = split( /_/, $cronjob );

                $unsortedcronjobs{$server}{$jobtype}{$cronjob} = {
                    'host'  => $host,
                    'group' => $group,
                    'ident' => "$host-$group",
                    'cron'  => $cronjobslist->{$cronjob},
                };
            }

            my $id = 1;
            foreach my $cronjob ( sort {
                sprintf("%02d%02d", $unsortedcronjobs{$server}{$jobtype}{$a}{cron}->{HOUR}, $unsortedcronjobs{$server}{$jobtype}{$a}{cron}->{MIN})
                <=>
                sprintf("%02d%02d", $unsortedcronjobs{$server}{$jobtype}{$b}{cron}->{HOUR}, $unsortedcronjobs{$server}{$jobtype}{$b}{cron}->{MIN})
                } keys %{ $unsortedcronjobs{$server}{$jobtype} } ) {
                my $PastMidnight = ( $unsortedcronjobs{$server}{$jobtype}{$cronjob}{cron}->{HOUR} >= 18 ) ? 0 : 1;

                $sortedcronjobs{$server}{$jobtype}{sprintf("$jobtype$PastMidnight%05d", $id)} = $unsortedcronjobs{$server}{$jobtype}{$cronjob};
                $id++;
            }
        }
    }

    return \%sortedcronjobs;
}

sub generated_crontab {
    my $cronjobs = get_cronjob_config();
    my $crontab  = "# Automatically generated by BaNG; do not edit locally\n";

    foreach my $jobtype ( sort keys %{ $cronjobs->{$servername} } ) {
        $crontab .= "#--- $jobtype ---\n";
        foreach my $cronjob ( sort keys %{ $cronjobs->{$servername}->{$jobtype} } ) {
            my %cron;
            foreach my $key ( qw( MIN HOUR DOM MONTH DOW ) ) {
                $cron{$key} = $cronjobs->{$servername}->{$jobtype}->{$cronjob}->{cron}->{$key};
                $crontab .= sprintf('%3s', $cron{$key});
            }
            $crontab .= "    root    $prefix/BaNG";

            $crontab .= " --wipe" if ( $jobtype eq 'wipe' );

            my $host  = "$cronjobs->{$servername}->{$jobtype}->{$cronjob}->{host}";
            $crontab .= " -h $host" unless $host eq 'BULK';

            my $group = "$cronjobs->{$servername}->{$jobtype}->{$cronjob}->{group}";
            $crontab .= " -g $group" unless $group eq 'BULK';

            my $threads = $cronjobs->{$servername}->{$jobtype}->{$cronjob}->{cron}->{THREADS};
            $crontab .= " -t $threads" if $threads;

            $crontab .= "\n";
        }
    }

    return $crontab;
}

sub read_host_configfile {
    my ($host, $group) = @_;

    my %configfile;
    my $settings;
    my $settingshelper;

    $configfile{group} = "$globalconfig{path_groupconfig}/$group.yaml";
    $configfile{host}  = "$globalconfig{path_hostconfig}/$host\_$group.yaml";

    $settings         = LoadFile($globalconfig{config_default});

    foreach my $configtmpl (qw( group host ))  {
        if ( sanityfilecheck($configfile{$configtmpl}) ) {

            my $settings_host = LoadFile($configfile{$configtmpl});

            foreach my $key ( keys %{$settings_host} ) {
                $settings->{$key}       = $settings_host->{$key};
                $settingshelper->{$key} = $configtmpl;
            }
        }
    }

    return $settings, $settingshelper;
}

sub read_group_configfile {
    my ($group) = @_;

    my %configfile;
    my $settings;
    my $settingshelper;

    $configfile{group} = "$globalconfig{path_groupconfig}/$group.yaml";

    $settings         = LoadFile($globalconfig{config_default});

    foreach my $configtmpl (qw( group ))  {
        if ( sanityfilecheck($configfile{$configtmpl}) ) {

            my $settings_host = LoadFile($configfile{$configtmpl});

            foreach my $key ( keys %{$settings_host} ) {
                $settings->{$key}       = $settings_host->{$key};
                $settingshelper->{$key} = $configtmpl;
            }
        }
    }

    return $settings, $settingshelper;
}

1;
