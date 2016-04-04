BaNG Command Line Tools
=======================


BaNG: backup and wipe
---------------------

### General

```sh
BaNG --help                                   # display help with some usage examples
```

Optional arguments:

```sh
-v | -vv | -vvv                               # verbose mode to include debugging messages of level 1-3
-n                                            # dry-run mode to simulate a backup (implies verbose)
-t <integer>                                  # number of threads to use (default: 1)
-p <path>                                     # override path to folder containing etc/
```

### Start backups

```sh
BaNG -g <group>                               # start backup of all hosts of given group (provided BulkAllow is set)
BaNG -h <host>                                # start backup of all groups of given host (provided BulkAllow is set)
BaNG -h <host> -g <group>                     # start backup of given group and host
```

Optional arguments:

```sh
--initial                                     # needed for first backup to initially create the folder/subvolume
--missingonly                                 # backup only hosts without recent backup (e.g. machines that were offline)
--noreport                                    # do not send any reports
```

### Wipe old backups

```sh
BaNG -g <group> --wipe                        # start wipe of all hosts of given group (provided BulkAllow is set)
BaNG -h <host> --wipe                         # start wipe of all groups of given host (provided BulkAllow is set)
BaNG -h <host> -g <group> --wipe              # start wipe of given group and host
```

Optional argument:

```sh
--force                                       # force wipe of too many backups (override auto_wipe_limit)
```

### Generate Xymon reports

```sh
BaNG -h <host> -g <group> --xymon             # generate and send Xymon report for given host (without making backups)
BaNG --xymon                                  # generate and send all Xymon reports (without making backups)
```


BaNGadm: admin tasks
--------------------

```sh
BaNGadm --add -h <host> -g <group>            # create a new host config
BaNGadm --add -g <group>                      # create a new group config

BaNGadm --delete -h <host> -g <group>         # delete an existing host config
BaNGadm --delete -g <group>                   # delete an existing group config

BaNGadm --setprop list -h <host> -g <group>   # show Read-Write/Read-Only status of all snaphots
BaNGadm --setprop rw|ro -h <host> -g <group>  # set all snapshots to Read-Write/Read-Only

BaNGadm --showgroups                          # show all available groups

BaNGadm --cron-create                         # generate and write cronjob file or print crontab to standard out
BaNGadm --cron-check                          # check if cronjob file / crontab up-to-date
```


BaNG-Web: web front-end
-----------------------

```sh
service BaNG-Web start|stop|status            # start/stop starman web server for production environment
BaNG-Web                                      # start dancer web front-end in development mode on port 3000
```
