package BaNG::Route_Documentation;
use Dancer ':syntax';
use BaNG::Config;
use Text::Markdown;
use Template::Plugin::Markdown;

prefix '/documentation';

get '/' => sub {
    open my $MARKDOWN, '<', "$prefix/Readme.markdown";
    my $markdown = do { local $/; <$MARKDOWN> };
    template 'documentation' => {
        section      => 'documentation',
        remotehost   => request->remote_host,
        webDancerEnv => config->{run_env},
        content      => $markdown,
    };
};
