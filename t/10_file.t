#!perl
use strict;
use warnings;
use FindBin::libs;
use Test::More;
use Data::Dump qw/pp/;

use Test::Patcher;


my $file = Test::Patcher->create_file;
isa_ok($file,'DBIx::Patcher::File');

is(
    Test::Patcher->create_file({
        file => 't/test/funk',
        base => 't/test/',
    })->chopped,
    'funk',
    'chopped',
);

is(
    Test::Patcher->create_file->md5,
    'lMpC0nmLmxox/u3OVqm6Iw',
    'md5',
);


done_testing;
