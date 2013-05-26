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
