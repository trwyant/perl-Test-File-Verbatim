package main;

use 5.010;

use strict;
use warnings;

use Test::More 0.88;	# Because of done_testing();

BEGIN {
    eval {
	require Test::Pod::LinkCheck::Lite;
	Test::Pod::LinkCheck::Lite->VERSION( 0.009 );	# MAYBE_IGNORE_GITHUB
	Test::Pod::LinkCheck::Lite->import( qw{ :const } );
	1;
    } or plan skip_all => 'Unable to load Test::Pod::LinkCheck::Lite';
}

Test::Pod::LinkCheck::Lite->new(
    ignore_url	=> MAYBE_IGNORE_GITHUB,
)->all_pod_files_ok(
    qw{ blib },
);

done_testing;

1;

# ex: set textwidth=72 :
