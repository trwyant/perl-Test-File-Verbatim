package Mock::HTTP;

use 5.010;

use strict;
use warnings;

use Carp;

our $VERSION = '0.000_006';

sub new {
    my ( $class ) = @_;
    return bless {}, $class;
}

sub get {
    my ( $self, $url ) = @_;
    state $canned = {
	'https://limerick.org/boat.html'	=> {
	    content	=> <<'EOD',
There was an old man in a boat,
Who said, "I'm afloat! I'm afloat!"
    When they said "No, you ain't,"
    He was ready to faint,
That unhappy old man in a boat.
EOD
	    headers	=> {
		'content-type'	=> 'text/html; charset=utf-8',
	    },
	    reason	=> 'OK',
	    status	=> 200,
	    success	=> 1,
	},
    };
    my $resp = $canned->{$url} || {
	headers	=> {
	    'content-type'	=> 'text/html; charset=utf-8', },
	reason	=> 'Not found',
	status	=> 404,
	success	=> 0,
    };
    $resp->{headers}{server} //= do {
	( my $svr = $url ) =~ s| \A [^/]+ // ||smx;
	$svr =~ s| / .* ||smx;
	$svr;
    };
    defined $resp->{content}
	and $resp->{headers}{'content-length'} //= length $resp->{content};
    $resp->{url} //= $url;
    return $resp;
}

1;

__END__

=head1 NAME

    Mock::HTTP - Mock HTTP::Tiny

=head1 SYNOPSIS

<<< replace boilerplate >>>

=head1 DESCRIPTION

<<< replace boilerplate >>>

=head1 METHODS

This class supports the following public methods:

=head1 ATTRIBUTES

This class has the following attributes:


=head1 SEE ALSO

<<< replace or remove boilerplate >>>

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Test-File-Verbatim>,
L<https://github.com/trwyant/perl-Test-File-Verbatim/issues/>, or in
electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :
