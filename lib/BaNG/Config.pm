package BaNG::Config;

use 5.010;
use strict;
use warnings;
use Cwd qw( abs_path );
use File::Basename;
use File::Find::Rule;
use POSIX qw( strftime );
use YAML::Tiny qw( LoadFile DumpFile );
use Text::Diff;

use Exporter 'import';
our @EXPORT = qw(
    %hosts
    %groups
    %servers
    %serverconfig
    $prefix
    $servername
    get_server_config_defaults
    get_serverconfig
    get_host_config_defaults
    get_host_config
    get_group_config
    write_config
    update_config
    delete_config
    get_cronjob_config
    generated_crontab
    status_crontab
);

our %hosts;
our %groups;
our %servers;
our %serverconfig;
our $prefix     = dirname( abs_path($0) );
our $servername = `hostname -s`;
chomp $servername;

sub get_serverconfig {
    my ($prefix_arg) = @_;

    if ($prefix_arg) {
        $prefix     = $prefix_arg;
        $servername = 'bangtestserver' if $prefix_arg eq 't';    # Run test suite with specific server name
    }

    undef %servers;
    undef %serverconfig;
    $serverconfig{path_configs}            = "$prefix/etc";
    $serverconfig{config_defaults_servers} = "$serverconfig{path_configs}/defaults_servers.yaml";
    $serverconfig{path_serverconfig}       = "$serverconfig{path_configs}/servers";

    # get info about all backup servers
    my @serverconfigs = _find_configs( "*_defaults\.yaml", $serverconfig{path_serverconfig} );

    foreach my $serverconfigfile (@serverconfigs) {
        my $server = _split_server_configname($serverconfigfile);
        my ( $serverconfig, $confighelper ) = _read_server_configfile($server);

        $servers{$server} = {
            configfile   => $serverconfigfile,
            serverconfig => $serverconfig,
            confighelper => $confighelper,
        };
    }

    # copy info about localhost to separate hash for easier retrieval
    foreach my $key ( keys %{$servers{$servername}{serverconfig}} ) {
        $serverconfig{$key} = $servers{$servername}{serverconfig}->{$key};
    }

    # preprend full path where needed
    foreach my $key (qw( config_defaults_hosts config_bangstat path_groupconfig path_hostconfig path_excludes path_logs path_lockfiles )) {
        $serverconfig{$key} = "$prefix/$serverconfig{$key}";
    }

    return 1;
}

sub get_server_config_defaults {
    my $defaults_server_file = $serverconfig{config_defaults_servers};
    my $settings;
    if ( _sanityfilecheck($defaults_server_file) ) {
        $settings = LoadFile($defaults_server_file);
    }

    return $settings;
}

sub get_host_config_defaults {
    my $defaults_hosts_file = $serverconfig{config_defaults_hosts};
    my $settings;
    if ( _sanityfilecheck($defaults_hosts_file) ) {
        $settings = LoadFile($defaults_hosts_file);
    }

    return $settings;
}

sub write_config {
    my ( $configtype, $modtype, $host, $group, $settings ) = @_;

    chomp $host;
    chomp $group;
    my $path_config = 'path_' . $configtype . 'config';
    $host = ( $configtype eq 'group' ) ? 0 : $host;

    if ( ( $host =~ /^[a-z\-0-9\.]+$/ ) && ( $group =~ /^[a-z\-0-9]+$/ ) ) {
        my $configName;
        if ( $configtype eq 'host' ) {
            $configName = $host . '_' . $group . '.yaml';
        } elsif ( $configtype eq 'group' ) {
            $configName = $group . '.yaml';
        }
        my $ConfigFile = "$serverconfig{$path_config}/$configName";

        if ( -f $ConfigFile && $modtype eq 'add' ) {
            return ( 3, "You try to override $ConfigFile!" );
        } else {
            DumpFile( $ConfigFile, $settings );
            chmod( 0664, $ConfigFile );
            chown( 0, 33, $ConfigFile );
            return ( 1, $ConfigFile );
        }
    } else {
        return ( 2, 'Hostname or Group uses wrong character!' );
    }
}

sub update_config {
    my ( $configtype, $host, $group, $key_arg, $val_arg ) = @_;

    my $settings;
    my $configName;
    my $path_config = 'path_' . $configtype . 'config';

    if ( $configtype eq 'host' ) {
        $configName = $host . '_' . $group . '.yaml';
    } elsif ( $configtype eq 'group' ) {
        $configName = $group . '.yaml';
    }

    my $configFile = "$serverconfig{$path_config}/$configName";

    if ( _sanityfilecheck($configFile) ) {
        $settings = LoadFile($configFile);
        $settings->{$key_arg} = $val_arg;
    }

    my ( $return_code, $return_msg ) = write_config( $configtype, 'update', $host, $group, $settings );

    return ( $return_code, $return_msg );
}

sub delete_config {
    my ( $configtype, $configfile ) = @_;

    my $path_config   = 'path_' . $configtype . 'config';
    my $DelConfigFile = "$serverconfig{$path_config}/$configfile";

    if ( -f $DelConfigFile ) {
        unlink $DelConfigFile;
        return ( 0, "Configfile $DelConfigFile deleted successfully." );
    } else {
        return ( 1, "$DelConfigFile does not exist." );
    }
}

sub get_host_config {
    my ( $host, $group ) = @_;

    $host  ||= '*';
    $group ||= '*';
    undef %hosts;
    my @hostconfigs = _find_configs( "$host\_$group\.yaml", "$serverconfig{path_hostconfig}" );

    foreach my $hostconfigfile (@hostconfigs) {
        my ( $hostname, $groupname ) = _split_configname($hostconfigfile);
        my ( $hostconfig, $confighelper ) = _read_host_configfile( $hostname, $groupname );
        my $isEnabled        = $hostconfig->{BKP_ENABLED};
        my $isBulkbkp        = $hostconfig->{BKP_BULK_ALLOW};
        my $isBulkwipe       = $hostconfig->{WIPE_BULK_ALLOW};
        my $status           = $isEnabled ? 'enabled' : 'disabled';
        my $css_class        = $isEnabled ? 'active ' : '';
        my $nobulk_css_class = ( $isBulkbkp == 0 && $isBulkwipe == 0 ) ? 'nobulk ' : '';

        $hosts{"$hostname-$groupname"} = {
            hostname         => $hostname,
            group            => $groupname,
            status           => $status,
            configfile       => $hostconfigfile,
            css_class        => $css_class,
            nobulk_css_class => $nobulk_css_class,
            hostconfig       => $hostconfig,
            confighelper     => $confighelper,
        };
    }

    return 1;
}

sub get_group_config {
    my ($group) = @_;

    $group ||= '*';
    undef %groups;
    my @groupconfigs = _find_configs( "$group\.yaml", "$serverconfig{path_groupconfig}" );

    foreach my $groupconfigfile (@groupconfigs) {
        my ($groupname) = _split_group_configname($groupconfigfile);
        my ( $groupconfig, $confighelper ) = _read_group_configfile($groupname);
        my @groupmembers     = BaNG::Common::list_groupmembers($groupname);
        my $isEnabled        = $groupconfig->{BKP_ENABLED};
        my $isBulkbkp        = $groupconfig->{BKP_BULK_ALLOW};
        my $isBulkwipe       = $groupconfig->{WIPE_BULK_ALLOW};
        my $status           = $isEnabled ? 'enabled' : 'disabled';
        my $css_class        = $isEnabled ? 'active ' : '';
        my $nobulk_css_class = ( $isBulkbkp == 0 && $isBulkwipe == 0 ) ? 'nobulk ' : '';

        $groups{$groupname} = {
            status           => $status,
            configfile       => $groupconfigfile,
            css_class        => $css_class,
            nobulk_css_class => $nobulk_css_class,
            groupconfig      => $groupconfig,
            confighelper     => $confighelper,
            groupmembers     => @groupmembers,
        };
    }

    return 1;
}

sub get_cronjob_config {
    my %unsortedcronjobs;
    my %sortedcronjobs;

    my @cronconfigs = _find_configs( '*_cronjobs.yaml', $serverconfig{path_serverconfig} );

    foreach my $cronconfigfile (@cronconfigs) {
        my $server       = _split_cron_configname($cronconfigfile);
        my $cronjobsfile = "$serverconfig{path_serverconfig}/${server}_cronjobs.yaml";
        next unless _sanityfilecheck($cronjobsfile);
        my $cronjobslist = LoadFile($cronjobsfile);

        $sortedcronjobs{$server}{header} = $cronjobslist->{header};

        JOBTYPE: foreach my $jobtype (qw( backup backup_missingonly wipe )) {
            foreach my $cronjob ( keys %{$cronjobslist->{$jobtype}} ) {
                my ( $host, $group ) = split( /_/, $cronjob );

                $unsortedcronjobs{$server}{$jobtype}{$cronjob} = {
                    host  => $host,
                    group => $group,
                    ident => "$host-$group",
                    cron  => $cronjobslist->{$jobtype}->{$cronjob},
                };

                # We mostly specify the time of the cronjob and therefore the other values default to '*'
                foreach my $key (qw( DOM MONTH DOW )) {
                    my $cron = $unsortedcronjobs{$server}{$jobtype}{$cronjob}->{cron};
                    $cron->{$key} = $cron->{$key} || '*';
                }
            }

            my $id = 1;
            foreach my $cronjob ( sort {
                sprintf('%02d%02d', $unsortedcronjobs{$server}{$jobtype}{$a}{cron}->{HOUR}, $unsortedcronjobs{$server}{$jobtype}{$a}{cron}->{MIN})
                <=>
                sprintf('%02d%02d', $unsortedcronjobs{$server}{$jobtype}{$b}{cron}->{HOUR}, $unsortedcronjobs{$server}{$jobtype}{$b}{cron}->{MIN})
                ||
                $a cmp $b
                } keys %{ $unsortedcronjobs{$server}{$jobtype} } ) {

                my $PastMidnight = ( $unsortedcronjobs{$server}{$jobtype}{$cronjob}{cron}->{HOUR} >= 18 ) ? 0 : 1;
                $sortedcronjobs{$server}{$jobtype}{sprintf( "$jobtype$PastMidnight%05d", $id )} = $unsortedcronjobs{$server}{$jobtype}{$cronjob};
                $id++;
            }
        }
    }

    return \%sortedcronjobs;
}

sub generated_crontab {
    my $cronjobs = get_cronjob_config();

    my $crontab = "# Automatically generated; do not edit locally\n";

    foreach my $headerkey (sort keys %{ $cronjobs->{$servername}->{header} } ) {
        $crontab .= "$headerkey=$cronjobs->{$servername}->{header}->{$headerkey}\n";
    }

    foreach my $jobtype (qw( backup backup_missingonly wipe )) {
        $crontab .= "#--- $jobtype ---\n";
        foreach my $cronjob ( sort keys %{$cronjobs->{$servername}->{$jobtype}} ) {
            my %cron;
            foreach my $key (qw( MIN HOUR DOM MONTH DOW )) {
                $cron{$key} = $cronjobs->{$servername}->{$jobtype}->{$cronjob}->{cron}->{$key};
                $crontab .= sprintf( '%2s ', $cron{$key} );
            }
            $crontab .= "    root    $prefix/BaNG";

            my $host = "$cronjobs->{$servername}->{$jobtype}->{$cronjob}->{host}";
            $crontab .= " -h $host" unless $host eq 'BULK';

            my $group = "$cronjobs->{$servername}->{$jobtype}->{$cronjob}->{group}";
            $crontab .= " -g $group" unless $group eq 'BULK';

            my $threads = $cronjobs->{$servername}->{$jobtype}->{$cronjob}->{cron}->{THREADS};
            $crontab .= " -t $threads" if $threads;

            my $finallysnapshots = $cronjobs->{$servername}->{$jobtype}->{$cronjob}->{cron}->{FINALLYSNAPSHOTS};
            $crontab .= " --finallysnapshots" if $finallysnapshots;

            $crontab .= " --wipe"        if ( $jobtype eq 'wipe' );
            $crontab .= " --missingonly" if ( $jobtype eq 'backup_missingonly' );

            $crontab .= "\n";
        }
    }

    return $crontab;
}

sub status_crontab {
    my $gen_crontab = generated_crontab();
    open ( my $cur_crontab, "<",'/etc/cron.d/BaNG' ) or die ("Can't open /etc/cron.d/BaNG for reading");

    my $diffs = diff \$gen_crontab, "/etc/cron.d/BaNG", { STYLE => "Table" };

    close $gen_crontab;
    print "$diffs\n" if $diffs;
}

sub _read_host_configfile {
    my ( $host, $group ) = @_;

    my %configfile;
    my $settings = get_host_config_defaults();
    $configfile{group} = "$serverconfig{path_groupconfig}/$group.yaml";
    $configfile{host}  = "$serverconfig{path_hostconfig}/$host\_$group.yaml";
    my $settingshelper = _override_config( $settings, \%configfile, qw( group host ) );

    return ( $settings, $settingshelper );
}

sub _read_group_configfile {
    my ($group) = @_;

    my %configfile;
    my $settings = get_host_config_defaults();
    $configfile{group} = "$serverconfig{path_groupconfig}/$group.yaml";
    my $settingshelper = _override_config( $settings, \%configfile, qw( group ) );

    return ( $settings, $settingshelper );
}

sub _read_server_configfile {
    my ($server) = @_;

    my %configfile;
    my $settings = LoadFile( $serverconfig{config_defaults_servers} );
    $configfile{server} = "$serverconfig{path_serverconfig}/${server}_defaults.yaml";
    my $settingshelper = _override_config( $settings, \%configfile, qw( server ) );

    return ( $settings, $settingshelper );
}

sub _override_config {
    my ( $settings, $configfile, @overrides ) = @_;

    my $settingshelper;
    foreach my $config_override (@overrides) {
        if ( _sanityfilecheck( $configfile->{$config_override} ) ) {

            my $settings_override = LoadFile( $configfile->{$config_override} );

            foreach my $key ( keys %{$settings_override} ) {
                $settings->{$key}       = $settings_override->{$key};
                $settingshelper->{$key} = $config_override;
            }
        }
    }

    return ($settingshelper);
}

sub _sanityfilecheck {
    my ($file) = @_;

    if ( !-f $file ) {
        # logit("000000","localhost","INTERNAL", "$file NOT available");
        return 0;    # FIXME CLI should check return value
    } else {
        return 1;
    }
}

sub _find_configs {
    my ( $query, $searchpath ) = @_;

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

sub _split_configname {
    my ($configfile) = @_;

    my ( $hostname, $groupname ) = $configfile =~ /^([\w\d\.-]+)_([\w\d-]+)\.yaml/;

    return ( $hostname, $groupname );
}

sub _split_group_configname {
    my ($configfile) = @_;

    my ($groupname) = $configfile =~ /^([\w\d-]+)\.yaml/;

    return ($groupname);
}

sub _split_server_configname {
    my ($configfile) = @_;

    my ($server) = $configfile =~ /^([\w\d-]+)_defaults\.yaml/;

    return $server;
}

sub _split_cron_configname {
    my ($cronconfigfile) = @_;

    my ($server) = $cronconfigfile =~ /^([\w\d-]+)_cronjobs\.yaml/;

    return $server;
}
