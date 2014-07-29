Installation
============

Install dependencies:

```sh
apt-get install rsync perl starman libdancer-perl libclone-perl libdatetime-perl libdbi-perl libfile-find-rule-perl libforks-perl libjson-perl liblist-moreutils-perl liblocale-gettext-perl libmail-sendmail-perl libmodule-refresh-perl libtemplate-perl libyaml-tiny-perl libmime-lite-perl libnet-ldap-perl libtext-markdown-perl
```


```sh
git clone bang-repo.git /opt/BaNG
cd /opt/BaNG
chown www-data:www-data var/sessions
cp -r etc.example etc
```

Edit config files, for instance the hostname of your server.
