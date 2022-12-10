package main;

use 5.010;

use strict;
use warnings;

use Test::More 0.88;	# Because of done_testing();
use Test::File::Verbatim;

chdir 't/data'
    or plan skip_all => "Unable to cd to t/data: $!";

foreach my $excl ( qw{ exclude_ack_ignore exclude_manifest_skip } ) {

    note <<"EOD";

Test $excl()
EOD

    my $is_skip = $excl eq 'exclude_manifest_skip';

    my $code = Test::File::Verbatim->can( $excl )
	or BAIL_OUT "Test::File::Verbatim does not implement $excl";

    note <<'EOD';

Included files

EOD

    foreach (
	'foo',	# Random file name
	'CVS',	# OK as file, not as directory
	'bak',	# OK as file, not as suffix.
    ) {
	-d $0;	# Abuse interface.
	ok ! $code->(), "File $_ is included by $excl()";
    }

    note <<'EOD';

Excluded files

EOD

    foreach (
	'foo.bak',	# Suffix .bak excluded
	'#foo#',	# EMACS swap file.
	'.git',	# Excluded as file.
    ) {
	-d $0;	# Abuse interface.
	ok $code->(), "File $_ is excluded by $excl()";
    }

    note <<'EOD';

Included directories

EOD

    foreach (
	'foo',	# Random directory name
	'foo.bak',	# OK as directory, not as file
    ) {
	-d 'lib';	# Abuse interface.
	$is_skip
	    and local $_ = "$_/";
	ok ! $code->(), "Directory $_ is included by $excl()";
    }

    note <<'EOD';

Excluded directories

EOD

    foreach (
	'CVS',	# Directory CVS is excluded
	'.git',	# Excluded as directory, too.
    ) {
	-d 'lib';	# Abuse interface.
	$is_skip
	    and local $_ = "$_/";
	ok $code->(), "Directory $_ is excluded by $excl()";
    }
}

done_testing;

1;

# ex: set textwidth=72 :
