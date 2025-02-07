BaNG Configuration
==================


Config files
------------

All configuration files are stored in the local `etc/` folder. The settings are designed in a sort of hierarchy, where more specific settings can be used to override more general ones. The default settings apply to all, but can be overridden by group- and host-specific settings.

  * `defaults_hosts.yaml`                : common default settings for all hosts backed up by BaNG
  * `defaults_servers.yaml`              : common default settings for all BaNG backup servers
  * `servers/<servername>_defaults.yaml` : settings specific to a given BaNG backup server
  * `groups/<groupname>.yaml`            : common settings for a given group of hosts backed up by BaNG
  * `hosts/<hostname>_<groupname>.yaml`  : settings specific to a given host and group pair
  * `excludes/excludelist_<name>`        : rsync exclude list for given group or host


Add a new host
--------------

To add a new host to an existing group, it's enough to copy and adapt another member's config file in the `hosts/` folder.
