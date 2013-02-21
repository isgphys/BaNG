package BaNG::Route_Host;
use Dancer ':syntax';
use BaNG::Config;

prefix '/host';

get '/' => sub {

    template 'host-search', {
        remotehost => request->remote_host,
        section    => 'host',
    };
};

get '/add' => sub {

    template 'host-edit', {
        section       => 'host_edit',
        remotehost    => request->remote_host,
        title         => 'Create new Hostconfig',
        add_entry_url => uri_for('/host/add'),
    };
};
post '/add' => sub {

    template 'host-edit', {
        section       => 'host_edit',
        remotehost    => request->remote_host,
        title         => 'Well done!',
        add_entry_url => uri_for('/host/add'),
    };
};


get '/:host' => sub {
    get_global_config();
    get_host_config(param('host'));

    template 'host', {
        section    => 'host',
        remotehost => request->remote_host,
        host       => param('host'),
        hosts      => \%hosts ,
    };
};

get '/search' => sub {

    template 'host-search' => {
        section    => 'host',
        remotehost => request->remote_host,
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
            section    => 'host',
            remotehost => request->remote_host,
            error      => 'Requested host is not available'
        };
    }
};

