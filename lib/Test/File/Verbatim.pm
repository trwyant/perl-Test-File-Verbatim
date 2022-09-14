package Test::File::Verbatim;

use 5.010;

use strict;
use warnings;

use utf8;

=pod

=encoding utf-8

=cut

# use Carp; # Don't use this, use $self->_bail_out() instead.
use Exporter qw{ import };
use File::Find ();
use HTTP::Tiny;
use Module::Load::Conditional ();
use Scalar::Util ();
use Test::Builder;
use Text::ParseWords ();

our $VERSION = '0.000_001';

use constant REF_ARRAY		=> ref [];
use constant URI_CLASS		=> 'Test::File::Verbatim::URI';

our @EXPORT_OK = qw{
    all_verbatim_ok
    configure_file_verbatim
    file_contains_ok
    files_are_identical_ok
    file_verbatim_ok
};

our @EXPORT = @EXPORT_OK;	## no critic (ProhibitAutomaticExportation)

our %EXPORT_TAGS = (
    all		=> \@EXPORT_OK,
    default	=> \@EXPORT,
);

{
    my $test;

    sub new {
	my ( $class ) = @_;
	return ( $test = bless {
		default_encoding	=> '',
	    }, $class );
    }

    sub _get_args {
	my @args = @_;
	unless ( Scalar::Util::blessed( $args[0] ) ) {
	    $test
		or __PACKAGE__->new();
	    unshift @args, $test;
	}
	return @args;
    }
}

sub all_verbatim_ok {
    my ( $self, @arg ) = _get_args( @_ );
    @arg
	or @arg = grep { -d } qw{ blib t eg };
    my $rslt = 1;
    foreach my $path ( map { $self->_all_verbatim_ok_expand_topic() } @arg ) {
	# NOTE that the following has to be done in two steps. If I just
	# tried $rslt &&= $self->file_verbatim_ok( $path ) no tests
	# would be run after the first failure, because it would
	# shortcut.
	my $ok = $self->file_verbatim_ok( $path );
	$rslt &&= $ok;
    }
    return $rslt;
}

sub _all_verbatim_ok_expand_topic {
    ref
	and return $_;
    if ( -d ) {
	my @rslt;
	File::Find::find(
	    sub {
		-d
		    or -z _
		    or -B _
		    or push @rslt, $File::Find::name;
	    },
	    $_,
	);
	return @rslt;
    }
    return $_;
}

sub configure_file_verbatim {
    my ( $self, $path ) = _get_args( @_ );
    if ( REF_ARRAY eq ref $path ) {
	$self->_configure_parsed( @{ $path } );
    } else {
	my $fh = $self->_get_handle( $path );
	while ( <$fh> ) {
	    $self->_configure_line( $_ );
	}
	close $fh;
    }
    return;
}

sub _configure_line {
    my ( $self, $line ) = @_;
    s/ \A \s+ //smx;
    $line ne ''
	and index $line, '#'
	or return;
    $line =~ s/ \s+ \z //smx;
    $self->_configure_parsed( Text::ParseWords::shellwords( $line ) );
    return;
}

sub _configure_parsed {
    my ( $self, @argv ) = @_;
    @argv
	or return;
    my $verb = shift @argv;
    my $code = $self->can( "_configure_verb_\L$verb" )
	or $self->_bail_out( "Configuration item $verb unknown" );
    $code->( $self, @argv );
    return;
}

sub _configure_verb_encoding {
    my ( $self, $encoding, $path ) = @_;
    $encoding //= '';
    if ( defined $path ) {
	if ( $self->{file_encoding}{$path} ne $encoding ) {
	    delete $self->{cache}{$path};
	    $self->{file_encoding}{$path} = $encoding;
	}
    } else {
	if ( $self->{default_encoding} ne $encoding ) {
	    delete $self->{cache};
	    $self->{default_encoding} = $encoding;
	}
    }
    return;
}

sub _configure_verb_trim {
    my ( $self, $value ) = @_;
    $self->{context}{trim} = _configure_interpret_boolean( $value );
    return;
}

sub _configure_interpret_boolean {
    my ( $value ) = @_;
    return {
	false	=> 0,
	no	=> 0,
	off	=> 0,
    }->{"\L$value"} // !! $value;
}

sub file_contains_ok {
    my ( $self, $path, $source ) = _get_args( @_ );

    delete local $self->{context};

    # Because this gets us a pre-built object I use $Test::Builder::Level
    # (localized) to get tests reported relative to the correct file and
    # line, rather than setting the 'level' attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    return $TEST->ok(
	index(
	    $self->_slurp_url( $path ),
	    $self->_slurp_url( $source ),
	) >= 0,
	sprintf( '%s contains %s',
	    ref $path || $path,
	    ref $source || $source,
	),
    );
}

sub _file_mode {
    my ( $self, $path ) = @_;
    my $encoding;
    defined $path
	and $encoding = $self->{file_encoding}{$path};
    $encoding //= $self->{default_encoding};
    return $encoding eq '' ? '<' : "<:encoding($encoding)";
}

sub file_verbatim_ok {
    my ( $self, $path ) = _get_args( @_ );

    my $rslt = 1;

    # Because this gets us a pre-built object I use $Test::Builder::Level
    # (localized) to get tests reported relative to the correct file and
    # line, rather than setting the 'level' attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    delete local $self->{context};

    my $fh = $self->_get_handle( $path );

    if ( -B $path && ! -z _ ) {
	$TEST->skip( "$path is binary" );
	return $rslt;
    }

    my $context = $self->{context};

    while ( <$fh> ) {
	m/ \A ( ( \#\# | =for ) [ ] VERBATIM ) \b/smx
	    or next;
	$context->{verbatim} = $1;
	$context->{leader} = $2;
	$context->{line} = $.;
	chomp;
	my ( undef, undef, $sub_cmd, $arg ) = split qr< \s+ >smx, $_, 4;
	defined $sub_cmd
	    or $self->_bail_out( 'sub-command missing' );

	$context->{line} = $.;
	my $code = $self->can( "_verbatim_$sub_cmd" )
	    or $self->_bail_out( "$sub_cmd not recognized" );

	# NOTE that the following has to be done in two steps. If I just
	# tried $rslt &&= $self->file_verbatim_ok( $path ) no tests
	# would be run after the first failure, because it would
	# shortcut.
	my $ok = $code->( $self, $arg );
	$rslt &&= $ok;
    }

    if ( defined $context->{expect} ) {
	my $ok = $TEST->cmp_ok(
	    $context->{count}, '==', $context->{expect},
	    "$context->{file_name} contains expected number of verbatim blocks",
	);
	$rslt &&= $ok;
    } elsif ( ! $context->{count} ) {
	$TEST->skip( "$context->{file_name} contains no verbatim blocks" );
    }

    return $rslt;
}

sub files_are_identical_ok {
    my ( $self, $path, $source ) = _get_args( @_ );

    delete local $self->{context};

    # Because this gets us a pre-built object I use $Test::Builder::Level
    # (localized) to get tests reported relative to the correct file and
    # line, rather than setting the 'level' attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    return $TEST->is_eq(
	$self->_slurp_url( $path ),
	$self->_slurp_url( $source ),
	sprintf( '%s is identical to %s',
	    ref $path || $path,
	    ref $source || $source,
	),
    );
}

sub _bail_out {
    my ( $self, @reason ) = @_;
    my $context = $self->{context};
    unshift @reason, 'VERBATIM ';
    exists $context->{file_name}
	and exists $context->{line}
	and push @reason, " at $context->{file_name} line $context->{line}";

    # Because this gets us a pre-built object I use $Test::Builder::Level
    # (localized) to get tests reported relative to the correct file and
    # line, rather than setting the 'level' attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    local $" = '';
    $TEST->BAIL_OUT( "@reason" );
    return;	# Can't get here, but Perl::Critic does not know this.
}

sub _bail_out_not_installed {
    my ( $self, $module ) = @_;
    return $self->_bail_out( "Module $module not installed" );
}

sub _can_load {
    my ( undef, $module ) = @_;	# Invocant unused
    local $@ = undef;
    return eval {
	Module::Load::Conditional::can_load( modules => { $module => 0 } );
	1;
    };
}

sub _check_install {
    my ( undef, $module ) = @_;	# Invocant unused
    my $data = Module::Load::Conditional::check_install( module => $module )
	or return;
    return $data->{file};
}

# This gets used so that we can hot-patch in a mock class for testing
# purposes.
sub __get_http_tiny {
    state $UA = HTTP::Tiny->new();
    return $UA;
}

sub _get_handle {
    my ( $self, $url ) = @_;

    $self->_init_context();

    if ( ref $url ) {
	$self->{context}{file_name} //= ref $url;
	return $self->_get_handle_open( $url );
    }

    my $uri_obj = URI_CLASS->new( $url );

    my $scheme = $uri_obj->scheme();

    unless ( defined $scheme ) {
	local $_ = $url;
	foreach my $check (
	    [ file 	=> sub { -e } ],
	    [ module	=> sub { $self->_check_install( $_ ) } ],
	    [ license	=> sub {
		    $self->_check_install( "Software::License::$_" ) } ],
	    [ file	=> sub { 1 } ],
	) {
	    $check->[1]->()
		or next;
	    $scheme = $check->[0];
	    last;
	}
    }

    my $code = $self->can( "_get_handle_scheme_$scheme" )
	or $self->_bail_out( "URL scheme '$scheme:' unsupported" );
    return $code->( $self, $uri_obj );
}

sub _get_handle_open {
    my ( $self, $path, $mode ) = @_;

    my $name = ref $path || $path;

    $mode //= $self->_file_mode( $name );

    open my $fh, $mode, $path
	or do {
	$self->_bail_out( "Unable to open $name: $!" );
    };

    my $context = $self->{context};
    $context->{file_name} //= $name;
    $context->{file_handle} //= $fh;

    return $fh;
}

sub _get_handle_scheme_file {
    my ( $self, $uri_obj ) = @_;
    return $self->_get_handle_open( $uri_obj->path() );
}

sub _get_handle_scheme_http {
    my ( $self, $uri_obj ) = @_;

    my $url = $uri_obj->as_string();
    my $ua = __get_http_tiny();
    my $resp = $ua->get( $uri_obj->as_string() );
    $resp->{success}
	or $self->_bail_out(
	"$url $resp->{status} $resp->{reason}" );
    local $_ = $resp->{headers}{'content-type'};
    defined
	or $self->_bail_out( "$url did not return content-type" );
    m| \A text / |smx
	or $self->_bail_out( "$url Content-type $_ is not text" );
    my $mode;
    if ( m/ \b charset= ( \S+ ) /smx ) {
	$mode = "<:encoding($1)";
    } else {
	$mode = '<';
    }
    $self->{context}{file_name} //= $url;
    return $self->_get_handle_open( \$resp->{content}, $mode );
}

*_get_handle_scheme_https = \&_get_handle_scheme_http;

sub _get_handle_scheme_license {
    my ( $self, $uri_obj ) = @_;
    my $module = sprintf 'Software::License::%s', $uri_obj->path();
    $self->_can_load( $module )
	or $self->_bail_out_not_installed( $module );
    my %arg = $uri_obj->query_form();
    my $method = delete( $arg{method} ) // 'license';
    $arg{holder} //= 'Anonymous';
    my $license = $module->new( \%arg );
    my $text = $license->$method();
    $self->{context}{file_name} //= $uri_obj->as_string();
    return $self->_get_handle_open( \$text );
}

sub _get_handle_scheme_module {
    my ( $self, $uri_obj ) = @_;
    my $module = $uri_obj->path();
    my $path = $self->_check_install( $module )
	or $self->_bail_out_not_installed( $module );
    # TODO can we get it from the web if it is not installed?
    $self->{context}{file_name} //= $uri_obj->as_string();
    return $self->_get_handle_open( $path );
}

# This gets used so that we can hot-patch in a mock class for testing
# purposes.
sub __get_test_builder {
    state $TEST = Test::Builder->new();
    return $TEST;
}

sub _init_context {
    my ( $self ) = @_;
    $self->{context} ||= {
	trim	=> 0,
    };
    return $self->{context};
}

sub _nest_depth {
    my $nest = 0;
    state $ignore = { map { $_ => 1 } __PACKAGE__, qw{ DB File::Find } };
    $nest++ while $ignore->{ caller( $nest ) || '' };
    return $nest;
}

sub _read_verbatim_section {
    my ( $self ) = @_;
    my $context = $self->{context};
    my $fh = $context->{file_handle};

    my $content = '';

    my $end_marker = "$context->{verbatim} END\n";

    local $_ = undef;
    while ( <$fh> ) {
	$_ eq $end_marker
	    and return $context->{trim} ? _trim_text( $content ) : $content;
	$content .= $_;
    }

    return;
}

# This gets called as a convenience (and encapsulation violation) from
# t/verbatim.t, and so needs the argument processing.
sub __slurp {
    my ( $self, $url ) = _get_args( @_ );
    delete local $self->{context};
    return $self->_slurp_url( $url );
}

sub _slurp_url {
    my ( $self, $url ) = _get_args( @_ );

    my $cache = $self->{cache}{$url} ||= [];
    $cache->[0] ||= do {
	my $fh = $self->_get_handle( $url );
	local $/ = undef;
	<$fh>;
    };

    my $context = $self->_init_context();

    if ( $context->{trim} ) {
	$cache->[$context->{trim}] ||= _trim_text( $cache->[0] );
    }

    return $cache->[$context->{trim}];
}

sub _trim_text {
    ( local $_ ) = @_;
    s/ ^ \s+ //mxg;
    s/ \s+ $ //mxg;
    return $_;
}

sub _verbatim_BEGIN {
    my ( $self, $module ) = @_;
    my $context = $self->{context};

    # Because this gets us a pre-built object I use $Test::Builder::Level
    # (localized) to get tests reported relative to the correct file and
    # line, rather than setting the 'level' attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    $context->{count}++;
    defined( my $content = $self->_read_verbatim_section() )
	or $self->_bail_out( 'BEGIN not terminated' );

    my $name = "$context->{file_name} line $context->{line} verbatim block found in $module";
    my $rslt = index( $self->_slurp_url( $module ), $content ) >= 0;

    return $TEST->ok( $rslt, $name );
}

sub _verbatim_CONFIGURE {
    my ( $self, $arg ) = @_;
    $arg //= '';
    if ( $arg =~ m/ \S /smx ) {
	$self->_configure_line( $arg );
    } else {
	my $context = $self->{context};
	my $fh = $context->{file_handle};
	my $end_marker = "$context->{verbatim} END\n";
	my $configure_line = $.;
	while ( <$fh> ) {
	    $_ eq $end_marker
		and return 1;
	    $context->{line} = $.;
	    $self->_configure_line( $_ );
	}
	$self->{context}{line} = $configure_line;
	$self->_bail_out( 'CONFIGURE not terminated' );
    }
    return 1;
}

sub _verbatim_EXPECT {
    my ( $self, $arg ) = @_;
    my $context = $self->{context};

    ( $context->{expect} ) = split qr< \s+ >smx, $arg, 2;
    return 1;
}

package Test::File::Verbatim::URI;	## no critic (Modules::ProhibitMultiplePackages)

{
    my @parts = qw{ scheme authority path query fragment };

    sub new {
	my ( $class, $uri ) = @_;
	my %self = ( as_string => $uri );
	@self{ @parts } =
	$uri =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
	return bless \%self, $class;
    }

    foreach my $method ( @parts, qw{ as_string } ) {
	no strict 'refs';
	*$method = sub { return $_[0]->{$method} };
    }

    sub query_form {
	my ( $self ) = @_;
	return( map { split /=/, $_, 2 } split /[&;]/, $self->query() // '' );
    }

}

1;

__END__

=head1 NAME

Test::File::Verbatim - Ensure that copied-and-pasted text tracks its source.

=head1 SYNOPSIS

 use Test::More 0.88; # for done_testing.
 use Test::File::Verbatim;
 
 all_verbatim_ok;

 done_testing;

=head1 DESCRIPTION

Yes, copy-and-paste is technical debt that should be avoided.
Unfortunately sometimes it is (or at least appears to be) a necessary
evil. The purpose of this set of tests is to provide ways to mitigate
(but not eliminate) the problem by providing tests that fail when the
source changes.

=head1 SUBROUTINES

This module supports the following public subroutines. All public
subroutines are exportable, and in fact all are exported by default.

In general, data are specified as URLs. The following schemes are
recognized, some of which are distinctly non-standard:

=over

=item file:

This is handled by the stripping the leading C<'file:'> (and C<'//'> if
present), and then using the normal Perl file I/O mechanism.

=item http:

This is handled by L<HTTP::Tiny|HTTP:Tiny>.

=item https:

This is handled by L<HTTP::Tiny|HTTP:Tiny>, provided the requisite
modules are installed.

=item license:

This is handled by stripping replacing the leading C<license:> with
C<Software::License::> and handing the rest to
L<Module::Load::Conditional::can_load()|Module::Load::Conditional>. If
this fails we bail out. If it succeeds a license object is instantiated
and queried, and a reference to the result is handled by the normal file
I/O mechanism.

The query mechanism for URLs is used to specify arguments to the
operation. Required argument C<'holder'> defaults to C<'Anonymous'>.

In addition to the arguments documented in
L<Software::License|Software::License>, argument C<'method'> specifies
the C<Software::License> method used to retrieve the license. This
defaults to C<'license'>.

B<Caveat:> the argument parsing is just a regular expression, because I
wanted to keep non-core dependencies to a minimum. If this turns out to
be a problem, I might look into using something like L<URI|URI> if it is
available.

=item module:

This is handled by stripping the leading C<module:> and handing the rest
to
L<Module::Load::Conditional::check_install()|Module::Load::Conditional>.
If it can find the module, the normal file I/O mechanism is used.

=back

If a recognized scheme can not be found, the default scheme is:

=over

=item file: if the file exists

=item module: if the module is installed

=item license: if the specified Software::License:: module is installed

=item otherwise file:

=back

As a special case, C<SCALAR> references are always handled as files.

=begin comment

=head2 new

This B<UNSUPPORTED> static method instantiates a test object.

This section of POD will be uncommented and filled out when the O-O
interface becomes supported, if ever. Until then, it exists to keep
L<Test::Pod::Coverage|Test::Pod::Coverage> happy.

=end comment

=head2 all_verbatim_ok

This subroutine reads the files specified in its arguments, and tests
all text files found therein. Directories are searched recursively. If
no arguments are specified, the default is C<qw{ blib eg t }>.

The heavy lifting is done by L<file_verbatim_ok()|/file_verbatim_ok>.

This returns a true value if all tests pass or skip, and a false value
if any test fails.

=head2 configure_file_verbatim

 configure_file_verbatim 'xt/author/file_test_verbatim_config';
 configure_file_verbatim \'encoding utf-8';
 configure_file_verbatim [ encoding => 'utf-8' ];

This subroutine configures the test. It takes a single argument, which
can be a file name, an C<http:> or C<https:> URL, a reference to a
scalar specifying the configuration, or a reference to an array
containing a single configuration item name and its arguments.

See L<CONFIGURATION|/CONFIGURATION>, below for details.

=head2 files_are_identical_ok

 files_are_identical_ok $file, $source;

This subroutine tests whether the files specified by the two arguments
are identical.

This returns a true value if the test passes, and a false value if it
fails.

=head2 file_contains_ok

 file_contains_ok $file, $source

This subroutine tests whether the file specified by the first argument
contains the file specified in the second argument.

This returns a true value if the test passes, and a false value if it
fails.

=head2 file_verbatim_ok

 file_verbatim_ok $path;

This subroutine tests the given file. It is opened and read, looking for
C<VERBATIM> annotations. These must begin at the beginning of the line.
In code, they are comments of the form C<## VERBATIM>. In POD, they are
directives of the form C<=for VERBATIM>. The following documentation
assumes the comment form of the annotation:

=over

=item ## VERBATIM BEGIN source-module-or-file

This annotation marks the beginning of a block of text that comes
verbatim from the specified source. If the source does not exist, a
BAIL_OUT is generated, ending the test.

The source is read and cached. Then the file being tested is read until
a C<'## VERBATIM END'> annotation is found. A BAIL_OUT is generated if
this is not found.

If the process gets this far, a test is generated, which passes if the
verbatim block is found in the source, and fails if not.

=item ## VERBATIM END

This annotation ends a verbatim block.

=item ## VERBATIM CONFIGURE

Without any arguments, this specifies a block of configuration commands,
terminated by C<## VERBATIM END>.

With arguments, this specifies a single configuration item.

See L<CONFIGURATION|/CONFIGURATION>, below for details.

=item ## VERBATIM EXPECT number

This annotation specifies the number of verbatim blocks expected. If it
is specified, then when the file being tested is completely read, a test
is generated to determine whether the specified number of verbatim
blocks was found.

If this is specified more than once, the last-specified value is used
for the test.

=back

If no verbatim blocks are found, or if the file is binary, a skipped
test is generated. A BAIL_OUT is generated if the file can not be
opened, or if a VERBATIM annotation is found that can not be
interpreted.

This returns a true value if all tests pass or skip, and a false value
if any test fails.

=head1 CONFIGURATION

Configuration can be done either by calling
L<configure_file_verbatim()|/configure_file_verbatim> (q.v.) or by
specifying a C<## VERBATIM CONFIGURE> annotation.

Either way the specification is parsed by
L<Text::ParseWords::shellwords()|Text::ParseWords> into a configuration
item name and arguments for that item. Configuration item names are not
case-sensitive, but the arguments may be.

The following configuration items are supported:

=over

=item encoding

This specifies file encodings. It takes either one or two arguments. The
first is the encoding name (e.g. C<'utf-8'>.

If a second argument is specified it is the name of the file to which
the encoding applies. File names are matched by case-sensitive string
comparison, so (for example)

 encoding utf-8 foo/bar

will not be applied to F<./foo/bar>.

If a second argument is not specified, the encoding becomes the default
encoding for files not specified explicitly. Specifying C<''> selects
the system's default encoding (ISO-LATIN-1, or some such).

The default is C<''>.

=item trim

This specifies whether leading and trailing white space is trimmed
before comparison. The argument is normally interpreted as a Perl
Boolean, but case-insensitive strings C<'no'>, C<'off'>, and C<'false'>
have been special-cased to yield false values.

The default is C<0> -- that is, do not trim.

=back

Empty lines and lines whose first non-blank character is C<'#'> are
ignored.

=head1 SEE ALSO

L<Test::Builder>

L<Test::File::Cmp|Test::File::Cmp> by Abdul al Hazred (AAHAZRED)
compares files independently of line breaks. Files are specified by
path.

L<Test::File::Content|Test::File::Content> by Moritz Onken (PERLER)
tests files for the presence or absence of specified strings or regular
expressions. Files can be specified by directory and file name
extension.

L<Test::File::Contents|Test::File::Contents> by Kirrily Robert, David E.
Wheeler, and Αριστοτέλης Παγκαλτζής (ARISTOTLE) compares files to
strings or regular expressions, with the option of C<diff> output on
failure. Files are specified by path.

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
