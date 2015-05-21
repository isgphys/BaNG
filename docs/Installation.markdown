Installation
============

Install dependencies:

```sh
apt-get install perl rsh-redone-server rsh-redone-client rsync starman \
    libclone-perl libdancer-perl libdatetime-perl libdbd-mysql-perl \
    libdbi-perl libfile-find-rule-perl libforks-perl libjson-perl \
    liblist-moreutils-perl liblocale-gettext-perl libmail-sendmail-perl \
    libmime-lite-perl libmodule-refresh-perl libnet-ldap-perl \
    libtemplate-perl libyaml-tiny-perl libtext-diff-perl
```

Note that `libforks-perl` must be version 0.35 or later. If your distribution ships an older version, you should install the module from cpan.

```sh
git clone https://github.com/patschbo/BaNG.git /opt/BaNG
cd /opt/BaNG
chown www-data:www-data var/sessions
cp config.yml.example config.yml
cp -r etc.example etc
```

Edit `config.yml` and update the user credentials.

Rename `etc/servers/bangserver_defaults.yaml` to match your server name.

```sh
mv etc/servers/bangserver_defaults.yaml etc/servers/`hostname -s`_defaults.yaml
```

Fields you typically want to change in the config files:

  * `defaults_servers.yaml`: `report_to`
  * `defaults_hosts.yaml`: `BKP_TARGET_HOST` and `BKP_TARGET_PATH`

Make sure the `BKP_TARGET_PATH` folder where backups should be stored exists

```sh
mkdir -p /export/backup
```

Adapt `etc/hosts` and `etc/groups` to your needs.

Create the MySQL database following `docs/Database.markdown` and edit `etc/bangstat_db.yaml` accordingly.

Allow rsh connections from localhost for testing purposes

```sh
echo '127.0.0.1   root' > ~root/.rhosts
```

Use `prove` to run the small test suite.

Try a first backup of a client.
