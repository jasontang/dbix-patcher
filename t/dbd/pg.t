#!perl
use strict;
use warnings;
use FindBin::libs;
use Test::More;
use Data::UUID;
use Data::Dump qw/pp/;

use Test::Framework;
use Test::Patcher;
use Test::DBD;
use Test::DB;

my $uuid = Data::UUID->new->create_hex;
# user
# host
# pass
# db

my $dbd = Test::DBD->create_dbd('Pg');

is(
    $dbd->type,
    'Pg',
    'type matches',
);

is(
    $dbd->cmd('somefile.sql'),
    'psql -U bob -h harry woo -f somefile.sql',
    'cmd matches',
);

is(
    $dbd->dsn,
    'dbi:Pg:dbname=woo;host=harry',
    'dsn matches',
);

Test::DB->new
    ->clear()
    ->run_dbix_tests
    ->global_setup($uuid)
    ->run_test_cases
;


done_testing;
