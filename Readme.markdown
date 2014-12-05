BaNG - Backup Next Generation
=============================

Backup tool developed by the [IT Services Group](http://isg.phys.ethz.ch) of the Physics Department at ETH Zurich.


Main Features
-------------

  * Perl wrapper for established rsync tool
    * compatible with Linux and OS X
    * supports hardlinks and btrfs snapshots
    * wipe based on daily/weekly/monthly backup rotation scheme
    * generate cron entry for scheduled backups and wipes
  * Reporting
    * Report detailed statistics to MySQL backend
    * Report via socket to Xymon monitoring server
    * Report per email
  * Perl Dancer web frontend
    * Dashboard with most important information
    * List backup paths to facilitate restore
    * View cronjob schedule
    * View configuration parameters (default, group, host)
    * Graphs with various statistics
    * Documentation rendering markdown files


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
