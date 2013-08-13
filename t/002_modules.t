use Test::More;
use strict;
use warnings;

use lib '/opt/BaNG/lib';

# Install missing perl module
# aptitude install libclone-perl libdancer-perl libdatetime-perl libdbi-perl libfile-find-rule-perl libforks-perl libjson-perl liblist-moreutils-perl liblocale-gettext-perl libmail-sendmail-perl libmodule-refresh-perl libtemplate-perl libthread-queue-perl libyaml-tiny-perl libmime-lite-perl

require_ok 'Dancer';
require_ok 'YAML::Tiny';
require_ok 'Cwd';

use_ok 'Date::Parse';
use_ok 'DBI';
use_ok 'Exporter';
use_ok 'File::Basename';
use_ok 'File::Find::Rule';
use_ok 'forks';
use_ok 'Getopt::Long';
use_ok 'IO::Socket';
use_ok 'IPC::Open3';
use_ok 'List::MoreUtils';
use_ok 'List::Util';
use_ok 'Mail::Sendmail';
use_ok 'MIME::Lite';
use_ok 'Net::Ping';
use_ok 'POSIX';
use_ok 'Template';
use_ok 'Thread::Queue';

done_testing();
