BaNG on Mac OS X
================

BaNG can be installed on a Mac OS X computer allowing to back up OS X clients to a native HFS+ file system for full support of extended attributes. Given that the OS X file system lacks a snapshotting feature, incremental backups are made with hardlinks using the `--link-dest` option of rsync. Note that BaNG is primarily meant for backups of user data. If you need to be able to restore a full system you should use TimeMachine instead.


Rsync command for restore
-------------------------

```sh
/opt/local/bin/rsync -axHXv --no-D --delete --rsync-path=/opt/local/bin/rsync --stats ORIGIN DESTINATION
```

Whenever possible restore only specific files or folders. If you restore the full home, all local copies of emails and other caches will have to be regenerated (as they are typically excluded from the backup).


Installation
------------

### Client-side

```sh
sudo port install rsync
```

#### Enable rsh login

  * edit `/var/root/.rhosts` and allow root logins from your BaNG server by adding `mac-bang.example.com      root`
  * create a file `/Library/LaunchDaemons/com.example.mac-bang.rshd.plist` with the following contents

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<false/>
	<key>Label</key>
	<string>com.example.mac-bang.rshd</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/libexec/rshd</string>
	</array>
	<key>SessionCreate</key>
	<true/>
	<key>Sockets</key>
	<dict>
		<key>Listeners</key>
		<dict>
			<key>SockServiceName</key>
			<string>shell</string>
		</dict>
	</dict>
	<key>inetdCompatibility</key>
	<dict>
		<key>Wait</key>
		<false/>
	</dict>
</dict>
</plist>
```

  * start the rsh daemon with `launchctl load /Library/LaunchDaemons/com.example.mac-bang.rshd.plist`

### Server-side

```sh
sudo port install rsync coreutils p5-timedate p5-file-find-rule p5-yaml-tiny p5-dbd-mysql p5-mime-lite p5-template-toolkit p5-text-diff p5-json
```

The perl `forks` package is not available through MacPorts and has to be installed for instance with `cpanm`:

```sh
curl -L http://cpanmin.us > cpanm
chmod u+x cpanm
./cpanm install forks
```

#### OS X specific BaNG configuration

The path for the `rsync` and `date` commands has to point to the MacPorts installation:

`etc/servers/macserver_defaults.yaml`

```yaml
path_date:              "/opt/local/bin/gdate"
path_rsync:             "/opt/local/bin/rsync"
```

Use hardlinks for incremental backups and also transfer extended attributes, but exclude special device files.

`etc/groups/mac-workstation.yaml`

```yaml
BKP_RSYNC_RSHELL_PATH:  "/opt/local/bin/rsync"
BKP_STORE_MODUS:        "links"
BKP_RSYNC_XATTRS:       1
BKP_RSYNC_NODEVICES:    1
```
