package BaNG::Routes;
use Dancer ':syntax';
use BaNG::Route_Config;
use BaNG::Route_Host;
use BaNG::Route_Statistics;
use BaNG::Route_Schedule;
#use BaNG::Authent;
use BaNG::Common;
use BaNG::Hosts;
use Auth::LDAP;

prefix undef;

get '/' => sub {
    get_fsinfo();

    template 'dashboard' => {
             'section' => 'dashboard',
             'environment' => request->remote_host(),
             'msg' => get_flash(),
             'fsinfo' => \%fsinfo,
    };
};

hook 'before' => sub {
    if (! session('logged_in') && request->path_info !~ m{^/$}) {
        if (request->path_info !~ m{^/login}){
            session 'requested_path' => request->path_info;
            debug "before:".  request->path_info;
        }
    request->path_info('/login');
    }
};

get '/login' => sub {
    template 'login', {
        #   'err' => $err,
    };
};

post '/login' => sub {
    if (checkuser(params->{user}, params->{pass})) {
        session user => params->{user};
        session 'logged_in' => true;
        debug("Logged in successfully: " . params->{user});
        set_flash('You are logged in.');
        return redirect session 'requested_path' || '/';
        redirect '/';
    } else {
        redirect '/login?failed=1';
    }
};

get '/logout' => sub {
    session->destroy;
    debug("Logged out successfully");
    set_flash('You are logged out.');
    return redirect '/';
};
