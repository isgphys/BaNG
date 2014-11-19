package Dancer::Plugin::Auth::Extensible::Provider::LDAPphys;

use 5.010;
use strict;
use warnings;
use Net::LDAP;

my $config = Dancer::Config::setting('plugins')->{'Auth::Extensible'}->{'realms'}->{'ldap'};

sub new {
    my ($class, $realm_settings) = @_;

    my $self = {
        realm_settings => $realm_settings,
    };

    return bless $self => $class;
}

sub realm_settings {
    shift->{realm_settings} || {};
}

sub authenticate_user {
    my ($self, $username, $password) = @_;

    my $user_dn = _user_dn($username);
    return 0 unless $user_dn;

    my $ldap = Net::LDAP->new($config->{server});
    my $bind = $ldap->bind(
        $user_dn,
        password => $password,
    );
    return 0 unless $bind;
    $ldap->unbind;
    $ldap->disconnect;

    my $authenticated = 0;
    $authenticated = 1 if( $bind->code == 0 && not $bind->is_error );

    return $authenticated;
}

sub get_user_details {
    my ($self, $username) = @_;

    my $ldap = Net::LDAP->new($config->{server});
    my $bind = $ldap->bind();

    my $ldap_result = $ldap->search(
       base   => $config->{base_dn},
       scope  => "sub",
       filter => "(uid=$username)",
       attrs  => ['cn'],
    );
    $ldap->unbind;
    $ldap->disconnect;

    return {} unless $ldap_result->count == 1;

    my $user_object  = ($ldap_result->entries)[0];
    my %user_details = (
        dn => $user_object->dn(),
        cn => ($user_object->get_value('cn'))[0],
    );

    return \%user_details;
}

sub get_user_roles {
    my ($self, $username) = @_;

    my @user_groups = _user_groups($username);

    return \@user_groups;
}

sub _user_dn {
    my ($username) = @_;

    return get_user_details('', $username)->{dn} || '';
}

sub _user_fullname {
    my ($username) = @_;

    return get_user_details('', $username)->{cn} || '';
}

sub _user_groups {
    my ($username) = @_;

    my $ldap = Net::LDAP->new($config->{server});
    my $bind = $ldap->bind();

    my $ldap_result = $ldap->search(
        base   => $config->{base_dn},
        scope  => 'sub',
        filter => $config->{group_filter},
        attrs  => ['cn', 'memberUid'],
    );
    $ldap->unbind;
    $ldap->disconnect;

    my @user_groups = ();
    foreach my $group ($ldap_result->entries) {
        my $has_members   = $group->get_value('memberUid');
        my @group_members = @{ $group->get_value( 'memberUid', asref => 1 ) } if $has_members;
        if ( grep { $_ eq $username } @group_members ) {
            my $groupname = ($group->get_value('cn'))[0];
            push( @user_groups, $groupname );
        }
    }

    return sort @user_groups;
}

sub _group_members {
    my ($group) = @_;

    my $ldap = Net::LDAP->new($config->{server});
    my $bind = $ldap->bind();

    my $ldap_result = $ldap->search(
        base   => $config->{base_dn},
        scope  => 'sub',
        filter => "(name=$group)",
        attrs  => ['memberUid'],
    );
    $ldap->unbind;
    $ldap->disconnect;

    my $group_object  = ($ldap_result->entries)[0];
    my @group_members = @{ $group_object->get_value( 'memberUid', asref => 1 ) } if $group_object;

    return @group_members;
}

1;
