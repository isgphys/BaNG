  BaNG Command Line Tools
===========================

 BaNG : backup and wipe
------------------------

    BaNG --help                           # Display help with some usage examples

### Optional arguments

    -d                                    # show debugging messages
    -n                                    # dry-run mode to simulate a backup (this implies -d)
    -t <integer>                          # number of threads to use (default: 1)
    -p <path>                             # override path to folder containing etc/

### Start backups

    BaNG -g <group>                       # Start backup of all hosts of given group (provided BulkAllow is set)
    BaNG -h <host>                        # Start backup of all groups of given host (provided BulkAllow is set)
    BaNG -h <host> -g <group>             # Start backup of given group and host

Optional argument:

    --missingonly                         # backup only hosts without recent backup (e.g. machines that were offline during the night)

### Wipe old backups

    BaNG -g <group> --wipe                # Start wipe of all hosts of given group (provided BulkAllow is set)
    BaNG -h <host> --wipe                 # Start wipe of all groups of given host (provided BulkAllow is set)
    BaNG -h <host> -g <group> --wipe      # Start wipe of given group and host

Optional argument:

    --force                               # force wipe of too many backups (override auto_wipe_limit)

### Generate Hobbit reports

    BaNG -h <host> -g <group> --hobbit    # Generate and send hobbit report (without making backups)
    BaNG --hobbit                         # Generate and send all hobbit reports (without making backups)


 BaNGadm : admin tasks
-----------------------

    BaNGadm --crontab                     # Show generated crontab entry


 BaNG-Web : web frontend
----------------------------

    service BaNG-Web start|stop|status    # Start/Stop Starman web server for production environment
    BaNG-Web.pl                           # Start Dancer web frontend in development mode on port 3000
