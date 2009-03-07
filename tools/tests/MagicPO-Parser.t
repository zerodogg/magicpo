#!/usr/bin/perl
use strict;
use Test::More;
use MagicPO::Parser;
use constant { true => 1, false => 0};

# How many tests to run
my $tests = 8;
# The test po file
my $TestPo = './tools/tests/testpo.po';
# The number of entries in $TestPo
my $TestPoEntries = 4;
plan tests => $tests;

# Global var keeping track of if we're getting callbacks or not
my $CallbackOk = false;
# The test callback
sub testcallback
{
	return if $CallbackOk;
	pass('test callback');
	$CallbackOk = 1;
}

# Create the object
my $obj = MagicPO::Parser->new($TestPo,\&testcallback);
ok($obj,'->new()');
isa_ok($obj,'MagicPO::Parser');
# Ensure that public hashes are available
ok(defined $obj->{PoFile});
ok(defined $obj->{Lookup});
is($obj->{IDS},$TestPoEntries,'Number of entries in the object');
$TestPoEntries--;
# The po files
is(scalar keys %{$obj->{Lookup}},$TestPoEntries,'Number of entries to lookup');

# The first PO-part
ok(defined $obj->{PoFile}{1},'Part1 defined');
