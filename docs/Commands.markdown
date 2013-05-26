  BaNG Command Line Tools
===========================

 BaNG : backup and wipe
------------------------

    BaNG --help                           # Display help

### Start backups

    BaNG -g <group>                       # Start backup of all hosts of given group (provided BulkAllow is set)
    BaNG -h <host>                        # Start backup of all groups of given host (provided BulkAllow is set)
    BaNG -h <host> -g <group>             # Start backup of given group and host
    BaNG -h <host> -g <group> -n          # Dry-run for testing purposes (without making backups)

### Wipe old backups

    BaNG -g <group> --wipe                # Start wipe of all hosts of given group (provided BulkAllow is set)
    BaNG -h <host> --wipe                 # Start wipe of all groups of given host (provided BulkAllow is set)
    BaNG -h <host> -g <group> --wipe      # Start wipe of given group and host

### Generate Hobbit reports

    BaNG -h <host> -g <group> --hobbit    # Generate and send hobbit report (without making backups)
    BaNG --hobbit                         # Generate and send all hobbit reports (without making backups)


 BaNGadm : admin tasks
-----------------------

    BaNGadm --crontab                     # Show generated crontab entry


 BaNG-Web.pl : web frontend
----------------------------

    BaNG-Web.pl                           # Start Dancer web frontend in development mode on port 3000
