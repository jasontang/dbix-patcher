package DBIx::Patcher::Schema::ResultSet::Patcher::Patch;
# vim: ts=8 sts=4 et sw=4 sr sta
use strict;
use warnings;

use parent 'DBIx::Class::ResultSet';

=head2 search_file($file)

Find the record of the last time the patch file was attempted to be applied

=cut
sub search_file {
    my($self,$file) = @_;

    my $set =  $self->search({
        filename => $file,
    },{
        order_by => 'created desc',
    });

    return if (!$set or $set->count == 0);

    return $set->slice(0,0)->first;
}

=head2 search_md5($md5)

Find records where the md5 matches and return the set for further investigating

=cut
sub search_md5 {
    my($self,$md5) = @_;

    my $set =  $self->search({
        b64digest => $md5,
    },{
        order_by => 'created desc',
    });

    return if (!$set or $set->count == 0);

    return $set;
}

1;
