package main;

use 5.010;

use strict;
use warnings;

use Errno qw{ ENOENT };
use Module::Load::Conditional qw{ can_load };
use Test::More 0.88;	# Because of done_testing();

use lib 'inc';
use My::Module::Test;	# In above directory.

use Test::File::Verbatim;	# Must be after My::Module::Test

# NOTE that the following uses Module::Load::Conditional::can_load()
# because that hides the module from xt/author/prereq.t, and because it
# is already a prerequisite. It has to be inside an eval() because
# Test::Without::Module throws an exception if it blocks a module.
use constant HAVE_SOFTWARE_LICENSE	=> do {
    local $@ = undef;
    eval {
	can_load( modules => {
		'Software::License'	=> 0,
	    }
	);
    } || 0;
};

my $ENOENT = do {
    local $! = ENOENT;
    "$!";
};

my $LICENSE_NONE = <<'EOD';
All rights reserved.
EOD

note <<'EOD';

Test using mock object, to ensure right steps are triggered

EOD

my $TEST = Test::More->builder();	# Test::Builder object


mock_verbatim_ok file_verbatim_ok => 't/data/text/test_01.txt',
    [
	[ ok => 1, 't/data/text/test_01.txt line 1 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_01.txt line 9 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
    ], 't/data/text/test_01.txt';


mock_verbatim_ok file_verbatim_ok => 't/data/text/test_02.txt',
    [
	[ ok => 1, 't/data/text/test_02.txt line 2 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_02.txt line 10 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
	[ cmp_ok => 2, '==', 2, 't/data/text/test_02.txt contains expected number of verbatim blocks', [ 1 ] ],
    ],  't/data/text/test_02.txt';


mock_verbatim_ok file_verbatim_ok => 't/data/text/test_03.txt',
    [
	[ ok => 1, 't/data/text/test_03.txt line 1 verbatim block found in Limerick::Nantucket', [ 1 ] ],
	[ ok => 1, 't/data/text/test_03.txt line 11 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
    ],  't/data/text/test_03.txt';


mock_verbatim_ok file_verbatim_ok => 't/data/text/test_04.txt',
    [
	[ skip => 't/data/text/test_04.txt is empty', [] ],
    ],  't/data/text/test_04.txt - Empty file';


mock_verbatim_ok file_verbatim_ok => 't/data/text/test_05.txt',
    [
	[ ok => 1, 't/data/text/test_05.txt line 1 verbatim block found in https://limerick.org/boat.html', [ 1 ] ],
    ],  't/data/text/test_05.txt';


mock_verbatim_ok file_verbatim_ok => 't/data/lib/Limerick/Nantucket.pod',
    [
	[ ok => 1, 't/data/lib/Limerick/Nantucket.pod line 27 verbatim block found in Limerick::Nantucket', [ 1 ] ],
    ],  't/data/lib/Limerick/Nantucket.pod';


mock_verbatim_ok file_verbatim_ok => \<<"EOD",
## VERBATIM BEGIN pod:Limerick::Nantucket
Limerick - Grist for the Test::File::Verbatim mill
## VERBATIM END
EOD
    [
	[ ok => 1, 'SCALAR line 1 verbatim block found in pod:Limerick::Nantucket', [ 1 ] ],
    ],  'SCALAR pod: URL';


my $text_01 = Test::File::Verbatim::__slurp( 't/data/text/test_01.txt' );
mock_verbatim_ok files_are_identical_ok =>
    't/data/text/test_01.txt', 't/data/text/test_01.txt',
    [
	[ is_eq => $text_01, $text_01,
	    't/data/text/test_01.txt is identical to t/data/text/test_01.txt',
	    [ 1 ] ]
    ], 'Identical files';


SKIP: {
    HAVE_SOFTWARE_LICENSE
	or skip 'Software::Licanse not available', 1;
    mock_verbatim_ok files_are_identical_ok => \$LICENSE_NONE, 'license:None',
	[
	    [ is_eq => $LICENSE_NONE, $LICENSE_NONE,
		'SCALAR is identical to license:None', [ 1 ] ]
	], 'license:None';
}


mock_verbatim_ok file_contains_ok =>
    't/data/text/test_01.txt', 't/data/text/limerick_moebius.txt',
    [
	[ ok => 1, 't/data/text/test_01.txt contains t/data/text/limerick_moebius.txt', [ 1 ] ]
    ], 'Path contains source';


mock_verbatim_ok all_verbatim_ok => 't/data/text/MANIFEST',
    [
	[ ok => 1, 't/data/text/test_01.txt line 1 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_01.txt line 9 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_02.txt line 2 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_02.txt line 10 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
	[ cmp_ok => 2, '==', 2, 't/data/text/test_02.txt contains expected number of verbatim blocks', [ 1 ] ],
	[ ok => 1, 't/data/text/test_03.txt line 1 verbatim block found in Limerick::Nantucket', [ 1 ] ],
	[ ok => 1, 't/data/text/test_03.txt line 11 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
	[ skip => 't/data/text/test_04.txt is empty', [] ],
	[ ok => 1, 't/data/text/test_05.txt line 1 verbatim block found in https://limerick.org/boat.html', [ 1 ] ],
    ], 'all_verbatim_ok MANIFEST';


throws_verbatim_ok file_verbatim_ok => 't/data/text/missing.txt',
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT" ],
    ], 't/data/text/missing.txt';


throws_verbatim_ok file_verbatim_ok => \"## VERBATIM\n",
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => 'VERBATIM sub-command missing at SCALAR line 1' ],
    ], 'Missing VERBATIM sub-command';


throws_verbatim_ok file_verbatim_ok => \"## VERBATIM FUBAR\n",
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => 'VERBATIM FUBAR not recognized at SCALAR line 1' ],
    ], 'Invalid VERBATIM sub-command';


throws_verbatim_ok file_verbatim_ok => \"## VERBATIM BEGIN\n",
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => 'VERBATIM BEGIN not terminated at SCALAR line 1' ],
    ], 'BEGIN not terminated';


my $hashes = '##';	# To hide them from all_files_ok
throws_verbatim_ok file_verbatim_ok => \<<"EOD",
$hashes VERBATIM BEGIN t/data/text/missing.txt
$hashes VERBATIM END
EOD
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT at SCALAR line 1" ],
    ], 'file_verbatim_ok() - source not found';


throws_verbatim_ok files_are_identical_ok =>
    't/data/text/test_01.txt', 't/data/text/missing.txt',
    qr< \A BAIL_OUT \b >smx,
    [
	[ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT" ],
    ], 'files_are_identical_ok() - source not found';


note <<'EOD';

Run passing tests for real, just to be sure they pass.

EOD

{
    my $first_test = $TEST->current_test();

    file_verbatim_ok 't/data/text/test_01.txt';

    test_details( $first_test, ( '' ) x 2 );
}

{
    my $first_test = $TEST->current_test();

    file_verbatim_ok 't/data/text/test_02.txt';

    test_details( $first_test, ( '' ) x 3 );
}

{
    my $first_test = $TEST->current_test();

    file_verbatim_ok 't/data/text/test_03.txt';

    test_details( $first_test, ( '' ) x 2 );
}

{
    my $first_test = $TEST->current_test();

    file_verbatim_ok 't/data/text/test_04.txt';

    test_details( $first_test, 'skip' );
}

{
    my $first_test = $TEST->current_test();

    file_verbatim_ok 't/data/text/test_05.txt';

    test_details( $first_test, '' );
}

note <<'EOD';

all_verbatim_ok() on files t/data/text/test_0{1,2,3,4}.txt

EOD

{
    my $first_test = $TEST->current_test();

    all_verbatim_ok map { sprintf 't/data/text/test_%02d.txt', $_ } 1 .. 4;

    test_details( $first_test, ( '' ) x 7, 'skip' );
}

note <<'EOD';

all_verbatim_ok() excluding qr{t/data}

EOD

{
    my $first_test = $TEST->current_test();

    all_verbatim_ok { exclude => [ qr{ \A t/data }smx ] };

    # Would like to do the following, but it is too sensitive to stray
    # files (say, editor swap files).
    # test_details( $first_test, ( 'skip' ) x 7, '' );
}

note <<'EOD';

File is identical to itself

EOD

files_are_identical_ok 't/data/text/test_01.txt', 't/data/text/test_01.txt';

note <<'EOD';

Test with encoding utf-8

EOD

configure_file_verbatim \<<'EOD';
flush
encoding utf-8
EOD

is_deeply Test::File::Verbatim::__get_config(), {
    default_encoding	=> 'utf-8',
    default_fatpack	=> 0,
    trim		=> 0,
}, 'Configuration';

note <<'EOD';

all_verbatim_ok() on files t/data/text/test_0{1,2,3,4}.txt, utf-8

EOD

{
    my $first_test = $TEST->current_test();

    all_verbatim_ok map { sprintf 't/data/text/test_%02d.txt', $_ } 1 .. 4;

    test_details( $first_test, ( '' ) x 7, 'skip' );
}

note <<'EOD';

Check internal state after running the above tests.

EOD

{
    my $context = Test::File::Verbatim::__get_context();
    # Do not try this at home, boys and girls.
    delete $context->{file_handle};
    is_deeply Test::File::Verbatim::__get_context(), {
	default_encoding	=> 'utf-8',
	default_fatpack	=> 0,
	file_encoding	=> {},
	file_name	=> 't/data/text/test_04.txt',
	trim		=> 0,
    }, 'Leftover context';
}

note <<'EOD';

Test fatpack processing

EOD

configure_file_verbatim \<<'EOD';
flush
encoding
fatpack on SCALAR
EOD

is_deeply Test::File::Verbatim::__get_config(), {
    default_encoding	=> '',
    default_fatpack	=> 0,
    file_fatpack	=> {
	SCALAR	=> 1,
    },
    trim		=> 0,
}, 'Configuration';


{
    my $first_test = $TEST->current_test();

    file_verbatim_ok \<<'EOD';
  ## VERBATIM EXPECT 1
  ## VERBATIM BEGIN t/data/text/limerick_bright.txt
  There was a young lady named Bright
  Who could travel much faster than light.
      She set out one day
      In a relative way
  And returned the previous night.
  ## VERBATIM END
EOD

    test_details( $first_test, '' );
}

note <<'EOD';

Check internal state after running the above tests.

EOD

{
    my $context = Test::File::Verbatim::__get_context();
    # Do not try this at home, boys and girls.
    delete $context->{file_handle};
    is_deeply Test::File::Verbatim::__get_context(), {
	count		=> 1,
	default_encoding	=> '',
	default_fatpack	=> 0,
	expect		=> 1,
	file_encoding	=> {},
	file_fatpack	=> {
	    SCALAR	=> 1,
	},
	file_name	=> 'SCALAR',
	leader		=> '##',
	line		=> 2,
	trim		=> 0,
	verbatim	=> '## VERBATIM',
    }, 'Leftover context';
}

done_testing;

sub test_details {
    my ( $num, @want ) = @_;
    my $last = $TEST->current_test();
    my $count = $last - $num;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    cmp_ok $last - $num, '==', $count, "Ran $count tests"
	or return;
    my @detail = $TEST->details();
    splice @detail, 0, $num++;
    my $inx = 0;
    while ( $inx < @want ) {
	if ( $want[$inx] eq '' ) {
	    cmp_ok $detail[$inx]{type}, 'eq', $want[$inx],
		"Test $num was a normal test";
	    ok $detail[$inx]{ok},
		"Test $num was a pass";
	} else {
	    is $detail[$inx]{type}, $want[$inx],
		"Test $num was a $want[$inx]";
	}
	$inx++;
	$num++;
    }
    return;
}

1;

# ex: set textwidth=72 :
