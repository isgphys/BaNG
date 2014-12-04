  BaNG Command Line Tools
===========================

 BaNG : backup and wipe
------------------------

```sh
BaNG --help                           # Display help with some usage examples
```

### Optional arguments

```sh
-v | -vv | -vvv                       # verbose mode to include debugging messages of level 1-3
-n                                    # dry-run mode to simulate a backup (implies verbose)
-t <integer>                          # number of threads to use (default: 1)
-p <path>                             # override path to folder containing etc/
```

### Start backups

```sh
BaNG -g <group>                       # Start backup of all hosts of given group (provided BulkAllow is set)
BaNG -h <host>                        # Start backup of all groups of given host (provided BulkAllow is set)
BaNG -h <host> -g <group>             # Start backup of given group and host
```

Optional arguments:

```sh
--initial                             # need for initial backup
--finallysnapshots                    # make snapshots after the hole backup stuff
--missingonly                         # backup only hosts without recent backup (e.g. machines that were offline during the night)
--noreport                            # do not send any reports
```

### Wipe old backups

```sh
BaNG -g <group> --wipe                # Start wipe of all hosts of given group (provided BulkAllow is set)
BaNG -h <host> --wipe                 # Start wipe of all groups of given host (provided BulkAllow is set)
BaNG -h <host> -g <group> --wipe      # Start wipe of given group and host
```

Optional argument:

```sh
--force                               # force wipe of too many backups (override auto_wipe_limit)
```

### Generate xymon reports

```sh
BaNG -h <host> -g <group> --xymon     # Generate and send xymon report (without making backups)
BaNG --xymon                          # Generate and send all xymon reports (without making backups)
```


 BaNGadm : admin tasks
-----------------------

```sh
BaNGadm --add -h <host> -g <group>          # create a new host config
BaNGadm --add -g <group>                    # create a new group config

BaNGadm --delete -h <hostname> -g <group>   # delete a existing host config
BaNGadm --delete -g <group>                 # delete a existing group config

BaNGadm --showgroups                        # Show all available backup groups
BaNGadm --crontab                           # generate crontab, use -n to show only the generated crontab
```


 BaNG-Web : web frontend
----------------------------

```sh
service BaNG-Web start|stop|status    # Start/Stop Starman web server for production environment
BaNG-Web.pl                           # Start Dancer web frontend in development mode on port 3000
```
