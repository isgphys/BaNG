#$Id: Markdown.pm,v 1.3 2005/11/12 03:28:09 naoya Exp $
package Template::Plugin::Markdown;
use strict;
use base qw (Template::Plugin::Filter);
use Text::Markdown;

our $VERSION = 0.02;

sub init {
    my $self = shift;
    $self->{_DYNAMIC} = 1;
    $self->install_filter($self->{_ARGS}->[0] || 'markdown');
    $self;
}

sub filter {
    my ($self, $text, $args, $config) = @_;
    my $m = Text::Markdown->new;
    return $m->markdown($text);
}

1;

__END__

=head1 NAME

Template::Plugin::Markdown - TT plugin for Text::Markdown

=head1 SYNOPSIS

  [% USE Markdown -%]
  [% FILTER markdown %]
  #Foo
  Bar
  ---
  *Italic* blah blah
  **Bold** foo bar baz
  [%- END %]

=head1 DESCRIPTION

Template::Plugin::Markdown is a plugin for TT, which format your text with Markdown Style.

=head1 SEE ALSO

L<Template>, L<Text::Markdown>

=head1 AUTHOR

Naoya Ito E<lt>naoya@bloghackers.netE<gt>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

