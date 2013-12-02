  BaNG on Mac OS X
====================

 Rsync command for restore
---------------------------

    /opt/local/bin/rsync -axHXv --no-D --delete --rsync-path=/opt/local/bin/rsync --stats ORIGIN DESTINATION

Whenever possible restore only specific files or folders. If you restore the full home, all local copies of emails and other caches will have to be regenerated (as they are excluded from the backup).

 Requirements
--------------

### Server-side

    macports install rsync core-utils

### Client-side

    macports install rsync

#### Enable rsh login

  * edit `/var/root/.rhosts` and add `afp.phys.ethz.ch      root`
  * edit `/System/Library/LaunchDaemons/shell.plist` and set disable to false
  * `launchctl load /System/Library/LaunchDaemons/shell.plist`
  * `launchctl start com.apple.rshd`

NB: On our Managed Workstations the required changes are automatically deployed with Munki.

### BaNG configuration

`etc/servers/macserver_defaults.yaml`

    path_date:          /opt/local/bin/gdate
    path_rsync:         /opt/local/bin/rsync

`etc/groups/mac-workstation.yaml`

    BKP_RSYNC_RSHELL_PATH:  "/opt/local/bin/rsync"
    BKP_STORE_MODUS:        "links"
    BKP_RSYNC_XATTRS:       1
    BKP_RSYNC_NODEVICES:    1
