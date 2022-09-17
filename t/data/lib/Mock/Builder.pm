package Mock::Builder;

use 5.010;

use strict;
use warnings;

use Carp;

our $VERSION = '0.000_002';

sub new {
    my ( $class ) = @_;
    return bless {
	log	=> [],
    }, $class;
}

sub BAIL_OUT {
    my ( $self, @arg ) = @_;
    push @{ $self->{log} }, [ BAIL_OUT => @arg ];
    local $" = '';
    Carp::croak( "BAIL_OUT @arg" );
}


sub __clear {
    my ( $self ) = @_;
    @{ $self->{log} } = ();
    return;
}

sub __get_log {
    my ( $self ) = @_;
    return $self->{log};
}

sub cmp_ok {
    my ( $self, $got, $op, $want, $name ) = @_;
    my $code = {
	'=='	=> sub { $_[0] == $_[1] ? 1 : 0 },
    }->{$op} or $self->BAIL_OUT( "Unsupported cmp_ok operation '$op'" );
    my $rslt = $code->( $got, $want );
    push @{ $self->{log} }, [ cmp_ok => $got, $op, $want, $name, [ $rslt ] ];
    return $rslt;
}

sub is_eq {
    my ( $self, $got, $want, $name ) = @_;
    my $rslt = $got eq $want;
    push @{ $self->{log} }, [ is_eq => $got, $want, $name, [ $rslt ] ];
    return $rslt;
}

sub ok {
    my ( $self, @arg ) = @_;
    push @{ $self->{log} }, [ ok => @arg, [ $arg[0] ] ];
    return $arg[0];
}

sub skip {
    my ( $self, @arg ) = @_;
    push @{ $self->{log} }, [ skip => @arg, [] ];
    return 1;
}

sub AUTOLOAD {
    my @arg = @_;
    our $AUTOLOAD;
    ( my $name = $AUTOLOAD ) =~ s/ .* :: //smx;
    my $code = sub {
	my ( $self, @arg ) = @_;
	push @{ $self->{log} }, [ $name, @arg, [ $arg[0] ] ];
	return $arg[0];
    };
    no strict 'refs';
    *$name = $code;
    goto $code;
}

1;

__END__

=head1 NAME

t::data::lib::Mock::Builder - <<< replace boilerplate >>>

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
