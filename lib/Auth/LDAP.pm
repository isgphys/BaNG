# Auth::LDAP extensive ldap authentification module for perl-dancer
# Added the following config to config.yml of your dancer project:
#
# auth_ldap:
#    server: 'ldaps://ldap.phys.ethz.ch'
#    user_base_dn: 'ou1=People,ou=Physik Departement,o=ethz,c=ch'
#    group_base_dn: 'ou1=Group,ou=Physik Departement,o=ethz,c=ch'
#    username_attribute: 'uid'
#    groupname_attribute: 'memberUid'
#    groups_allowed: 'isg'

package Auth::LDAP;
use Net::LDAP;
use Dancer ':syntax';

use Exporter 'import';
our @EXPORT = qw(
    checkuser
    );


sub _find_user_dn
{
    my $user = shift;
    my $user_base_dn =
        Dancer::Config::setting('auth_ldap')->{'user_base_dn'};
    my $server = Dancer::Config::setting('auth_ldap')->{'server'};

    my $ldap = Net::LDAP->new($server);

    unless($ldap)
    {
        debug "ERROR: Could not connect to server $server";
        return undef;
    }

    my $bind_result = $ldap->bind();

    unless($bind_result->code() == 0)
    {
        debug "ERROR: Could not login $user. LDAP says:\n";
        debug $bind_result->error_desc();
        return undef;
    }

    my $ldap_result = $ldap->search(
       base   => $user_base_dn,
       scope  => "sub",
       filter => "(uid=$user)",
       attrs  => ['cn']
    );

    unless($ldap_result->count() == 1)
    {
        debug "ERROR: Could not lookup user dn $user. Found "
        .$ldap_result->count().
        " entries for uid=$user";

        return undef;
    }
    debug "User $user has dn ". ($ldap_result->entries)[0]->dn();
    $ldap->unbind();
    return( $ldap_result->entries)[0]->dn();
}

sub checkuser
{
    my $user = shift || return undef;
    my $pass = shift || return undef;
    my $server = Dancer::Config::setting('auth_ldap')->{'server'};
    my $user_base_dn =
        Dancer::Config::setting('auth_ldap')->{'user_base_dn'};
    my $group_base_dn =
        Dancer::Config::setting('auth_ldap')->{'group_base_dn'}
        || Dancer::Config::setting('auth_ldap')->{'user_base_dn'};
    my $groups_allowed =
        Dancer::Config::setting('auth_ldap')->{'groups_allowed'};
    my $username_attribute =
        Dancer::Config::setting('auth_ldap')->{'username_attribute'}
        || 'CN';
    my $groupname_attribute =
        Dancer::Config::setting('auth_ldap')->{'groupname_attribute'}
        || 'member';
    my $group_members_by_dn =
        Dancer::Config::setting('auth_ldap')->{'group_members_by_dn'}
        || undef;

    unless($server && $user_base_dn)
    {
        debug "ERROR: Bad configuration for ldap_auth in config.yml";
        return undef;
    }

    my $ldap = Net::LDAP->new($server);

    unless($ldap)
    {
        debug "ERROR: Could not connect to server $server";
        return undef;
    }

    my $user_dn = _find_user_dn($user);

    unless($user_dn)
    {
        debug "ERROR: Bad user dn received. abort";
        return undef;
    }

    my $bind_result = $ldap->bind(
        $user_dn,
        password=>$pass
    );

    unless($bind_result->code() == 0)
    {
        debug "ERROR: Could not login $user. LDAP says:\n";
        debug $bind_result->error_desc();
        return undef;
    }

    # If no groups_allowed entries are defined - a successfull ldap
    # authentification is enough:
    unless($groups_allowed)
    {
        debug 'User $user GRANTED: groups_allowed undef but ldap bind ok!';
        return 1;
    }

    $groups_allowed =
        ref($groups_allowed) eq 'ARRAY' ?
        $groups_allowed :
        [$groups_allowed];

    foreach my $group (@$groups_allowed)
    {
        my $ldap_result = $ldap->search(
            base   => $group_base_dn,
            scope  => "sub",
            filter => "(name=$group)",
            attrs  => [$groupname_attribute]
        );

        unless($ldap_result->count() == 1)
        {
            debug "ERROR: Could not lookup group $group";
            next;
        }

        my $group_object = ($ldap_result->entries)[0];
        my $group_members =
            $group_object->get_value($groupname_attribute, asref => 1);
        if($group_members_by_dn)
        {
            if(grep(/^$username_attribute=$user,/, @$group_members) == 1)
            {
                $ldap->unbind();
                debug "User $user GRANTED: Is member of group $group";
                return 1;
            }
        }
        else
        {
            if(grep(/^$user$/, @$group_members) == 1)
            {
                $ldap->unbind();
                debug "User $user GRANTED: Is member of group $group";
                return 1;
            }
        }
    }
    $ldap->unbind();
    debug "User $user NOT GRANTED: Successful authenticated but not a ".
        "member of the groups allowed";
    return undef;
}

1;
