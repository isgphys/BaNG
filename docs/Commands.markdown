BaNG Command Line Tools
=======================


BaNG: backup and wipe
---------------------

### General

```sh
BaNG --help                                   # display help with some usage examples
BaNG --version                                # show version number and help
```

### Start backups

```sh
BaNG -h <host> -g <group>                     # start backup of given host and group
BaNG -g <group>                               # start backup of all hosts of given group (provided BulkAllow is set)
BaNG -h <host>                                # start backup of all groups of given host (provided BulkAllow is set)
```

Optional arguments:

```sh
--initial                                     # needed for first backup to initially create the folder/subvolume
--missingonly                                 # backup only hosts without recent backup (e.g. machines that were offline)
--noreport                                    # do not send any reports
-t <integer>                                  # number of threads to use (default: 1)
-p <path>                                     # override path to folder containing etc/
-v | -vv | -vvv                               # verbose mode to include debugging messages of level 1-3
-n                                            # dry-run mode to simulate a backup (implies verbose)
```

### Wipe old backups

```sh
BaNG -h <host> -g <group> --wipe              # start wipe of given group and host
BaNG -g <group> --wipe                        # start wipe of all hosts of given group (provided BulkAllow is set)
BaNG -h <host> --wipe                         # start wipe of all groups of given host (provided BulkAllow is set)
```

Optional argument:

```sh
--force                                       # force wipe of too many backups (override auto_wipe_limit)
-v | -vv | -vvv                               # verbose mode to include debugging messages of level 1-3
-n                                            # dry-run mode to simulate a backup (implies verbose)
```

### Generate Xymon reports

```sh
BaNG -h <host> -g <group> --xymon             # generate and send Xymon report for given host (without making backups)
BaNG --xymon                                  # generate and send all Xymon reports (without making backups)
```

Optional argument:

```sh
-v | -vv | -vvv                               # verbose mode to include debugging messages of level 1-3
-n                                            # dry-run mode to simulate a backup (implies verbose)
```

BaNGadm: admin tasks
--------------------

```sh
BaNGadm --help                               # show this help message
BaNGadm --version                            # show version number and help
```

```sh
BaNGadm --add -h <host> -g <group>            # create a new host config
BaNGadm --add -g <group>                      # create a new group config

BaNGadm --delete -h <host> -g <group>         # delete an existing host config
BaNGadm --delete -g <group>                   # delete an existing group config

BaNGadm --initialize -h <host> -g <group>     # create target folder structure for defined host

BaNGadm --failed                              # show all failed backups
BaNGadm --failed -h <host> -g <group>         # show failed backups of defined hosts and/or group

BaNGadm --setprop list -h <host> -g <group>   # show Read-Write/Read-Only status of all snaphots
BaNGadm --setprop rw|ro -h <host> -g <group>  # set all snapshots to Read-Write/Read-Only

BaNGadm --db_dump                             # create database dump
BaNGadm --db_archive                          # move records from table statistic to statistic_archive where older than 100 days

BaNGadm --showgroups                          # show all available groups

BaNGadm --cron-create                         # generate and write cronjob file or print crontab to standard out
BaNGadm --cron-check                          # check if cronjob file / crontab up-to-date
```

Optional arguments:

```sh
-v | -vvv                                     # verbose mode to include debugging messages of level 1 and 3
-n                                            # dry-run mode to simulate a backup (implies verbose)
```

BaNG-Web: web front-end
-----------------------

```sh
service BaNG-Web start|stop|status            # start/stop starman web server for production environment
BaNG-Web                                      # start dancer web front-end in development mode on port 3000
```
