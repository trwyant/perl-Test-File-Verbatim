package main;

use strict;
use warnings;

use ExtUtils::Manifest qw{maniread};
use Test::More 0.88;	# Because of done_testing();

my $manifest = maniread();

foreach ( sort keys %{ $manifest } ) {
    m{ \A bin / }smx
	and next;
    m{ \A eg / }smx
	and next;
    m{ \A script / }smx
	and next;
    m{ \A tools / }smx
	and next;

    ok ! is_executable(), "$_ should not be executable";
}

done_testing;

sub is_executable {
    my @stat = stat $_;
    $stat[2] & oct(111)
	and return 1;
    open my $fh, '<', $_ or die "Unable to open $_: $!\n";
    local $_ = <$fh>;
    close $fh;
    defined $_
	or return 0;
    return m{ \A [#]! .* perl }smx;
}

1;

# ex: set textwidth=72 :
