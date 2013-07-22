package Dancer::Plugin::Auth::Extensible;

use warnings;
use strict;
use attributes;
use Carp;
use Dancer::Plugin;
use Dancer qw(:syntax);
use Scalar::Util qw(refaddr);

our $VERSION = '0.20';

my $settings = plugin_setting;

my $loginpage = $settings->{login_page} || '/login';
my $logoutpage = $settings->{logout_page} || '/logout';
my $deniedpage = $settings->{denied_page} || '/login/denied';

=head1 NAME

Dancer::Plugin::Auth::Extensible - extensible authentication framework for Dancer apps

=head1 DESCRIPTION

A user authentication and authorisation framework plugin for Dancer apps.

Makes it easy to require a user to be logged in to access certain routes,
provides role-based access control, and supports various authentication
methods/sources (config file, database, Unix system users, etc).

Designed to support multiple authentication realms and to be as extensible as
possible, and to make secure password handling easy (the base class for auth
providers makes handling C<RFC2307>-style hashed passwords really simple, so you
have no excuse for storing plain-text passwords).


=head1 SYNOPSIS

Configure the plugin to use the authentication provider class you wish to use:

  plugins:
        Auth::Extensible:
            realms:
                users:
                    provider: Example
                    ....

The configuration you provide will depend on the authentication provider module
in use.  For a simple example, see
L<Dancer::Plugin::Auth::Extensible::Provider::Config>.

Define that a user must be logged in and have the proper permissions to 
access a route:

    get '/secret' => require_role Confidant => sub { tell_secrets(); };

Define that a user must be logged in to access a route - and find out who is
logged in with the C<logged_in_user> keyword:

    get '/users' => require_login sub {
        my $user = logged_in_user;
        return "Hi there, $user->{username}";
    };

=head1 AUTHENTICATION PROVIDERS

For flexibility, this authentication framework uses simple authentication
provider classes, which implement a simple interface and do whatever is required
to authenticate a user against the chosen source of authentication.

For an example of how simple provider classes are, so you can build your own if
required or just try out this authentication framework plugin easily, 
see L<Dancer::Plugin::Auth::Extensible::Provider::Example>.

This framework supplies the following providers out-of-the-box:

=over 4

=item L<Dancer::Plugin::Auth::Extensible::Provider::Unix>

Authenticates users using system accounts on Linux/Unix type boxes

=item L<Dancer::Plugin::Auth::Extensible::Provider::Database>

Authenticates users stored in a database table

=item L<Dancer::Plugin::Auth::Extensible::Provider::Config>

Authenticates users stored in the app's config

=back

Need to write your own?  Just subclass
L<Dancer::Plugin::Auth::Extensible::Provider::Base> and implement the required
methods, and you're good to go!

=head1 CONTROLLING ACCESS TO ROUTES

Keywords are provided to check if a user is logged in / has appropriate roles.

=over

=item require_login - require the user to be logged in

    get '/dashboard' => require_login sub { .... };

If the user is not logged in, they will be redirected to the login page URL to
log in.  The default URL is C</login> - this may be changed with the
C<login_url> option.

=item require_role - require the user to have a specified role

    get '/beer' => require_role BeerDrinker => sub { ... };

Requires that the user be logged in as a user who has the specified role.  If
the user is not logged in, they will be redirected to the login page URL.  If
they are logged in, but do not have the required role, they will be redirected
to the access denied URL.

=item require_any_roles - require the user to have one of a list of roles

    get '/drink' => require_any_role [qw(BeerDrinker VodaDrinker)] => sub {
        ...
    };

Requires that the user be logged in as a user who has any one (or more) of the
roles listed.  If the user is not logged in, they will be redirected to the
login page URL.  If they are logged in, but do not have any of the specified
roles, they will be redirected to the access denied URL.

=item require_all_roles - require the user to have all roles listed

    get '/foo' => require_all_roles [qw(Foo Bar)] => sub { ... };

Requires that the user be logged in as a user who has all of the roles listed.
If the user is not logged in, they will be redirected to the login page URL.  If
they are logged in but do not have all of the specified roles, they will be
redirected to the access denied URL.

=back

=head2 Replacing the Default C< /login > and C< /login/denied > Routes

By default, the plugin adds a route to present a simple login form at that URL.
If you would rather add your own, set the C<no_default_pages> setting to a true
value, and define your own route which responds to C</login> with a login page.

If the user is logged in, but tries to access a route which requires a specific
role they don't have, they will be redirected to the "permission denied" page
URL, which defaults to C</login/denied> but may be changed using the
C<denied_page> option.

Again, by default a route is added to respond to that URL with a default page;
again, you can disable this by setting C<no_default_pages> and creating your
own.

=head2 Keywords

=over

=item require_login

Used to wrap a route which requires a user to be logged in order to access
it.

    get '/secret' => require_login sub { .... };

=cut

sub require_login {
    my $coderef = shift;
    return sub {
        if (!$coderef || ref $coderef ne 'CODE') {
            croak "Invalid require_login usage, please see docs";
        }

        my $user = logged_in_user();
        if (!$user) {
            execute_hook('login_required', $coderef);
            # TODO: see if any code executed by that hook set up a response
            return redirect uri_for($loginpage, { return_url => request->path });
        }
        return $coderef->();
    };
}

register require_login  => \&require_login;
register requires_login => \&require_login;

=item require_role

Used to wrap a route which requires a user to be logged in as a user with the
specified role in order to access it.

    get '/beer' => require_role BeerDrinker => sub { ... };

You can also provide a regular expression, if you need to match the role using a
regex - for example:

    get '/beer' => require_role qr/Drinker$/ => sub { ... };

=cut
sub require_role {
    return _build_wrapper(@_, 'single');
}

register require_role  => \&require_role;
register requires_role => \&require_role;

=item require_any_role

Used to wrap a route which requires a user to be logged in as a user with any
one (or more) of the specified roles in order to access it.

    get '/foo' => require_any_role [qw(Foo Bar)] => sub { ... };

=cut

sub require_any_role {
    return _build_wrapper(@_, 'any');
}

register require_any_role  => \&require_any_role;
register requires_any_role => \&require_any_role;

=item require_all_roles

Used to wrap a route which requires a user to be logged in as a user with all
of the roles listed in order to access it.

    get '/foo' => require_all_roles [qw(Foo Bar)] => sub { ... };

=cut

sub require_all_roles {
    return _build_wrapper(@_, 'all');
}

register require_all_roles  => \&require_all_roles;
register requires_all_roles => \&require_all_roles;


sub _build_wrapper {
    my $require_role = shift;
    my $coderef = shift;
    my $mode = shift;

    my @role_list = ref $require_role eq 'ARRAY' 
        ? @$require_role
        : $require_role;
    return sub {
        my $user = logged_in_user();
        if (!$user) {
            execute_hook('login_required', $coderef);
            # TODO: see if any code executed by that hook set up a response
            return redirect uri_for($loginpage, { return_url => request->path });
        }

        my $role_match;
        if ($mode eq 'single') {
            for (user_roles()) {
                $role_match++ and last if $_ ~~ $require_role;
            }
        } elsif ($mode eq 'any') {
            my %role_ok = map { $_ => 1 } @role_list;
            for (user_roles()) {
                $role_match++ and last if $role_ok{$_};
            }
        } elsif ($mode eq 'all') {
            $role_match++;
            for my $role (@role_list) {
                if (!user_has_role($role)) {
                    $role_match = 0;
                    last;
                }
            }
        }

        if ($role_match) {
            return $coderef->();
        }

        execute_hook('permission_denied', $coderef);
        # TODO: see if any code executed by that hook set up a response
        return redirect uri_for($deniedpage, { return_url => request->path });
    };
}


=item logged_in_user

Returns a hashref of details of the currently logged-in user, if there is one.

The details you get back will depend upon the authentication provider in use.

=cut

sub logged_in_user {
    if (my $user = session 'logged_in_user') {
        my $realm    = session 'logged_in_user_realm';
        my $provider = auth_provider($realm);
        return $provider->get_user_details($user, $realm);
    } else {
        return;
    }
}
register logged_in_user => \&logged_in_user;

=item user_has_role

Check if a user has the role named.

By default, the currently-logged-in user will be checked, so you need only name
the role you're looking for:

    if (user_has_role('BeerDrinker')) { pour_beer(); }

You can also provide the username to check; 

    if (user_has_role($user, $role)) { .... }

=cut

sub user_has_role {
    my ($username, $want_role);
    if (@_ == 2) {
        ($username, $want_role) = @_;
    } else {
        $username  = session 'logged_in_user';
        $want_role = shift;
    }

    return unless defined $username;

    my $roles = user_roles($username);

    for my $has_role (@$roles) {
        return 1 if $has_role eq $want_role;
    }

    return 0;
}
register user_has_role => \&user_has_role;

=item user_roles

Returns a list of the roles of a user.

By default, roles for the currently-logged-in user will be checked;
alternatively, you may supply a username to check.

Returns a list or arrayref depending on context.

=cut

sub user_roles {
    my ($username) = @_;
    $username = session 'logged_in_user' unless defined $username;

    my $roles = auth_provider()->get_user_roles($username);
    return unless defined $roles;
    return wantarray ? @$roles : $roles;
}
register user_roles => \&user_roles;


=item authenticate_user

Usually you'll want to let the built-in login handling code deal with
authenticating users, but in case you need to do it yourself, this keyword
accepts a username and password, and optionally a specific realm, and checks
whether the username and password are valid.

For example:

    if (authenticate_user($username, $password)) {
        ...
    }

If you are using multiple authentication realms, by default each realm will be
consulted in turn.  If you only wish to check one of them (for instance, you're
authenticating an admin user, and there's only one realm which applies to them),
you can supply the realm as an optional third parameter.

In boolean context, returns simply true or false; in list context, returns
C<($success, $realm)>.

=cut

sub authenticate_user {
    my ($username, $password, $realm) = @_;

    my @realms_to_check = $realm? ($realm) : (keys %{ $settings->{realms} });

    for my $realm (@realms_to_check) {
        debug "Attempting to authenticate $username against realm $realm";
        my $provider = auth_provider($realm);
        if ($provider->authenticate_user($username, $password)) {
            debug "$realm accepted user $username";
            return wantarray ? (1, $realm) : 1;
        }
    }

    # If we get to here, we failed to authenticate against any realm using the
    # details provided. 
    # TODO: allow providers to raise an exception if something failed, and catch
    # that and do something appropriate, rather than just treating it as a
    # failed login.
    return wantarray ? (0, undef) : 0;
}

register authenticate_user => \&authenticate_user;


=back

=head2 SAMPLE CONFIGURATION

In your application's configuation file:

    session: simple
    plugins:
        Auth::Extensible:
            # Set to 1 if you want to disable the use of roles (0 is default)
            disable_roles: 0
            
            # List each authentication realm, with the provider to use and the
            # provider-specific settings (see the documentation for the provider
            # you wish to use)
            realms:
                realm_one:
                    provider: Database
                        db_connection_name: 'foo'

B<Please note> that you B<must> have a session provider configured.  The 
authentication framework requires sessions in order to track information about 
the currently logged in user.
Please see L<Dancer::Session> for information on how to configure session 
management within your application.

=cut

# Given a realm, returns a configured and ready to use instance of the provider
# specified by that realm's config.
{
my %realm_provider;
sub auth_provider {
    my $realm = shift;

    # If no realm was provided, but we have a logged in user, use their realm:
    if (!$realm && session->{logged_in_user}) {
        $realm = session->{logged_in_user_realm};
    }

    # First, if we already have a provider for this realm, go ahead and use it:
    return $realm_provider{$realm} if exists $realm_provider{$realm};

    # OK, we need to find out what provider this realm uses, and get an instance
    # of that provider, configured with the settings from the realm.
    my $realm_settings = $settings->{realms}{$realm}
        or die "Invalid realm $realm";
    my $provider_class = $realm_settings->{provider}
        or die "No provider configured - consult documentation for "
            . __PACKAGE__;

    if ($provider_class !~ /::/) {
        $provider_class = __PACKAGE__ . "::Provider::$provider_class";
    }
    Dancer::ModuleLoader->load($provider_class)
        or die "Cannot load provider $provider_class";

    return $realm_provider{$realm} = $provider_class->new($realm_settings);
}
}

register_hook qw(login_required permission_denied);
register_plugin for_versions => [qw(1 2)];


# Given a class method name and a set of parameters, try calling that class
# method for each realm in turn, arranging for each to receive the configuration
# defined for that realm, until one returns a non-undef, then return the realm which
# succeeded and the response.
# Note: all provider class methods return a single value; if any need to return
# a list in future, this will need changing)
sub _try_realms {
    my ($method, @args);
    for my $realm (keys %{ $settings->{realms} }) {
        my $provider = auth_provider($realm);
        if (!$provider->can($method)) {
            die "Provider $provider does not provide a $method method!";
        }
        if (defined(my $result = $provider->$method(@args))) {
            return $result;
        }
    }
    return;
}

# Set up routes to serve default pages, if desired
if (!$settings->{no_default_pages}) {
    get $loginpage => sub {
        status 401;
        return _default_login_page();
    };
    get $deniedpage => sub {
        status 403;
        return _default_permission_denied_page();
    };
}

# Handle logging in...
post $loginpage => sub {
    my ($success, $realm) = authenticate_user(
        params->{username}, params->{password}
    );
    if ($success) {
        session logged_in_user => params->{username};
        session logged_in_user_realm => $realm;
        redirect params->{return_url} || '/';
    } else {
        vars->{login_failed}++;
        forward $loginpage, { login_failed => 1 }, { method => 'GET' };
    }
};

# ... and logging out.
any ['get','post'] => $logoutpage => sub {
    session->destroy;
    if (params->{return_url}) {
        redirect params->{return_url};
    } else {
        # TODO: perhaps make this more configurable, perhaps by attempting to
        # render a template first.
        return "OK, logged out successfully.";
    }
};

sub _default_permission_denied_page {
    return <<PAGE
<h1>Permission Denied</h1>

<p>
Sorry, you're not allowed to access that page.
</p>
PAGE
}

sub _default_login_page {
    my $login_fail_message = vars->{login_failed}
        ? "<p>LOGIN FAILED</p>"
        : "";
    my $return_url = params->{return_url} || '';
    return <<PAGE;
<h1>Login Required</h1>

<p>
You need to log in to continue.
</p>

$login_fail_message

<form method="post">
<label for="username">Username:</label>
<input type="text" name="username" id="username">
<br />
<label for="password">Password:</label>
<input type="password" name="password" id="password">
<br />
<input type="hidden" name="return_url" value="$return_url">
<input type="submit" value="Login">
</form>
PAGE
}
=head1 AUTHOR

David Precious, C<< <davidp at preshweb.co.uk> >>


=head1 BUGS / FEATURE REQUESTS

This is an early version; there may still be bugs present or features missing.

This is developed on GitHub - please feel free to raise issues or pull requests
against the repo at:
L<https://github.com/bigpresh/Dancer-Plugin-Auth-Extensible>



=head1 ACKNOWLEDGEMENTS

Valuable feedback on the early design of this module came from many people,
including Matt S Trout (mst), David Golden (xdg), Damien Krotkine (dams),
Daniel Perrett, and others.

Configurable login/logout URLs added by Rene (hertell)

Regex support for require_role by chenryn

=head1 LICENSE AND COPYRIGHT

Copyright 2012 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Dancer::Plugin::Auth::Extensible
