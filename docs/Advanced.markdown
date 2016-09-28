Advanced Topics
===============


Authentication
--------------

The Dancer web front-end allows different means of user authentication. The simplest is to define user credentials inside `config.yml`. In our setup we bind to a LDAP server using [Dancer::Plugin::Auth::Extensible](http://search.cpan.org/dist/Dancer-Plugin-Auth-Extensible/) with a custom `LDAPphys` provider, also configured through the `config.yml`.

Authorization is controlled at the level of the routes by adding `require_login` to restrict to valid users, or `require_role config->{admin_role}` to further restrict to members of an admin group. Non-admin users will also see a navigation bar limited to the items they have access to.


Multiple servers
----------------

BaNG can be run on multiple backup servers for load distribution or to support backing up OS X clients with a dedicated server. One master server can poll information from the others and display the backup status of all servers in a single BaNG web front-end. For this to work, the master must be able to connect to the other nodes via ssh. This may require adapting the `remote_command` subroutine in the `RemoteCommand.pm` module.

Note that every backup server has its own config files and cron scheduling. This independence prevents the BaNG master to become a single point of failure.


NFS automounts
--------------

We export the backup partitions via NFS to the clients for easy restoring of files. The `get_automount_paths` subroutine polls NIS for the list of automount paths, provided `path_ypcat` is defined. The paths are then displayed in the `/restore` route.


Cronjobs
--------

Backup and wipe jobs have to be run on a regular basis, which is typically done using cron jobs. BaNG allows to configure the cronjobs in dedicated config files (see `etc.example/servers/bangserver_cronjobs.yaml`) and can create the corresponding file in `/etc/cron.d/`.

```sh
BaNGadm --cron-create -n    # show cronjob file / crontab for current server
BaNGadm --cron-create       # write cron file for current server to /etc/cron.d/
```

#### Cron config

    yaml-field   cron-field     allowed values
    ----------   ----------     --------------
    MIN          minute         0-59
    HOUR         hour           0-23
    DOM          day of month   1-31
    MONTH        month          1-12 (or names, see below)
    DOW          day of week    0-7 (0 or 7 is Sun, or use names)
    DESCRITPION                 Add some meta information which will shown later in the reports


Setting up SSH keys
-------------------

If you want to do the backups using ssh, you need to first generate passwordless keys,

```sh
ssh-keygen -t rsa -b 4096 -f BaNG_rsa
```

append the public `BaNG_rsa.pub` to the `authorized_keys` on the client, and include the following in the BaNG host config:

```yaml
BKP_RSYNC_RSHELL:    '/usr/bin/ssh -i /root/.ssh/BaNG_rsa'
```

to prevent the `The authenticity of host 'xyz (xxx.xx.xx.xx)' can't be established` warnings add StrictHostKeyChecking=yes to your BKP_RSYNC_RSHELL option like

```yaml
BKP_RSYNC_RSHELL:    '/usr/bin/ssh -i /root/.ssh/BaNG_rsa -o StrictHostKeyChecking=yes'
```

