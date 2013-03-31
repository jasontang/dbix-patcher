package Test::DBD;
use strict;
use warnings;
use Test::More;

sub create_dbd {
    my($self,$type) = @_;

    my $module = 'DBIx::Patcher::DBD::'. $type;
    use_ok($module);

    return $module->new({
        user => 'bob',
        host => 'harry',
        pass => 'secret',
        db => 'woo',
    });
}

1;
