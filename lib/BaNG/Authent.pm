package BaNG::Authent;
use Dancer ':syntax';
use Authen::Simple::LDAP;

use Exporter 'import';
our @EXPORT = qw(
    checkuser
);

sub checkuser {
    my ($username, $password) = @_;
    my $ldap = Authen::Simple::LDAP->new(
            host    => 'ldaps://ldap.phys.ethz.ch',
            basedn  => 'ou=Physik Departement, o=ETHZ, c=CH',
            filter => '(&(uid=%s)(adminAccount=yes))',
            );

    if ( $ldap->authenticate( $username, $password ) ) {
        return 1;
    }else{
        return 0;
    }
};

1
