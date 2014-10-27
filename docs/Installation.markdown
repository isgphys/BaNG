Installation
============

Install dependencies:

```sh
apt-get install rsync perl starman libdancer-perl libclone-perl libdatetime-perl libdbi-perl libfile-find-rule-perl libforks-perl libjson-perl liblist-moreutils-perl liblocale-gettext-perl libmail-sendmail-perl libdbd-mysql-perl libmodule-refresh-perl libtemplate-perl libyaml-tiny-perl libmime-lite-perl libnet-ldap-perl libtext-markdown-perl nis
```

Note that `libforks-perl` must be version 0.35 or later. If your distribution ships an older version, you should install the module from cpan.

```sh
git clone git@gitlab.phys.ethz.ch:dancer/bang.git /opt/BaNG
cd /opt/BaNG
chown www-data:www-data var/sessions
cp config.yml.example config.yml
cp -r etc.example etc
```

Edit `config.yml` and insert the hostname of your ldap server and its base dn.

Rename `etc/servers/bangserver_defaults.yaml` to match your server name.

Fields you typically want to change in the config files:

  * `defaults_servers.yaml`: `report_to`
  * `defaults_hosts.yaml`: `BKP_TARGET_HOST`

Adapt `etc/hosts` and `etc/groups` to your needs.

Create the MySQL database following `docs/Database.markdown` and edit `etc/bangstat_db.yaml` accordingly.

Create (BTRFS) partition and try a first backup.

The tests require a symlink to your server config:

```sh
ln -s /opt/BaNG/etc/servers/yourserver_defaults.yaml /opt/BaNG/t/etc/servers/
```

Use `prove` to run the small test suite.
