package BaNG::Routes_Reporting;

use 5.010;
use strict;
use warnings;
use Dancer ':syntax';
use BaNG::Common;
use BaNG::Config;
use BaNG::Hosts;
use BaNG::Reporting;
use BaNG::Routes_Config;
use BaNG::Routes_Docs;
use BaNG::Routes_Host;
use BaNG::Routes_Restore;
use BaNG::Routes_Schedule;
use BaNG::Routes_Statistics;

prefix '/reporting';

get '/' => sub {
    get_serverconfig();

    template 'reporting-bkpreport' => {
        section           => 'reporting',
        RecentBackupsLast => bangstat_recentbackups_last(),
    };
};

1;
