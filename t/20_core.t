#!perl
use strict;
use warnings;
use FindBin::libs;
use Test::More;
use Data::Dump qw/pp/;

use Test::Framework;
use Test::Patcher;

my $schema = Test::Framework->get_schema();

isa_ok($schema,'DBIx::Patcher::Schema');

my $core = Test::Patcher->create_core;
isa_ok($core,'DBIx::Patcher::Core');


my $patches = $core->collate_patches(['t/data']);
is(scalar (grep { ref($_) eq 'DBIx::Patcher::File' } @{$patches}),
    8,
    'found files (collate_patches)'
);

my @foo =  $core->find_patches('t/data');
is(scalar (grep { ref($_) eq 'DBIx::Patcher::File' } @foo),
    8,
    'found files (find_patches)'
);


done_testing;
