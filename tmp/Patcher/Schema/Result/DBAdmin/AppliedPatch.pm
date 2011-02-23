package DBIx::Patcher::Schema::Result::DBAdmin::AppliedPatch;
# vim: ts=8 sts=4 et sw=4 sr sta
use strict;
use warnings;

use base 'DBIx::Class';
__PACKAGE__->load_components('PK::Auto', 'InflateColumn::DateTime', 'Core');
__PACKAGE__->table('dbadmin.applied_patch');

__PACKAGE__->add_columns(
    id => {
        data_type => 'integer',
        is_nullable => 0,
        is_auto_increment => 1,
    },
    created => {
        data_type => 'timestamp with time zone',
        is_nullable => 1,
        default => \'NOW()',
    },
    filename => {
        data_type => 'text',
        is_nullable => 0,
    },
    basename => {
        data_type => 'text',
        is_nullable => 0,
    },
    succeeded => {
        data_type => 'boolean',
        is_nullable => 0,
    },
    output => {
        data_type => 'text',
        is_nullable => 0,
    },
    b64digest => {
        data_type => 'text',
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('id');

1;
