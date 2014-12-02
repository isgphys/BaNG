  Advanced Topics
===================


 Authentication
----------------

The Dancer web front-end allows different means of user authentication. The simplest is to define user credentials inside `config.yml`. In our setup we bind to a LDAP server using [Dancer::Plugin::Auth::Extensible](http://search.cpan.org/dist/Dancer-Plugin-Auth-Extensible/) with a custom `LDAPphys` provider, also configured through the `config.yml`.

Authorization is controlled at the level of the routes by adding `require_login` to restrict to valid users, or `require_role config->{admin_role}` to further restrict to members of an admin group. Non-admin users will also see a navigation bar limited to the items they have access to.


 Multiple servers
------------------

BaNG can be run on multiple backup servers for load distribution or to support backing up OS X clients with a dedicated server. One master server can poll information from the others and display the backup status of all servers in a single BaNG web front-end. For this to work, the master must be able to connect to the other nodes via ssh. This may require adapting the `remote_command` subroutine in the `Hosts.pm` module.

Note that every backup server has its own config files and cron scheduling. This independence prevents the BaNG master to become a single point of failure.


 NFS Automounts
----------------

We export the backup partitions via NFS to the clients for easy restoring of files. The `get_autmount_paths` subroutine polls NIS for the list of automount paths, provided `path_ypcat` is defined. The paths are then displayed in the `/restore` route.


 Cronjobs
----------

Backup and wipe jobs have to be run on a regular basis, which is typically done using cron jobs. BaNG allows to configure the cronjobs in dedicated config files (see `etc.example/servers/bangserver_cronjobs.yaml`) and can create the corresponding file in `/etc/cron.d/`.

```sh
BaNGadm --crontab -n    # show crontab for current server
BaNGadm --crontab       # write cron file for current server to /etc/cron.d/
```
