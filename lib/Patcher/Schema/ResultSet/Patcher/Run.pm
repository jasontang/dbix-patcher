package Patcher::Schema::ResultSet::Patcher::Run;
# vim: ts=8 sts=4 et sw=4 sr sta
use Moose;
use namespace::autoclean;

BEGIN {extends 'DBIx::Class::ResultSet';}

=head2 create_run()

=cut
sub create_run {
    my($self) = @_;

    return $self->create({ start => \'default' });
}


1;
