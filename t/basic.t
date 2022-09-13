package main;

use strict;
use warnings;

use Test::More 0.88;	# Because of done_testing();

require_ok 'Test::File::Verbatim'
    or BAIL_OUT $@;

done_testing;

1;
