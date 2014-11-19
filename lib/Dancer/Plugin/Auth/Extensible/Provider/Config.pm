package Dancer::Plugin::Auth::Extensible::Provider::Config;

use 5.010;
use strict;
use warnings;

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

    my $user_details = $self->get_user_details($username) or return;

    return $password eq $user_details->{pass};
}

sub get_user_details {
    my ($self, $username) = @_;

    my ($user) = grep {
        $_->{user} eq $username
    } @{ $self->realm_settings->{users} };

    return $user;
}

sub get_user_roles {
    my ($self, $username) = @_;

    my $user_details = $self->get_user_details($username) or return;

    return $user_details->{roles};
}

1;
