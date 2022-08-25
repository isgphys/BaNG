requires 'DBI';
requires 'File::Find::Rule';
requires 'JSON';
requires 'MIME::Lite';
requires 'Template';
requires 'Text::Diff';
requires 'YAML::Tiny';
requires 'forks';

# Some dependencies are only required for the web app but not the backups.
# We flag them as required for development, so that the installation can be
# skipped with `carton install --deployment --without develop`.
on 'develop' => sub {
    requires 'Dancer';
    requires 'Dancer::Plugin::Auth::Extensible';
    requires 'Net::LDAP';
};
