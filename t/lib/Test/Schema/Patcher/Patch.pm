package Test::Schema::Patcher::Patch;
use strict;
use warnings;
use Test::More;
use Sub::Exporter -setup => {
    exports => [ qw/ create_patch / ],
};
use Test::Framework;
use Data::Dump qw/pp/;


sub create_patch {
    my($uuid,$conf) = @_;

    $conf = { } if (!defined $conf);

    my $rs = Test::Framework->get_schema->resultset('Patcher::Patch');

    $conf->{filename} = "$uuid" if (!defined $conf->{filename});

    return $rs->create($conf);
}

1;
