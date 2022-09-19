package My::Module::Test;

use 5.010;

use strict;
use warnings;

use Exporter qw{ import };
use Test::File::Verbatim ();

our $VERSION = '0.000_004';

my @extra_exports = qw{ mock_verbatim_ok throws_verbatim_ok };

push @Test::File::Verbatim::EXPORT, @extra_exports;

# This dodge is so that Test::File::Verbatim reports errors against the
# correct statck level.

package Test::File::Verbatim;

use Test::Exception;
use Test::More 0.88;	# Because of done_testing();

use lib 't/data/lib';	# Modules referred to in test.
use Mock::Builder;	# In above directory
use Mock::HTTP;		# Ditto

{
    my $TEST;

    BEGIN {
	$TEST = Mock::Builder->new();
    }

    sub mock_verbatim_ok {
	my ( $method, @mock_arg ) = @_;

	my ( $want, $name ) = splice @mock_arg, -2, 2;

	my $code = __PACKAGE__->can( $method )
	    or do {
	    local $Test::Builder::Level = $Test::Builder::Level + 1;
	    my ( undef, $file, $line ) = caller;
	    BAIL_OUT( "sub $method not found at $file line $line" );
	};

	local *Test::File::Verbatim::__get_test_builder = sub {
	    return $TEST;
	};

	local *Test::File::Verbatim::__get_http_tiny = sub {
	    state $UA = Mock::HTTP->new();
	    return $UA;
	};

	$TEST->__clear();

	$code->( @mock_arg );

	local $Test::Builder::Level = $Test::Builder::Level + 1;

	my $rslt = is_deeply $TEST->__get_log(), $want, "$name: trace";

	$rslt or diag 'Got ', explain $TEST->__get_log();

	return $rslt;
    }

    # FIXME there is a lot of boiler plate shared between this
    # subroutine and mock_verbatim_ok.
    sub throws_verbatim_ok {
	my ( $method, @mock_arg ) = @_;

	my ( $like, $want, $name ) = splice @mock_arg, -3, 3;

	my $code = __PACKAGE__->can( $method )
	    or do {
	    local $Test::Builder::Level = $Test::Builder::Level + 1;
	    my ( undef, $file, $line ) = caller;
	    BAIL_OUT( "sub $method not found at $file line $line" );
	};

	local *Test::File::Verbatim::__get_test_builder = sub {
	    return $TEST;
	};

	local *Test::File::Verbatim::__get_http_tiny = sub {
	    state $UA = Mock::HTTP->new();
	    return $UA;
	};

	$TEST->__clear();

	local $Test::Builder::level = $Test::Builder::Level + 1;

	my $rslt = throws_ok { $code->( @mock_arg ) } $like, "$name: exception";

	my $r2 = is_deeply $TEST->__get_log(), $want, "$name: trace";

	$r2 or diag 'Got ', explain $TEST->__get_log();

	return $rslt && $r2;
    }

}


1;

__END__

=head1 NAME

My::Module::Test - <<< replace boilerplate >>>

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
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Test-Verbatim>,
L<https://github.com/trwyant/perl-Test-Verbatim/issues/>, or in
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
