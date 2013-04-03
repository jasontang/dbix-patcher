package DBIx::Patcher::Core;
use strict;
use warnings;
use FindBin::libs;

use Moo;
use Carp;
use Data::Dump qw/pp/;
use Path::Class;
use DBIx::Patcher::Schema;
use DBIx::Patcher::File;
use DBIx::Patcher::DBD::Pg;
use DBIx::Patcher::DBD::SQLite;
use IO::File;
use Digest::MD5;
use File::ShareDir;

=pod

=head1 NAME

DBIx::Patcher::Core - 

=head1 METHODS

=cut

sub invoke {
    my($self,$paths) = @_;
    my $patches = $self->collate_patches($paths);

    $self->try_patching($patches);
}



has host => ( is => 'ro', default => sub { 'localhost' } );
has user => ( is => 'ro', default => sub { '' } );
has db => ( is => 'ro', default => sub { 'patcher' } );
has pass => ( is => 'ro', default => sub { '' } );

has type => ( is => 'ro', default => sub { 'Pg' } );
has driver => ( is => 'lazy' );
has schema => ( is => 'lazy' );

has base => ( is => 'rw', default => sub {
    return Path::Class::Dir->new('.')->absolute->resolve->cleanup;
} );


has verbose => ( is => 'rw' );
has debug => ( is => 'rw', default => sub { '' } );
has add => ( is => 'rw', default => sub { '' } );
has matchmd5 => ( is => 'rw', default => sub { '' } );
has retry => ( is => 'rw', default => sub { '' } );
has link => ( is => 'rw', default => sub { '' } );

sub _build_driver {
    my($self) = @_;
    my $class = 'DBIx::Patcher::DBD::'. $self->type;
    return $class->new({
        user => $self->user,
        host => $self->host,
        pass => $self->pass,
        db => $self->db,
    });
}

sub _build_schema {
    my($self) = @_;
    return DBIx::Patcher::Schema->connect(
        $self->driver->dsn, $self->user, $self->pass,
    );
}

sub cmd {
    my $self = shift @_;
    return $self->driver->cmd(@_);
}


=head2 collate_patches

=cut

sub collate_patches {
    my($self,$paths) = @_;
    my @files;
    foreach my $dir (@{$paths}) {
        push @files, $self->find_patches($dir);
    }

    print " Found ". scalar @files ." file(s)\n";

    return \@files;
}

=head2 find_patches

=cut

sub find_patches {
    my($self,$path) = @_;
    my $dir = Path::Class::Dir->new($path);

    my @files;
    foreach my $child ($dir->children) {
        if (!$child->isa('Path::Class::Dir')
            && $child->relative($dir) =~ /\.sql$/i) {
            push @files, DBIx::Patcher::File->new({
                base => $self->base,
                file => $child,
                schema => $self->schema,
                verbose => $self->verbose,
            });
        }
    }

    return sort {
        $a->file->relative($dir) cmp $b->file->relative($dir)
    } @files;
}

=head2 try_patching

=cut

sub try_patching {
    my($self,$files) = @_;

    return
        if (!defined $files || !(ref($files) eq 'ARRAY') || !scalar @{$files});


    my $run = $self->schema->resultset('Patcher::Run')->create_run;
    foreach my $file (@{$files}) {
        my $patch;
        
        if ($file->needs_patching($run,$self->matchmd5,$self->retry)) {
            $patch = $file->apply_patch(
                $run,
                $self->cmd($file->file->absolute),
                $self->add,
            );
        }

        # summarise
        print "  "
            . $file->_build_chopped
            . ($self->verbose ? " (". $file->md5 .")" : '')
            . " .. "
            . $file->state
            ."\n";

        if ($file->state eq 'FAILED') {
            print $patch->output;
        }

    }
    $run->finish_now;
}



sub install {
    my($self) = @_;
    return $self->driver->install_sql();
}

# FIXME
#sub _install_me {
#    my($self,$schema) = @_;
#
#    print "_install_me:  To be implemented\n";
#    $schema->deploy({},
##        [ File::ShareDir::module_dir("DBIx::Patcher"), "sql", "schema" ]
#        [ "lib/DBIx/Patcher.pm", "sql", "schema" ]
#    );
#}

1;
__END__

=head1 AUTHOR

Jason Tang, C<< <tang.jason.ch at gmail.com> >>

=cut
