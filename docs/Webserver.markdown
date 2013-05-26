  BaNG Webserver
==================

 Permissions
-------------

Allow Apache to write logs and sessions to BaNG subfolders

    chmod www-data logs
    chmod www-data sessions


 Apache Config
---------------

Example configuration ```/etc/apache2/sites-enabled/bang```

    <VirtualHost *:80>
        ServerName backup.phys.ethz.ch
        ServerAlias bang.phys.ethz.ch
        ServerAlias restore.phys.ethz.ch
        DocumentRoot /opt/BaNG

        Redirect / https://backup.phys.ethz.ch

        ErrorLog  /var/log/apache2/bang_error_log
        CustomLog /var/log/apache2/bang_access_log common
    </VirtualHost>

    <VirtualHost *:443>
        ServerName backup.phys.ethz.ch
        ServerAlias bang.phys.ethz.ch
        ServerAlias restore.phys.ethz.ch
        DocumentRoot /opt/BaNG

        HostnameLookups On

        SSLEngine on
        SSLCertificateFile /etc/apache2/cert/phd-bkp-gw.crt
        SSLCertificateKeyFile /etc/apache2/cert/phd-bkp-gw.key

        SetEnv DANCER_ENVIRONMENT "production"

        <Directory /opt/BaNG>
            AllowOverride None
            Order allow,deny
            Allow from all

            AuthType Basic
            AuthName "ETH D-PHYS Account"
            AuthBasicProvider ldap
            AuthLDAPURL "ldap://ldap.phys.ethz.ch/o=ethz,c=ch"
            AuthLDAPGroupAttribute memberUid
            AuthLDAPGroupAttributeIsDN off

            Require ldap-group cn=isg,ou1=Group,ou=Physik Departement,o=ethz,c=ch
        </Directory>

        <Location />
            SetHandler perl-script
            PerlHandler Plack::Handler::Apache2
            PerlSetVar psgi_app /opt/BaNG/BaNG-Web.pl
        </Location>

        logLevel  warn
        ErrorLog  /var/log/apache2/bang_ssl_error_log
        CustomLog /var/log/apache2/bang_ssl_access_log common
    </VirtualHost>
