package DBIx::Patcher::DBD::Pg;

use Moo;

=pod

=head1 NAME

DBIx::Patcher::DBD::Pg - 

=head1 METHODS

=cut

has type => ( is => 'ro', default => sub { 'Pg' } );
has user => ( is => 'ro', required => 1 );
has host => ( is => 'ro', required => 1 );
has pass => ( is => 'ro', required => 1 );
has db   => ( is => 'ro', required => 1 );

sub cmd {
    my $self = shift @_;
    return "psql -U ". $self->user ." -h ". $self->host ." ". $self->db
        ." -f $_[0]";
}

sub dsn {
    my($self) = @_;
    return "dbi:". $self->type .":dbname=". $self->db .";host=". $self->host;
}


1;
__END__

=head1 AUTHOR

Jason Tang, C<< <tang.jason.ch at gmail.com> >>

=cut

