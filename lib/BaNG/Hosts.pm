package BaNG::Hosts;

use 5.010;
use BaNG::Common;
use BaNG::Config;
use BaNG::Reporting;
use Net::Ping;

use Exporter 'import';
our @EXPORT = qw(
    get_fsinfo
    chkClientConn
    createLockFile
    removeLockFile
    getLockFiles
);


sub get_fsinfo {
    my %fsinfo;
    get_server_config();
    foreach my $server ( keys %servers ) {

        my @mounts = remoteWrapperCommand($server, 'BaNG/bang_df', );

        foreach my $mount (@mounts){
            #/^([\/\w\d-]+)\s+([\w\d]+)\s+([\d]+)\s+([\d]+)\s+([\d]+)\s+([\d]+).\s+([\/\w\d-]+)$/;
            $mount =~ qr/
                        ^(?<filesystem> [\/\w\d-]+)
                        \s+(?<fstyp> [\w\d]+)
                        \s+(?<blocks> [\d]+)
                        \s+(?<used> [\d]+)
                        \s+(?<available>[\d]+)
                        \s+(?<usedper> [\d]+)
                        .\s+(?<mountpt> [\/\w\d-]+)$
            /x ;

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

sub check_fill_level {
    my ($level) = @_ ;
    my $css_class = '';

    if ( $level > 98 ){
        $css_class = "alert_red";
    } elsif ($level > 90) {
        $css_class = "alert_orange";
    } elsif ($level > 80) {
        $css_class = "alert_yellow";
    }

    return $css_class;
}

sub chkClientConn {
    my ($host, $gwhost) = @_;

    my $state = 0;
    my $msg   = "Host offline";
    my $p     = Net::Ping->new("tcp",2);

    if ($p->ping("$host")){
        $state = 1;
        $msg   = "Host online";
    }
    elsif($gwhost){
        $state = 1;
        $msg   = "Host not pingable because behind a Gateway-Host";
    }
    $p->close();

    return $state, $msg;
}

#################################
# Lockfile
#
sub LockFile {
    my ($host, $group, $path) = @_;

    $path =~ s/^://g;
    $path =~ s/\s:/\+/g;
    $path =~ s/\//%/g;
    my $lockfilename = "${host}_${group}_${path}";
    my $lockfile     = "$globalconfig{path_lockfiles}/$lockfilename.lock";

    return $lockfile;
}

sub splitLockFileName {
    my ($lockfile) = @_;
    my ($host, $group, $path) = $lockfile =~ /^([\w\d-]+)_([\w\d-]+)_(.*)\.lock/;

    $path =~ s/%/\//g;
    $path =~ s/\'//g;
    $path =~ s/\+/ :/g;
    $path =~ s/^\//:\//g;

    return $host, $group, $path;
}

sub createLockFile {
    my ($host, $group, $path) = @_;

    my $lockfile = LockFile($host, $group, $path);

    if ( -e $lockfile ) {
        logit( $host, $group, "ERROR: lockfile $lockfile still exists" );
        return 0;
    } else {
        unless ($globalconfig{dryrun}) {
            system("touch \"$lockfile\"") and logit( $host, $group, "ERROR: could not create lockfile $lockfile" );
        }
        logit( $host, $group, "Created lockfile $lockfile" );
        return 1;
    }
}

sub removeLockFile {
    my ($host, $group, $path) = @_;

    my $lockfile = LockFile($host, $group, $path);
    unlink $lockfile unless $globalconfig{dryrun};
    logit( $host, $group, "Removed lockfile $lockfile" );

    return 1;
}

sub getLockFiles {
    my @lockfiles;
    my $ffr_obj = File::Find::Rule->file()
    ->name("*.lock")
    ->relative
    ->maxdepth(1)
    ->start($globalconfig{path_lockfiles});

    while ( my $lockfile = $ffr_obj->match() ) {
        my ($host, $group, $path) = splitLockFileName($lockfile);
        my $file = {
            'host'  => $host,
            'group' => $group,
            'path'  => $path,
        };
        push( @lockfiles, $file );
    }

    return \@lockfiles;
}

#################################
# RemoteWrapper
#
sub remoteWrapperCommand {
    my ($remoteHost, $remoteCommand, $remoteArgument) = @_;
    $remoteArgument = $remoteArgument || "";

    my $results = `ssh -o IdentitiesOnly=yes -i /var/www/.ssh/remotesshwrapper root\@$remoteHost /usr/local/bin/remotesshwrapper $remoteCommand $remoteArgument`;
    my @results = split("\n", $results);

    return @results;
}

1;
