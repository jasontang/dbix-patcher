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

sub install_sql {
    my($self) = @_;
    return "

BEGIN;

CREATE SCHEMA patcher;

CREATE TABLE patcher.run (
    id SERIAL PRIMARY KEY,
    start timestamp with time zone DEFAULT now() NOT NULL,
    finish timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE patcher.patch (
    id SERIAL PRIMARY KEY,
    run_id integer REFERENCES patcher.run(id) DEFERRABLE,
    created timestamp with time zone DEFAULT now() NOT NULL,
    filename text NOT NULL,
    success boolean DEFAULT false,
    b64digest TEXT,
    output text
);

COMMIT;

";
}

1;
__END__

=head1 AUTHOR

Jason Tang, C<< <tang.jason.ch at gmail.com> >>

=cut

