  BaNG - Backup Next Generation
=================================

 Main Features
---------------

  * Perl wrapper for established rsync tool
    * supports hardlinks and btrfs snapshots
    * wipe based on daily/weekly/monthly backup rotation scheme
    * generate cron entry for scheduled backups and wipes
  * Reporting
    * Report detailed statistics to MySQL backend
    * Report via socket to Hobbit/Xymon
    * Report per email
  * Perl Dancer web frontend
    * Dashboard with most important information
    * List backup paths to facilitate restore
    * View cronjob schedule
    * View configuration parameters (default, group, host)
    * Graphs with various statistics
    * Documentation rendering markdown files


 Command Line Tool
-------------------

    ./BaNG --help                           # Display help
    ./BaNG -g <group>                       # Start backup of all hosts of given group (provided BulkAllow is set)
    ./BaNG -h <host>                        # Start backup of all groups of given host (provided BulkAllow is set)
    ./BaNG -h <host> -g <group>             # Start backup of given group and host
    ./BaNG -g <group> --wipe                # Start wipe of all hosts of given group (provided BulkAllow is set)
    ./BaNG -h <host> --wipe                 # Start wipe of all groups of given host (provided BulkAllow is set)
    ./BaNG -h <host> -g <group> --wipe      # Start wipe of given group and host
    ./BaNG -h <host> -g <group> -n          # Dry-run for testing purposes (without making backups)
    ./BaNG -h <host> -g <group> --hobbit    # Generate and send hobbit report (without making backups)
    ./BaNG --hobbit                         # Generate and send all hobbit reports (without making backups)
    ./BaNG --crontab                        # Show generated crontab entry


 Configuration
---------------

Config files:

  * ```./etc/bang_defaults.yaml```: common default settings
  * ```./etc/groups/<groupname>.yaml```: group-specific settings
  * ```./etc/hosts/<hostname>_<groupname>.yaml```: host-specific settings

The default settings apply to all, but can be overriden by group or/and host-specific settings.

To add a new host to an existing group, it's enough to copy and adapt another member's config file.
