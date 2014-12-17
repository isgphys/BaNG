BaNG - Backup Next Generation
=============================

Backup tool developed and used by the [IT Services Group](http://isg.phys.ethz.ch) of the Physics Department at ETH Zurich.


Motivation
----------

A couple of years ago, our backups were made with bash scripts that would start a single *rsync* process per client to back up the data to a file system on a remote server. We used hard links to avoid that the backup space would have to increase linearly with the number of recent backups we wanted to keep. Still, because of the daily file changes, we always planned the backup space to be roughly twice as large as the productive file server.

At some point, due to the ever increasing storage volumes, the backups started to take longer and longer, and would eventually reach the critical 24 hours limit, thereby making daily backups impossible. Independently, the used *ext* and *xfs* file systems on the backup server struggled with the large number of files and hard links, especially when wiping older backups. For these reasons we decided to replan our backups from scratch.

Thus **BaNG**, our next generation backup tool, was born. It allows to start multiple *rsync* processes in parallel for higher transfer rates. If the backup server has *btrfs*, BaNG uses its snapshot feature to store several backups. Combined with the built-in compression the amount of backup space needed is greatly reduced. In addition to command line tools, BaNG has a web front-end to explore the status of the backups at a single glance, while also providing graphs to better analyze the performance and scheduling.

Since 2012 we use it productively for our daily backups of over 300TB of data across several SAN servers. However, it may still contain bugs and is primarily meant for advanced users. Please refer to the [documentation](docs/) for more details.


Main Features
-------------

  * Perl wrapper for established rsync tool
    * compatible with Linux and OS X
    * supports hard links and btrfs snapshots
    * incremental transfers, restorable from single backup
    * multiple forked processes for faster transfers
    * wipe based on daily/weekly/monthly backup rotation scheme
    * generate cron entry for scheduled backups and wipes
  * Reporting
    * Report detailed statistics to MySQL database
    * Report via socket to Xymon monitoring server
    * Report per email
  * Perl Dancer web front-end
    * User authentication and authorization
    * Dashboard with most important information
    * List backup paths to facilitate restore
    * View cron schedule of backup and wipe jobs
    * View configuration parameters
    * Create a new host or group from the web interface
    * View status reports of latest backup jobs
    * View errors in global log files
    * Graphs with various statistics
    * Swimlane graph of the backup schedule
    * Bar charts of largest backup jobs
    * Customizable menu entry for additional links
    * Documentation rendered from markdown files
  * Configurability
    * Easy and extensive configuration options
    * Configurable at several levels (host, group, server, default)
    * Based on text files in the YAML format


License
-------

> BaNG - Backup Next Generation
> Copyright 2014 Patrick Schmid & Claude Becker
>
> This program is free software: you can redistribute it and/or modify
> it under the terms of the GNU General Public License as published by
> the Free Software Foundation, either version 3 of the License, or
> (at your option) any later version.
>
> This program is distributed in the hope that it will be useful,
> but WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
> GNU General Public License for more details.
