package BaNG::Common;

use Dancer ':syntax';

use Exporter 'import';
our @EXPORT = qw(
    $flash
    get_flash
    set_flash
);
our $flash;

sub set_flash {
       my $message = shift;

       $flash = $message;
}

sub get_flash {

       my $msg = $flash;
       $flash = "";

       return $msg;
}

1;
