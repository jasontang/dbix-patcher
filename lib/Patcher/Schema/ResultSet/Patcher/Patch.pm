package Patcher::Schema::ResultSet::Patcher::Patch;
# vim: ts=8 sts=4 et sw=4 sr sta
use Moose;
use namespace::autoclean;

BEGIN {extends 'DBIx::Class::ResultSet';}

=head2 ()

=cut
sub search_file {
    my($self,$file) = @_;

    return $self->search({
        filename => $file,
    },{
        order_by => 'created desc',
    });
}


1;
