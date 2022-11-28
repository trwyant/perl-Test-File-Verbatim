package main;

use 5.010;

use strict;
use warnings;

use Test::More 0.88;	# Because of done_testing();
use Test::File::Verbatim;

BEGIN {
    *excl = \&Test::File::Verbatim::__exclude;
}

note <<'EOD';

Included files

EOD

foreach (
    'foo',	# Random file name
    'CVS',	# OK as file, not as directory
    'bak',	# OK as file, not as suffix.
) {
    -d $0;	# Abuse interface.
    ok ! excl(), "File $_ is included";
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
    ok excl(), "File $_ is excluded";
}

note <<'EOD';

Included directories

EOD

foreach (
    'foo',	# Random directory name
    'foo.bak',	# OK as directory, not as file
) {
    -d 't';	# Abuse interface.
    ok ! excl(), "Directory $_ is included";
}

note <<'EOD';

Excluded directories

EOD

foreach (
    'CVS',	# Directory CVS is excluded
    '.git',	# Excluded as directory, too.
) {
    -d 't';	# Abuse interface.
    ok excl(), "Directory $_ is excluded";
}

done_testing;

1;

# ex: set textwidth=72 :
