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
use ExtUtils::Manifest();
use File::Find ();
use HTTP::Tiny;
use List::Util 1.33 ();	# for any()
use Module::Load::Conditional ();
use Pod::Perldoc;
use Scalar::Util ();
use Storable ();
use Test::Builder;
use Text::ParseWords ();

our $VERSION = '0.000_006';

use constant REF_ARRAY		=> ref [];
use constant REF_HASH		=> ref {};
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
		cache	=> {},
		config	=> {
		    default_encoding	=> '',
		    default_fatpack	=> 0,
		    trim		=> 0,
		},
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
    my $opt = REF_HASH eq ref $arg[-1] ? pop @arg : {};
    state $valid_opt = { map { $_ => 1 } qw{ exclude } };
    my @bad_opt;
    @bad_opt = grep { ! $valid_opt->{$_} } sort keys %{ $opt }
	and $self->_bail_out( "Bad options: @bad_opt" );
    @arg
	or @arg = grep { -d } qw{ blib/arch blib/lib blib/script t eg };
    my $rslt = 1;
    foreach my $path ( map { $self->_all_verbatim_ok_expand( $opt, $_ ) } @arg ) {
	# NOTE that the following has to be done in two steps. If I just
	# tried $rslt &&= $self->file_verbatim_ok( $path ) no tests
	# would be run after the first failure, because it would
	# shortcut.
	my $ok = $self->file_verbatim_ok( $path );
	$rslt &&= $ok;
    }
    return $rslt;
}

sub _all_verbatim_ok_expand {
    my ( $self, $opt, $url ) = @_;
    ref $url
	and return $_;
    my $uri_obj = URI_CLASS->new( $url );
    my $scheme = $uri_obj->scheme() // '';
    my $code = $self->can( "_all_verbatim_ok_expand_scheme_$scheme" )
	or $self->_bail_out_scheme_unsupported( $scheme );
    return $code->( $self, $opt, $uri_obj );
}

sub _all_verbatim_ok_expand_scheme_ {
    my ( undef, undef, $uri_obj ) = @_;
    $uri_obj->path() =~ m{ (?: \A | / ) MANIFEST \z }smx
	and goto &_all_verbatim_ok_expand_scheme_manifest;
    goto &_all_verbatim_ok_expand_scheme_file;
}

sub _all_verbatim_ok_expand_scheme_file {
    my ( $self, $opt, $uri_obj ) = @_;
    $self->_diagnostic_authority_ignored( $uri_obj );
    my $path = $uri_obj->path();
    if ( -d $path ) {
	my @rslt;
	File::Find::find(
	    {
		wanted	=> sub {
		    -d
			and return;
		    $self->_all_verbatim_ok_exclude_file( $opt->{exclude} )
			and return $self->_do_test(
			skip => "$_ excluded from testing" );
		    push @rslt, $_;
		    return;
		},
		no_chdir	=> 1,
	    },
	    $_,
	);
	return @rslt;
    }
    return $path;
}

sub _all_verbatim_ok_expand_scheme_manifest {
    my ( $self, undef, $uri_obj ) = @_;	# $opt not used.
    $self->_diagnostic_authority_ignored( $uri_obj );
    return do {
	local $SIG{__WARN__} = sub {
	    $self->_bail_out( $_[0] );
	};
	sort keys %{ ExtUtils::Manifest::maniread( $uri_obj->path() ) };
    };
}

sub _all_verbatim_ok_exclude_file {
    my ( $self, $exclude ) = @_;
    defined $exclude
	or return;
    my $ref = ref $exclude;
    my $code = $self->can( "_all_verbatim_ok_exclude_file_$ref" )
	or $self->_bail_out( "Unsupported $ref ref in exclude" );
    goto $code;
}

sub _all_verbatim_ok_exclude_file_ {
    my ( undef, $exclude ) = @_;
    return $_ eq $exclude;
}

sub _all_verbatim_ok_exclude_file_ARRAY {
    my ( $self, $exclude ) = @_;
    return List::Util::any { $self->_all_verbatim_ok_exclude_file( $_ ) }
    @{ $exclude };
}

sub _all_verbatim_ok_exclude_file_CODE {
    my ( $self, $exclude ) = @_;
    return $exclude->( $self );
}

sub _all_verbatim_ok_exclude_file_HASH {
    my ( undef, $exclude ) = @_;
    return $exclude->{$_};
}

sub _all_verbatim_ok_exclude_file_Regexp {
    my ( undef, $exclude ) = @_;
    return $_ =~ $exclude;
}

sub configure_file_verbatim {
    my ( $self, @argv ) = _get_args( @_ );
    $self->_init_context();
    my $config = $self->{config};
    foreach my $path ( @argv ) {
	if ( REF_ARRAY eq ref $path ) {
	    $self->_configure_parsed( $config, @{ $path } );
	} else {
	    local $self->{cache} = $self->{cache};
	    my $fatpack = $self->_get_fatpack( $path );
	    my $fh = $self->_get_handle( $path );
	    while ( <$fh> ) {
		s/ \r $ //smx;
		$fatpack
		    and s/ \A \N{U+0020}{2} //smx;
		$self->_configure_line( $config, $_ );
	    }
	    close $fh;
	}
    }
    return;
}

sub _configure_line {
    my ( $self, $config, $line ) = @_;
    s/ \A \s+ //smx;
    $line ne ''
	and index $line, '#'
	or return;
    $line =~ s/ \s+ \z //smx;
    $self->_configure_parsed( $config, Text::ParseWords::shellwords( $line ) );
    return;
}

sub _configure_parsed {
    my ( $self, $config, @argv ) = @_;
    @argv
	or return;
    my $verb = shift @argv;
    my $code = $self->can( "_configure_verb_\L$verb" )
	or $self->_bail_out( "Configuration item $verb unknown" );
    $code->( $self, $config, @argv );
    return;
}

sub _configure_verb_encoding {
    my ( $self, $context, $encoding, $path ) = @_;
    $encoding //= '';
    if ( defined $path ) {
	if ( $context->{file_encoding}{$path} eq $encoding ) {
	    # Ignore it.
	} elsif ( $self->{cache}{$path} ) {
	    $self->_diagnostic(
		"Encoding '$encoding' ignored; $path already read" );
	} else {
	    $context->{file_encoding}{$path} = $encoding;
	}
    } else {
	$context->{default_encoding} = $encoding;
    }
    return;
}

sub _configure_verb_fatpack {
    my ( $self, $context, $fatpack, $path ) = @_;
    $fatpack = _configure_interpret_boolean( $fatpack );
    if ( defined $path ) {
	if ( not $context->{file_fatpack}{$path} xor $fatpack ) {
	    # If the Boolean value did not change, ignore it.
	} elsif ( $self->{cache}{$path} ) {
	    $self->_diagnostic(
		"Fatpack setting ignored; $path already read" );
	} else {
	    $context->{file_fatpack}{$path} = $fatpack;
	}
    } else {
	$context->{default_fatpack} = $fatpack;
    }
    return;
}

sub _configure_verb_flush {
    my ( $self, undef, @argv ) = @_;
    if ( @argv ) {
	delete $self->{cache}{$_} for @argv;
    } else {
	%{ $self->{cache} } = ();
    }
    return;
}

sub _configure_verb_trim {
    my ( undef, $context, $value ) = @_;	# Invocant unused
    $context->{trim} = _configure_interpret_boolean( $value );
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

    $self->_init_context();

    return $self->_do_test( ok	=>
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
	and $encoding = $self->{context}{file_encoding}{$path};
    $encoding //= $self->{context}{default_encoding};
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

    $self->_init_context();

    my $fh = $self->_get_handle( $path );

    -d $fh
	and return $TEST->skip( "$path is a directory" );

    -z _
	and return $TEST->skip( "$path is empty" );

    {
	no warnings qw{ utf8 };	## no critic (ProhibitNoWarnings)
	-B _
	    and return $TEST->skip( "$path is binary" );
    }

    my $context = $self->{context};
    my $fatpack = $self->_get_fatpack( $path );

    while ( <$fh> ) {
	$fatpack
	    and s/ \A \N{U+0020}{2} //smx;
	m/ \A ( ( \#\# | =for ) [ ] VERBATIM ) \b/smx
	    or next;
	s/ \r $ //smx;
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

    $self->_init_context();

    return $self->_do_test( is_eq =>
	$self->_slurp_url( $path ),
	$self->_slurp_url( $source ),
	sprintf( '%s is identical to %s',
	    ref $path || $path,
	    ref $source || $source,
	),
    );
}

sub _adjust_reason {
    my ( $self, @reason ) = @_;
    my $context = $self->{context};
    unshift @reason, 'VERBATIM ';
    exists $context->{file_name}
	and exists $context->{line}
	and push @reason, " at $context->{file_name} line $context->{line}";
    return @reason;
}

sub _bail_out {
    my ( $self, @reason ) = @_;

    @reason = $self->_adjust_reason( @reason );

    return $self->_do_test( BAIL_OUT =>
	join '', @reason );
}

sub _bail_out_not_installed {
    my ( $self, $module ) = @_;
    return $self->_bail_out( "Module $module not installed" );
}

sub _bail_out_scheme_unsupported {
    my ( $self, $scheme ) = @_;
    return $self->_bail_out( "URL scheme '$scheme:' unsupported" );
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

sub _diagnostic {
    my ( $self, @reason ) = @_;

    @reason = $self->_adjust_reason( @reason );

    return $self->_do_test( diag => join '', @reason );
}

sub _diagnostic_authority_ignored {
    my ( $self, $uri_obj ) = @_;
    my $authority;
    defined( $authority = $uri_obj->authority() )
	and $authority ne q<>
	and $self->_diagnostic( 'Authority portion ignored in ',
	    $uri_obj->as_string() );
    return;
}

# This is intended for one-off tests. The result is returned.
sub _do_test {
    my ( undef, $test, @argv ) = @_;

    # Because this gets us a pre-built object I use
    # $Test::Builder::Level (localized) to get tests reported relative
    # to the correct file and line, rather than setting the 'level'
    # attribute.
    my $TEST = __get_test_builder();
    local $Test::Builder::Level = _nest_depth();

    return $TEST->$test( @argv );
}

# For testing only. May be changed or revoked at any time. CAVEAT CODER!
sub __get_config {
    my ( $self ) = _get_args( @_ );
    return $self->{config};
}

# For testing only. May be changed or revoked at any time. CAVEAT CODER!
sub __get_context {
    my ( $self ) = _get_args( @_ );
    return $self->{context};
}

# This gets used so that we can hot-patch in a mock class for testing
# purposes.
sub __get_http_tiny {
    state $UA = HTTP::Tiny->new();
    return $UA;
}

sub _get_fatpack {
    my ( $self, $path ) = @_;
    my $config = $self->{context} || $self->{config};
    my $fatpack;
    if ( defined $path ) {
	my $name = ref $path || $path;
	$fatpack = $config->{file_fatpack}{$name};
    }
    $fatpack //= $config->{default_fatpack};
    return $fatpack;
}


sub _get_handle {
    my ( $self, $url ) = @_;

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
	or $self->_bail_out_scheme_unsupported( $scheme );
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
    $self->_diagnostic_authority_ignored( $uri_obj );
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
    $self->_diagnostic_authority_ignored( $uri_obj );
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
    $self->_diagnostic_authority_ignored( $uri_obj );
    my $module = $uri_obj->path();
    my $path = $self->_check_install( $module )
	or $self->_bail_out_not_installed( $module );
    # TODO can we get it from the web if it is not installed?
    $self->{context}{file_name} //= $uri_obj->as_string();
    return $self->_get_handle_open( $path );
}

sub _get_handle_scheme_pod {
    my ( $self, $uri_obj ) = @_;
    $self->_diagnostic_authority_ignored( $uri_obj );
    my $module = $uri_obj->path();
    my $pp = Pod::Perldoc->new();
    my @found = eval {
	open my $fh, '>', \my $text	## no critic (RequireBriefOpen)
	    or $self->_bail_out( "Failed to open SCALAR ref: $!" );
	local *STDERR = $fh;
	$pp->maybe_extend_searchpath();
	$pp->grand_search_init( [ $module ] );
    } or $self->_bail_out( "POD not found for $module" );
    return $self->_get_handle_open( $found[0] );
}

# This gets used so that we can hot-patch in a mock class for testing
# purposes.
sub __get_test_builder {
    state $TEST = Test::Builder->new();
    return $TEST;
}

sub _init_context {
    my ( $self ) = @_;
    $self->{context} = Storable::dclone( $self->{config} );
    return;
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
    $self->_init_context();
    return $self->_slurp_url( $url );
}

sub _slurp_url {
    my ( $self, $url ) = _get_args( @_ );

    my $cache = $self->{cache}{$url} ||= [];
    my $fatpack = $self->_get_fatpack( $url );

    $cache->[0] ||= do {
	my $fh = $self->_get_handle( $url );
	local $/ = undef;
	( my $text = <$fh> ) =~ s/ \r $ //smxg;
	$fatpack
	    and $text =~ s/ ^ \N{U+0020}{2} //smxg;
	$text;
    };

    my $context = $self->{context};

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

    $context->{count}++;
    defined( my $content = $self->_read_verbatim_section() )
	or $self->_bail_out( 'BEGIN not terminated' );

    my $name = "$context->{file_name} line $context->{line} verbatim block found in $module";
    my $rslt = index( $self->_slurp_url( $module ), $content ) >= 0;

    return $self->_do_test( ok => $rslt, $name );
}

sub _verbatim_CONFIGURE {
    my ( $self, $arg ) = @_;
    $arg //= '';
    my $context = $self->{context};
    if ( $arg =~ m/ \S /smx ) {
	$self->_configure_line( $context, $arg );
    } else {
	my $context = $self->{context};
	my $fh = $context->{file_handle};
	my $end_marker = "$context->{verbatim} END\n";
	my $configure_line = $.;
	while ( <$fh> ) {
	    $_ eq $end_marker
		and return 1;
	    $context->{line} = $.;
	    $self->_configure_line( $context, $_ );
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
	# The following is ALMOST the regexp given at the end of the URI
	# POD; but I needed to disallow consecutive colons to force
	# module names with colons to parse as path, not schema.
	# NOTE that this means the URI module can NOT be used to parse
	# these.
	$uri =~ m|(?:([^:/?#]+):(?!:))?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
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

This module is based directly on L<Test::Builder|Test::Builder>, and
seems to play nicely with both L<Test::More|Test::More> and
L<Test2::V0|Test2::V0>.

In general, data are specified as URLs. The authority portion of the URL
is ignored unless specifically documented otherwise. The following
schemes are recognized, some of which are distinctly non-standard:

=over

=item file:

This scheme is handled by passing the path portion of the URL to the
normal Perl file I/O machinery. Relative paths are fine, and are
interpreted as you would expect.

=item http:

This scheme is handled by L<HTTP::Tiny|HTTP:Tiny>. The authority portion
of the URL is B<not> ignored.

=item https:

This scheme is handled by L<HTTP::Tiny|HTTP:Tiny>, provided the
requisite modules are installed. The authority portion of the URL is
B<not> ignored.

=item license:

This scheme is handled by prefixing C<Software::License::> to the path portion
of the URL, and handing it to
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

B<Note> that L<Software::License|Software::License> is B<not> a
prerequisite for this module. If you wish to use the C<license:>
functionality you will need to install it separately.

=item manifest:

This scheme is recognized only by L<all_verbatim_ok()|/all_verbatim_ok>.
The specified file is read by
L<ExtUtils::Manifest::maniread()|ExtUtils::Manifest>, and the files in
the manifest are added to the list of files to be tested.

=item module:

This is handled by passing the path portion of the URL to
L<Module::Load::Conditional::check_install()|Module::Load::Conditional>.
If it can find the module, the normal Perl file I/O mechanism is used.

=item pod:

POD files are found using the mostly-undocumented
L<Pod::Perldoc|Pod::Perldoc> module, which does the heavy lifting for
the C<perldoc> program. Once found, the normal Perl file I/O mechanism
is used.

=back

Any other scheme will result in a C<BAIL_OUT>.

If no scheme is specified, it defaults to:

=over

=item file: if the file exists

=item module: if the module is installed

=item license: if the specified Software::License:: module is installed

=item otherwise file:, for the sake of error generation.

=back

As a special case, C<SCALAR> references are always handled as files.

With the exception of configurations, any data read are cached.

B<Caveat:> at the moment, the URL processing is based on a home-grown
class implementing the requisite subset of the L<URI|URI> interface.
The URL parsing is done by the regular expression given near the end of
the L<URI|URI> documentation.

=head1 SUBROUTINES

This module supports the following public subroutines. All public
subroutines are exportable, and in fact all are exported by default.

=begin comment

=head2 new

This B<UNSUPPORTED> static method instantiates a test object.

This section of POD will be uncommented and filled out when the O-O
interface becomes supported, if ever. Until then, it exists to keep
L<Test::Pod::Coverage|Test::Pod::Coverage> happy.

=end comment

=head2 all_verbatim_ok

This subroutine reads the files specified in its arguments, and tests
all text files specified therein. If no arguments are specified, the
default is C<qw{ blib/arch blib/lib blib/script eg t }>.

The arguments may be URLs, but only schemes C<file:> and C<manifest:>
are legal. If an argument has no scheme specified, the scheme will be
C<manifest:> if the last element of the path is C<'MANIFEST'>, or
C<file:> otherwise.

Each file specified is tested by
L<file_verbatim_ok()|/file_verbatim_ok>.

C<all_verbatim_ok()> returns a true value if all tests pass or skip, or
a false value if any test fails.

You can specify a hash reference as the last argument. The hash
specifies options affecting the tests generated. These are:

=over

=item exclude

This option specifies files to be excluded from the test. Possible
values are:

=over

=item * A scalar

The file with the given name is excluded.

=item * An ARRAY reference

A file is excluded if it matches any of the exclusion specifications in
the array.

=item * A CODE reference

The code will be called with the path to the file in the topic variable
(C<$_>). It will be excluded if the code returns a true value.

=item * A HASH reference

A file is excluded if the hash contains a true value for that file's
name.

=item * A Regexp reference

A file is excluded if its path name matches the given regular
expression.

=back

=back

Any other options will cause the test to BAIL_OUT.

=head2 configure_file_verbatim

 configure_file_verbatim 'xt/author/file_test_verbatim_config';
 configure_file_verbatim \'encoding utf-8';
 configure_file_verbatim [ encoding => 'utf-8' ];

This subroutine configures the test. It takes multiple arguments, each
of which can be a file name, an C<http:> or C<https:> URL, a reference
to a scalar specifying the configuration, or a reference to an array
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
specifying a C<## VERBATIM CONFIGURE> annotation. In the former case the
configuration change is global. In the latter, it is local to the file
in which the C<## VERBATIM> annotation appeared.

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

Files are read with the encoding valid at the time they are read.
Subsequent changes will not affect them. An attempt to change the
file-specific encoding of a file that has already been read will be
ignored with a diagnostic.

This configuration item is ignored for C<http:> and C<https:> URLs.
These are decoded using the information in the C<Content-Type> header,
if any.

The default is C<''>.

=item fatpack

This specifies whether files are fat packed. Fat packed files have the
leading two spaces (if present) removed from each line. This
configuration item takes either one or two arguments.

The first argument is normally interpreted as a Perl Boolean, but
case-insensitive strings C<'no'>, C<'off'>, and C<'false'> have been
special-cased to yield false values.

If a second argument is specified (and the author strongly recommends
this) it is the name of the file which is fat packed.  File names are
matched by case-sensitive string comparison, so (for example)

 fatpack yes foo/bar

will not be applied to F<./foo/bar>.

If a second argument is not specified, it specifies the setting for all
files not specified explicitly.

Files are read with the setting valid at the time they are read.
Subsequent changes will not affect them. An attempt to change the
file-specific encoding of a file that has already been read will be
ignored with a diagnostic.

The default is C<0> (i.e. false).

=item flush

This causes the cached data to be deleted. You might want to do this if
you need to re-read a file with a different encoding.

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
