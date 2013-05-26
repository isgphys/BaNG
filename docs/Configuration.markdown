  BaNG Configuration
======================

Config files:

  * ```./etc/bang_defaults.yaml```: common default settings
  * ```./etc/groups/<groupname>.yaml```: group-specific settings
  * ```./etc/hosts/<hostname>_<groupname>.yaml```: host-specific settings

The default settings apply to all, but can be overriden by group or/and host-specific settings.

To add a new host to an existing group, it's enough to copy and adapt another member's config file.
