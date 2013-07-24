  BaNG Configuration
======================

 Config files
--------------

All configuration files are stored in the `./etc` folder.

  * ```defaults_servers.yaml```              : common default settings for servers
  * ```defaults_hosts.yaml```                : common default settings for hosts
  * ```servers/<servername>_defaults.yaml``` : server-specific settings
  * ```groups/<groupname>.yaml```            : group-specific settings
  * ```hosts/<hostname>_<groupname>.yaml```  : host-specific settings
  * ```excludes/excludelist_<name>```        : rsync exclude list for given group or host

The default settings apply to all, but can be overriden by server-, group- and host-specific settings.


 Add a new host
----------------

To add a new host to an existing group, it's enough to copy and adapt another member's config file in the `hosts/` folder.
