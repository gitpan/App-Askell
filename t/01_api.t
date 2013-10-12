use strict;
use warnings;

use Test::More;
my $tests;
plan tests => $tests;

use App::Askell;

BEGIN { $tests = 2; }

ok(defined $App::Askell::VERSION);
ok($App::Askell::VERSION =~ /^\d{1}.\d{6}$/);

BEGIN { $tests += 1; }

can_ok('App::Askell', qw(new));
