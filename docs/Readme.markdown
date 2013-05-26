  BaNG - Backup Next Generation
=================================

Backup tool developed by the [IT Services Group](http://isg.phys.ethz.ch) of the Physics Department at ETH Zurich.


 Main Features
---------------

  * Perl wrapper for established rsync tool
    * compatible with Linux and OS X
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


 Authors
---------

Patrick Schmid (schmid@phys.ethz.ch) & Claude Becker (becker@phys.ethz.ch)


 License
---------

GNU General Public License version 3 or later.
