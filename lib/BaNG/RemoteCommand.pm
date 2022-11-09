
package BaNG::RemoteCommand;

use 5.010;
use strict;
use warnings;
use BaNG::Config;
use Date::Parse;
use POSIX qw( floor );

use Exporter 'import';
our @EXPORT = qw(
    remote_command
);

#################################
# Remote_Command
#
sub remote_command {
    my ( $remoteHost, $remoteCommand, $remoteArgument ) = @_;
    $remoteArgument ||= '';
    $remoteHost = "localhost" if $remoteHost eq 'bangtestserver';

    my $remote_app_path = $serverconfig{remote_app} ? '' : $serverconfig{remote_app_path};
    $remote_app_path .= '/' if $remote_app_path =~ /.+[^\/]$/;

    my $results = `ssh -x -o IdentitiesOnly=yes -o ConnectTimeout=2 -i $serverconfig{remote_ssh_key} root\@$remoteHost $serverconfig{remote_app} ${remote_app_path}$remoteCommand "$remoteArgument" 2>/dev/null`;
    my @results = split( "\n", $results );

    return @results;
}

1;
