  Advanced Topics
===================

 Multiple servers
------------------

BaNG can be run on multiple backup servers for load distribution or to support backing up OS X clients with a dedicated server. One master server can poll information from the others and display the backup status of all servers in a single BaNG web front-end. For this to work, the master must be able to connect to the other nodes via ssh. This may require adapting the `remote_command` subroutine in the `Hosts.pm` module.

Note that every backup server has its own config files and cron scheduling. This independence prevents the BaNG master to become a single point of failure.


 Authentication
----------------

The Dancer web front-end allows different means of user authentication. In our setup we bind to a LDAP server using [Dancer::Plugin::Auth::Extensible](http://search.cpan.org/dist/Dancer-Plugin-Auth-Extensible/) with a custom `LDAPphys` provider, configured through the `config.yml`. Authorization is controlled at the level of the routes by adding `require_login` to restrict to valid users, or `require_role $ldapgroup` to further restrict to members of a given group. Non-admin users will also see a navigation bar limited to the items they have access to.
