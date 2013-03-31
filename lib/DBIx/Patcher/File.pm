package DBIx::Patcher::File;
use Moo;
use Data::Dump qw/pp/;
use Path::Class;
use DBIx::Patcher::Schema;
use IO::File;
use Digest::MD5;
use File::ShareDir;

=pod

=head1 NAME

DBIx::Patcher::Core - 

=head1 METHODS

=cut

has schema  => ( is => 'ro', required => 1 );
has base    => ( is => 'ro', required => 1 );
has file    => ( is => 'ro', required => 1 );

has verbose => ( is => 'rw' );

has state   => ( is => 'rw' );
has md5     => ( is => 'lazy' );
has chopped => ( is => 'lazy' );

sub _build_chopped {
    my($self) = @_;

    if ($self->base) {
        return $self->file->relative($self->base);
    }
    die "'base' not set";
}

sub _build_md5 {
    my($self) = @_;

    my $io = IO::File->new;
    $io->open("< ". $self->file->relative);
    $io->binmode;

    my $digester = Digest::MD5->new;
    $digester->addfile($io);

    return $digester->b64digest;
}

=head2 needs_patching

=cut

sub needs_patching {
    my($self,$run,$matchmd5,$retry) = @_;

    # check $opts->{dry}

    # find file order by desc
    # FIXME: extract $schema from $run if not set
    my $last = $self->schema->resultset('Patcher::Patch')
        ->search_file($self->chopped);

    # if we don't have a direct file match try matching md5
    my $lastmd5;
    if (!$last && $matchmd5) {
        $lastmd5 = $self->schema->resultset('Patcher::Patch')
            ->search_md5($self->md5);
    }


    if ($last) {
        my $b64digest = $last->b64digest || '';

        if ($b64digest eq $self->md5) {
            if ($last->is_successful) {
                $self->state('SKIP');
            } else {
                if (!$retry) {
                    $self->state('RETRY');
                }
            }
        } else {
            $self->state('CHANGED');
        }
    } elsif ($lastmd5) {
        # we have something useful from seaching for md5
        # 1 exact match means it is the same file
        if ($lastmd5->count == 1) {
            my $patch = $lastmd5->first;

            if ($patch->is_successful) { # TEST
                print " (".$patch->filename.")";

                # indicated we want to just link it
                    if ($self->link) {
                        $run->add_successful_patch($self->chopped,$self->md5);
                        $self->state('LINKED');
                    } else {
                        # could potentially link these files
                        $self->state('SAME');
                    }
            } else {
                $self->('RETRY');
            }
        } elsif ($lastmd5->count > 1) {
            $self->('MULTIPLE');
        }
    }

    return 1 if (!defined $self->state);
    return 0;
}

=head2 apply_patching

=cut

sub apply_patch {
    my($self,$run,$cmd,$add) = @_;

    my $patch = $run->add_patch($self->chopped,$self->md5);
    print "    cmd: ". $cmd ."\n" if ($self->verbose);

    my $output = $add ? 'PATCHER: Added' : qx{$cmd 2>&1};
    my $patch_fields = { output => $output };

    # successful
    if (!$add && $output =~ m{ERROR:}xms) {
        $self->state('FAILED');
        $patch_fields = {
            output => $output,
        };
    } else {
        if ($add) {
            $self->state('ADDED');
        } else {
            $self->state('OK');
        }
        $patch_fields = {
            success => 1,
            output => $output,
        };
    }

    $patch->update($patch_fields);
    return $patch;
}


1;
__END__

=head1 AUTHOR

Jason Tang, C<< <tang.jason.ch at gmail.com> >>

=cut

