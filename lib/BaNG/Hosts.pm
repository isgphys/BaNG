package BaNG::Hosts;

use 5.010;
use strict;
use warnings;
use BaNG::Common;
use BaNG::Config;
use BaNG::Reporting;
use Net::Ping;

use Exporter 'import';
our @EXPORT = qw(
    get_fsinfo
    get_lockfiles
    check_client_connection
    create_lockfile
    remove_lockfile
    check_lockfile
    getlockfiles
);

sub get_fsinfo {
    my %fsinfo;
    foreach my $server ( keys %servers ) {
        my @mounts;
        @mounts = remotewrapper_command( $server, 'BaNG/bang_df' );

        foreach my $mount (@mounts) {
            $mount =~ qr{
                        ^(?<filesystem> [\/\w\d-]+)
                        \s+(?<fstyp> [\w\d]+)
                        \s+(?<blocks> [\d]+)
                        \s+(?<used> [\d]+)
                        \s+(?<available>[\d]+)
                        \s+(?<usedper> [\d]+)
                        .\s+(?<mountpt> [\/\w\d-]+)
            }x;

            $fsinfo{$server}{$+{mountpt}} = {
                'filesystem' => $+{filesystem},
                'mount'      => $+{mountpt},
                'fstyp'      => $+{fstyp},
                'blocks'     => num2human($+{blocks}),
                'used'       => num2human($+{used}*1024,1024),
                'available'  => num2human($+{available}*1024,1024),
                'freediff'   => "",
                'used_per'   => $+{usedper},
                'css_class'  => check_fill_level($+{usedper}),
            };
        }

        if ($server eq $servername) {
            @mounts = remotewrapper_command( $server, 'BaNG/bang_di' ) ;
            foreach my $mount (@mounts) {
                $mount =~ qr{
                ^(?<filesystem> [\/\w\d-]+)
                \s+(?<fstyp>[\w\d]+)
                \s+(?<blocks>[\d]+)
                \s+(?<used>[\d]+)
                \s+(?<available>[\d]+)
                \s+(?<free>[\d]+)
                \s+(?<usedper>[\d]+)
                .\s+(?<mountpt>[\/\w\d-]+)
                }x;

                my $freediff    = $+{free} - $+{available};
                my $freediffper = 100 / $+{free} * $freediff;

                $fsinfo{$server}{$+{mountpt}}{freediff} = ( $freediffper > 10 ) ? num2human($freediff*1024,1024) : "" ;
            }
        }

    }

    return \%fsinfo;
}

sub get_lockfiles {
    my %lockfiles;
    foreach my $server ( keys %servers ) {
        my @lockfiles = remotewrapper_command( $server, 'BaNG/bang_getLockFile', $serverconfig{path_lockfiles} );

        foreach my $lockfile ( @lockfiles  ) {
            my ($host, $group, $path, $timestamp, $file) = split_lockfile_name($lockfile);
            my $taskid = `cat $serverconfig{path_lockfiles}/$file`;
            $lockfiles{$server}{"$host-$group-$path"} = {
                'taskid'    => $taskid,
                'host'      => $host,
                'group'     => $group,
                'path'      => $path,
                'timestamp' => $timestamp,
            };
        }
    }

    return \%lockfiles;
}

sub check_fill_level {
    my ($level) = @_;
    my $css_class = '';

    if ( $level > 98 ) {
        $css_class = "alert_red";
    } elsif ( $level > 90 ) {
        $css_class = "alert_orange";
    } elsif ( $level > 80 ) {
        $css_class = "alert_yellow";
    }

    return $css_class;
}

sub check_client_connection {
    my ($host, $gwhost) = @_;

    my $state = 0;
    my $msg   = "Host offline";
    my $p     = Net::Ping->new( "tcp", 2 );

    if ( $p->ping("$host") ) {
        $state = 1;
        $msg   = "Host online";
    } elsif ($gwhost) {
        $state = 1;
        $msg   = "Host not pingable because behind a Gateway-Host";
    }
    $p->close();

    return $state, $msg;
}

#################################
# Lockfile
#
sub lockfile {
    my ($host, $group, $path) = @_;

    $path =~ s/^://g;
    $path =~ s/\s:/\+/g;
    $path =~ s/\//%/g;
    my $lockfilename = "${host}_${group}_${path}";
    my $lockfile     = "$serverconfig{path_lockfiles}/$lockfilename.lock";

    return $lockfile;
}

sub create_lockfile {
    my ($taskid, $host, $group, $path) = @_;

    my $lockfile = lockfile( $host, $group, $path );

    if ( -e $lockfile ) {
        logit( $taskid, $host, $group, "ERROR: lockfile $lockfile still exists" );
        return 0;
    } else {
        unless ( $serverconfig{dryrun} ) {
            system("echo $taskid > \"$lockfile\"") and logit( $taskid, $host, $group, "ERROR: could not create lockfile $lockfile" );
        }
        logit( $taskid, $host, $group, "Created lockfile $lockfile" );
        return 1;
    }
}

sub remove_lockfile {
    my ($taskid, $host, $group, $path) = @_;

    my $lockfile = lockfile( $host, $group, $path );
    unlink $lockfile unless $serverconfig{dryrun};
    logit( $taskid, $host, $group, "Removed lockfile $lockfile" );

    return 1;
}

sub split_lockfile_name {
    my ($lockfile) = @_;
    my ($host, $group, $path, $timestamp) = $lockfile =~ /^([\w\d-]+)_([\w\d-]+)_(.*)\.lock (.*)/;
    my $file = "${host}_${group}_${path}.lock";
    $file =~ s/\'/\\'/g;

    $path =~ s/%/\//g;
    $path =~ s/\'//g;
    $path =~ s/\+/ :/g;
    $path =~ s/^\//:\//g;

    return $host, $group, $path, $timestamp, $file;
}

sub check_lockfile {
    my ($taskid, $host, $group) = @_;

    my @lockfiles;
    my $ffr_obj = File::Find::Rule->file()
                                  ->name("${host}_${group}_*.lock")
                                  ->relative
                                  ->maxdepth(1)
                                  ->start($serverconfig{path_lockfiles});

    while ( my $lockfile = $ffr_obj->match() ) {
        push( @lockfiles, $lockfile );
    }

    logit( $taskid, $host, $group, "Check for running backup tasks" );

    if ( $#lockfiles > -1 ) {
        logit( $taskid, $host, $group, "ERROR: Wipe canceled, still ". ( $#lockfiles +1 ) ." running backup!" );
        return 0;
    }

    return 1;
}

#################################
# RemoteWrapper
#
sub remotewrapper_command {
    my ($remoteHost, $remoteCommand, $remoteArgument) = @_;
    $remoteArgument ||= '';

    my $results = `ssh -x -o IdentitiesOnly=yes -i /var/www/.ssh/remotesshwrapper root\@$remoteHost /usr/local/bin/remotesshwrapper $remoteCommand $remoteArgument 2>/dev/null`;
    my @results = split( "\n", $results );

    return @results;
}

1;
