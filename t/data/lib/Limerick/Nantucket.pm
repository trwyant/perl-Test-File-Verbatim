package Limerick::Nantucket;

use 5.010;

use strict;
use warnings;

use Carp;

our $VERSION = '0.000_006';

sub limerick {
    return <<'EOD';
There was an old man from Nantucket
Who kept all his cash in a bucket.
    But his daughter named Nan
    Ran away with a man,
And as for the bucket, Nan tuck it.
EOD
}

1;

# ex: set textwidth=72 :
