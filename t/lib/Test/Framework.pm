package Test::Framework;
use strict;
use warnings;
use Test::More;
use DBIx::Patcher::Schema;

{
    my $schema;
    sub get_schema {
        $schema ||= DBIx::Patcher::Schema->connect(
            'dbi:Pg:dbname=patcher;host=localhost',
            'www',
            '',
        );

        return $schema;
    }

}



1;
