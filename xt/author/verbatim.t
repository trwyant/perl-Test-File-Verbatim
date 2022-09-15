package main;

use 5.010;

use strict;
use warnings;

use Test::More 0.88;	# Because of done_testing();

BEGIN {
    local $@ = undef;
    eval {
	require Test::File::Verbatim;
	Test::File::Verbatim->import();
	1;
    } or plan skip_all => 'File::Test::Verbatim not available';
}

# This is necessary because t/verbatim.t contains here documents with
# VERBATIM annotations. These will be found by file_verbatim_ok(), so we
# want the tests they specify to pass.
use lib 't/data/lib';

configure_file_verbatim \<<'EOD';
encoding utf-8
trim off
EOD

all_verbatim_ok {
    exclude	=> qr{ \A t/data/ }smx,
};

# Use files_are_identical_ok or file_contains_ok for LICENSE

done_testing;

1;

# ex: set textwidth=72 :
