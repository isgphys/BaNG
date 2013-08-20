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
    getlockfiles
);

sub get_fsinfo {
    my %fsinfo;
    foreach my $server ( keys %servers ) {

        my @mounts = remotewrapper_command( $server, 'BaNG/bang_df' );

        foreach my $mount (@mounts) {
            $mount =~ qr{
                        ^(?<filesystem> [\/\w\d-]+)
                        \s+(?<fstyp> [\w\d]+)
                        \s+(?<blocks> [\d]+)
                        \s+(?<used> [\d]+)
                        \s+(?<available>[\d]+)
                        \s+(?<usedper> [\d]+)
                        .\s+(?<mountpt> [\/\w\d-]+)$
            }x;

            $fsinfo{$server}{$+{mountpt}} = {
                'filesystem' => $+{filesystem},
                'mount'      => $+{mountpt},
                'fstyp'      => $+{fstyp},
                'blocks'     => num2human($+{blocks}),
                'used'       => num2human($+{used}*1024,1024),
                'available'  => num2human($+{available}*1024,1024),
                'used_per'   => $+{usedper},
                'css_class'  => check_fill_level($+{usedper}),
            };
        }
    }

    return \%fsinfo;
}

sub get_lockfiles {
    my %lockfiles;
    foreach my $server ( keys %servers ) {

        my @lockfiles = remotewrapper_command( $server, 'BaNG/bang_getlockfile', $serverconfig{path_lockfiles} );

        foreach my $lockfile ( @lockfiles  ) {
            my ($host, $group, $path) = split_lockfile_name($lockfile);
            $lockfiles{$server}{"$host-$group-$path"} = {
                'host'  => $host,
                'group' => $group,
                'path'  => $path,
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

sub split_lockfile_name {
    my ($lockfile) = @_;
    my ($host, $group, $path) = $lockfile =~ /^([\w\d-]+)_([\w\d-]+)_(.*)\.lock/;

    $path =~ s/%/\//g;
    $path =~ s/\'//g;
    $path =~ s/\+/ :/g;
    $path =~ s/^\//:\//g;

    return $host, $group, $path;
}

sub create_lockfile {
    my ($host, $group, $path) = @_;

    my $lockfile = lockfile( $host, $group, $path );

    if ( -e $lockfile ) {
        logit( $host, $group, "ERROR: lockfile $lockfile still exists" );
        return 0;
    } else {
        unless ( $serverconfig{dryrun} ) {
            system("touch \"$lockfile\"") and logit( $host, $group, "ERROR: could not create lockfile $lockfile" );
        }
        logit( $host, $group, "Created lockfile $lockfile" );
        return 1;
    }
}

sub remove_lockfile {
    my ($host, $group, $path) = @_;

    my $lockfile = lockfile( $host, $group, $path );
    unlink $lockfile unless $serverconfig{dryrun};
    logit( $host, $group, "Removed lockfile $lockfile" );

    return 1;
}

#################################
# RemoteWrapper
#
sub remotewrapper_command {
    my ($remoteHost, $remoteCommand, $remoteArgument) = @_;
    $remoteArgument ||= '';

    my $results = `ssh -o IdentitiesOnly=yes -i /var/www/.ssh/remotesshwrapper root\@$remoteHost /usr/local/bin/remotesshwrapper $remoteCommand $remoteArgument 2>/dev/null`;
    my @results = split( "\n", $results );

    return @results;
}

1;
