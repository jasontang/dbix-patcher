package Test::Role::WithSchema;
use Moo::Role;
use Test::Framework;

has schema => (
    is => 'lazy',
);

sub _build_schema {
    
    return Test::Framework->get_schema;
}

1;
