package Test::Schema::Patcher::Run;
use strict;
use warnings;
use Test::More;
use Sub::Exporter -setup => {
    exports => [ qw/ create_run / ],
};
use Test::Framework;


sub create_run {
    my($uuid,$conf) = @_;

    $conf = { } if (!defined $conf);

    my $rs = Test::Framework->get_schema->resultset('Patcher::Run');


    return $rs->create($conf);
}

1;
