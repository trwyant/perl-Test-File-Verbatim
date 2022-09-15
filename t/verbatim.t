package main;

use 5.010;

use strict;
use warnings;

use Errno qw{ ENOENT };
use Test::Exception;
use Test::More 0.88;	# Because of done_testing();
use Test::File::Verbatim;

use lib 't/data/lib';	# Modules referred to in test.
use Mock::Builder;	# In above directory
use Mock::HTTP;		# Ditto

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

{
    my $TEST = Mock::Builder->new();

    local *Test::File::Verbatim::__get_test_builder = sub {
	return $TEST;
    };

    local *Test::File::Verbatim::__get_http_tiny = sub {
	state $UA = Mock::HTTP->new();
	return $UA;
    };

    file_verbatim_ok 't/data/text/test_01.txt';

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 't/data/text/test_01.txt line 1 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_01.txt line 9 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ]
    ], 't/data/text/test_01.txt: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok 't/data/text/test_02.txt';

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 't/data/text/test_02.txt line 2 verbatim block found in t/data/text/limerick_bright.txt', [ 1 ] ],
	[ ok => 1, 't/data/text/test_02.txt line 10 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
	[ cmp_ok => 2, '==', 2, 't/data/text/test_02.txt contains expected number of verbatim blocks', [ 1 ] ],
    ],  't/data/text/test_02.txt: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok 't/data/text/test_03.txt';

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 't/data/text/test_03.txt line 1 verbatim block found in Limerick', [ 1 ] ],
	[ ok => 1, 't/data/text/test_03.txt line 11 verbatim block found in t/data/text/limerick_moebius.txt', [ 1 ] ],
    ],  't/data/text/test_03.txt: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok 't/data/text/test_04.txt';

    is_deeply $TEST->__get_log(),
    [
	[ skip => 't/data/text/test_04.txt contains no verbatim blocks', [] ],
    ],  't/data/text/test_04.txt - Empty file: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok 't/data/text/test_05.txt';

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 't/data/text/test_05.txt line 1 verbatim block found in https://limerick.org/boat.html', [ 1 ] ],
    ],  't/data/text/test_05.txt: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok 't/data/lib/Limerick.pod';

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 't/data/lib/Limerick.pod line 27 verbatim block found in Limerick', [ 1 ] ],
    ],  't/data/lib/Limerick.pod: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    file_verbatim_ok \<<'EOD';
## VERBATIM BEGIN pod:Limerick
Limerick - Grist for the Test::File::Verbatim mill
## VERBATIM END
EOD

    is_deeply $TEST->__get_log(),
    [
	[ ok => 1, 'SCALAR line 1 verbatim block found in pod:Limerick', [ 1 ] ],
    ],  'SCALAR pod: URL: trace'
	or diag 'Got ', explain $TEST->__get_log();



    $TEST->__clear();

    my $text_01 = Test::File::Verbatim::__slurp( 't/data/text/test_01.txt' );
    files_are_identical_ok 't/data/text/test_01.txt', 't/data/text/test_01.txt';

    is_deeply $TEST->__get_log(),
	[
	    [ is_eq => $text_01, $text_01, 't/data/text/test_01.txt is identical to t/data/text/test_01.txt', [ 1 ] ]
	], 'Identical files: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    files_are_identical_ok \$LICENSE_NONE, 'license:None';

    is_deeply $TEST->__get_log(),
	[
	    [ is_eq => $LICENSE_NONE, $LICENSE_NONE, 'SCALAR is identical to license:None', [ 1 ] ]
	], 'license:None: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    file_contains_ok 't/data/text/test_01.txt', 't/data/text/limerick_moebius.txt';

    is_deeply $TEST->__get_log(),
	[
	    [ ok => 1, 't/data/text/test_01.txt contains t/data/text/limerick_moebius.txt', [ 1 ] ]
	], 'Path contains source: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    throws_ok { file_verbatim_ok 't/data/text/missing.txt' }
	qr< \A BAIL_OUT \b >smx,
	't/data/text/missing.txt: exception';

    {
	is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT" ],
	], 't/data/text/missing.txt: trace'
	    or diag 'Got ', explain $TEST->__get_log();
    }


    $TEST->__clear();

    throws_ok { file_verbatim_ok \"## VERBATIM\n" }
	qr< \A BAIL_OUT \b >smx,
	'Missing VERBATIM sub-command: exception';

    is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => 'VERBATIM sub-command missing at SCALAR line 1' ],
	], 'Missing VERBATIM sub-command: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    throws_ok { file_verbatim_ok \"## VERBATIM FUBAR\n" }
	qr< \A BAIL_OUT \b >smx,
	'Invalid VERBATIM sub-command';

    is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => 'VERBATIM FUBAR not recognized at SCALAR line 1' ],
	], 'Invalid sub-command - Bailed out'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    throws_ok { file_verbatim_ok \"## VERBATIM BEGIN\n" }
	qr< \A BAIL_OUT \b >smx,
	'BEGIN not terminated: exception';

    is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => 'VERBATIM BEGIN not terminated at SCALAR line 1' ],
	], 'BEGIN not terminated: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    my $hashes = '##';	# To hide from all_files_ok
    throws_ok { file_verbatim_ok \<<"EOD" }
$hashes VERBATIM BEGIN t/data/text/missing.txt
$hashes VERBATIM END
EOD
	qr< \A BAIL_OUT \b >smx,
	'Source not found: exception';

    is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT at SCALAR line 1" ],
	], 'Source not found: trace'
	    or diag 'Got ', explain $TEST->__get_log();


    $TEST->__clear();

    throws_ok {
	files_are_identical_ok 't/data/text/test_01.txt', 't/data/text/missing.txt' }
	qr< \A BAIL_OUT \b >smx,
	'Source not found: exception';

    is_deeply $TEST->__get_log(),
	[
	    [ BAIL_OUT => "VERBATIM Unable to open t/data/text/missing.txt: $ENOENT" ],
	], 'Source not found: trace'
	    or diag 'Got ', explain $TEST->__get_log();

}

note <<'EOD';

Run passing tests for real, just to be sure they pass.

EOD

file_verbatim_ok 't/data/text/test_01.txt';

file_verbatim_ok 't/data/text/test_02.txt';

file_verbatim_ok 't/data/text/test_03.txt';

file_verbatim_ok 't/data/text/test_04.txt';

file_verbatim_ok 't/data/text/test_05.txt';

all_verbatim_ok map { sprintf 't/data/text/test_%02d.txt', $_ } 1 .. 4;

files_are_identical_ok 't/data/text/test_01.txt', 't/data/text/test_01.txt';

note <<'EOD';

Test with encoding utf-8

EOD

configure_file_verbatim \<<'EOD';
encoding utf-8
EOD

all_verbatim_ok map { sprintf 't/data/text/test_%02d.txt', $_ } 1 .. 4;

done_testing;

1;

# ex: set textwidth=72 :
