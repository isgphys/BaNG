package BaNG::Hosts;
use Dancer ':syntax';
use File::Find::Rule;

use Exporter 'import';
our @EXPORT = qw(
    find_enabled_hosts
);

sub find_enabled_hosts {
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

1;
