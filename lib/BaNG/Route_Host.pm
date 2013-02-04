package BaNG::Route_Host;
use Dancer ':syntax';
use BaNG::Config;

prefix '/host';

get '/' => sub {

    template 'host-search', {
        section   => 'host',
    };
};

get '/add' => sub {

    template 'host-edit', {
        section   => 'host_edit',
        title     => 'Create new Hostconfig',
        add_entry_url => uri_for('/host/add'),
    };
};
post '/add' => sub {

    template 'host-edit', {
        section   => 'host_edit',
        title     => 'Well done!',
        add_entry_url => uri_for('/host/add'),
    };
};


get '/:host' => sub {
    get_global_config();
    find_hosts(param('host'));

    template 'host', {
        section   => 'host',
        host      => param('host'),
        hosts     => \%hosts ,
    };
};

get '/search' => sub {

    template 'host-search' => {
        section => 'host',
    };
};

post '/search' => sub {
    my $host = '';
    if(param('search_text') && param('search_text') =~ /[a-z0-9\-]{1,255}/i)
    {
        $host = param('search_text');
        return redirect sprintf('/host/%s', $host);
    }
    else
    {
        return template 'host' => {
            section => 'host',
            error   => 'Requested host is not available'
        };
    }
};

