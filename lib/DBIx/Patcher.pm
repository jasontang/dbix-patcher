package DBIx::Patcher;
use strict;
use warnings;
use FindBin::libs;

use Carp;
use Data::Dump qw/pp/;
use Getopt::Long;
use Path::Class;
use DBIx::Patcher::Schema;
use IO::File;
use Digest::MD5;

=pod

=head1 NAME

DBIx::Patcher - store history of patches applied in database schema

=cut


$|=1;
our $opts = {
    host => 'localhost',
    user => 'www',
    type => 'Pg',
    pass => '',
};
our $types = {
    Pg => {
        cmd => sub {
            return "psql -U $opts->{user} -h $opts->{host} $opts->{db} "
                ."-f $_[0]";
        },
        dsn => sub {
            return "dbi:$opts->{type}:dbname=$opts->{db};"
                ."host=$opts->{host}";
        },
    },
};
our $schema;

sub run {
    my($self) = @_;

    GetOptions(
        'host|h=s'    => \$opts->{host},
        'user|u=s'    => \$opts->{user},
        'db|d=s'      => \$opts->{db},
        'pass|p=s'    => \$opts->{pass},
        'retry|r'     => \$opts->{retry},
        'chop|c=s'    => \$opts->{chop},
        'add|a'       => \$opts->{add},

        'install'   => \$opts->{install},
#        'plugin=s'  => \$opts->{plugin},
        'verbose'   => \$opts->{verbose},
        'debug'     => \$opts->{debug},
#        'dry'       => \$opts->{dry},
        'version'     => \$opts->{version},
        'matchmd5'     => \$opts->{matchmd5},
        'link'     => \$opts->{link},
    );

    $self->_version() if ($opts->{version});

    # FIXME: do we need to use a plugin?
    # merge in defaults into opt and share plugin
    $opts->{chop} = Path::Class::Dir->new(
        $opts->{chop} ? $opts->{chop} : '.' )
        ->absolute->resolve->cleanup;

    # initiate db
    my $type = $opts->{type};
    my $db = $opts->{db};
    my $host = $opts->{host};
    $schema = DBIx::Patcher::Schema->connect(
        $types->{$opts->{type}}->{dsn}(),
        $opts->{user}, $opts->{pass},
    );


    # is it an install
    if ($opts->{install}) {
        _install_me();
    }

    # remaining paramters must be directories
    my @files;
    foreach my $dir (@ARGV) {
        push @files, $self->_collate_patches($dir);
    }
    print "  Found ". scalar @files ." file(s)\n" if ($opts->{verbose});


    # patch with the files
    if (scalar @files) {
        my $run = $schema->resultset('Patcher::Run')->create_run;

        # create run record
        foreach my $file (@files) {
            $self->_patch_it($run,$file);
        }
        $run->update({ finish => \'default' });
    }

    print "opts: ". pp($opts) ."\n" if ($opts->{debug});
    print "argv: ". pp(\@ARGV) ."\n" if ($opts->{debug});
    print "file: ". scalar @files ."\n" if ($opts->{debug});
}

sub _version {
    print "  ". __PACKAGE__ ." $DBIx::Patcher::VERSION Jason Tang\n\n";
    exit;
}

sub _patch_it {
    my($self,$run,$file) = @_;
    my $state;

    my $chopped = $self->_chop_file($file);
    # check $opts->{dry}
    print "    $chopped";

    my $md5 = $self->_md5_it($file);
    print " ($md5)" if ($opts->{verbose});

    # find file order by desc
    my $last = $schema->resultset('Patcher::Patch')
        ->search_file($chopped);
    my $lastmd5;

    # if we don't have a direct file match try matching md5
    if (!$last && $opts->{matchmd5}) {
        $lastmd5 = $schema->resultset('Patcher::Patch')
            ->search_md5($md5);
    }

    my $skip;
    if ($last) {
        if ($last->b64digest eq $md5) {
            if ($last->is_successful) {
                $state = 'SKIP';
                $skip = 1;
            } else {
                if (!$opts->{retry}) {
                    $state = 'RETRY';
                    $skip = 1;
                }
            }
        } else {
            $state = 'CHANGED';
            $skip = 1;
        }
    } elsif (!$last && $opts->{matchmd5}) {
        # we have something useful from seaching for md5
        if ($lastmd5) {
            # 1 exact match means it is the same file
            if ($lastmd5->count == 1) {
                my $patch = $lastmd5->first;

                if ($patch->is_successful) {
                    print " (".$patch->filename.")";

                    # indicated we want to just link it
                    if ($opts->{link}) {
                        $run->add_successful_patch($chopped,$md5);
                        $state = 'LINKED';

                    # could potentially link these files
                    } else {
                        $state = 'SAME';
                    }
                } else {
                    $state = 'RETRY';
                }
                $skip = 1;
            # 
            } elsif ($lastmd5->count > 1) {
                $state = 'MULTIPLE';
                $skip = 1;
            }
        }
    }

    if (!$skip) {
        $state = $self->_apply_patch($run,$file,$md5,$chopped);
    }

    if (!defined $state) {
        die "Expecting to have a state set by now!!";
    }
    print " .. $state\n";
}

sub _chop_file {
    my($self,$file) = @_;

    if ($opts->{chop}) {
        return $file->relative($opts->{chop});
    }
    die "should be chop!!";
}

sub _apply_patch {
    my($self,$run,$file,$md5,$chopped) = @_;

    my $patch = $run->add_patch($chopped,$md5);
    my $cmd = $types->{$opts->{type}}->{cmd}($file->absolute);
    my $state;

    print "cmd: $cmd\n" if ($opts->{debug});

    my $output = ($opts->{add}) ? 'PATCHER: Added' : qx{$cmd 2>&1};
    my $patch_fields = { output => $output };
    # successful
    if (!$opts->{add} && $output =~ m{ERROR:}xms) {
        $state = 'FAILED';
        $patch_fields = {
            output => $output,
        };
    } else {
        if ($opts->{add}) {
            $state = 'ADDED';
        } else {
            $state = 'OK';
        }
        $patch_fields = {
            success => 1,
            output => $output,
        };
    }

    $patch->update($patch_fields);
    return $state;
}

sub _md5_it {
    my($self,$file) = @_;
    my $io = IO::File->new;
    $io->open("< ". $file->relative);
    $io->binmode;

    my $digester = Digest::MD5->new;
    $digester->addfile($io);

    my $digest = $digester->b64digest;
    return $digest;
}

sub _collate_patches {
    my($self,$path) = @_;
    my $dir = Path::Class::Dir->new($path);

    my @files;
    foreach my $child ($dir->children) {
        if (!$child->isa('Path::Class::Dir')
            && $child->relative($dir) =~ /\.sql$/i) {
            push @files, $child;
        }
    }

    return sort { $a->relative($dir) cmp $b->relative($dir) } @files;
}

sub _install_me {
    print "_install_me:  To be implemented\n";
}

1;
__END__

=head1 SYNOPSIS

    # add patches already run on an existing db
    patcher -h db-server -u bob -d my_db sql/0.01 --add

    # running from within the location where the app/sql lives
    patcher -h db-server -u bob -d my_db sql/0.01

    # run patcher from anywhere and store filename correctly
    patcher -h db-server -u bob -d my_db /opt/app/sql/0.01 -c /opt/app

    # to retry previously failed patches
    patcher -h db-server -u bob -d my_db sql/0.01 --retry

=head1 DESCRIPTION

=head1 OPTIONS

=head2 --install

TBA - install the patcher schema before doing anything else

=head2 --host -h

Host of the database. Defaults to localhost

=head2 --user -u

User for connecting to the database. Defaults to www

=head2 --database -d

Name of the database

=head2 --chop -c

When patching remove this from the absolute path of the patch file to make
the logging of patches relative from a certain point. Defaults to $PWD

=head2 --retry

For patches that have failed retry

=head2 --add -a

Any files found that haven't been run, just add them as if they run successfully

=head2 --version

Displays version information

=head2 --matchmd5

When the filename cannot be found, try matching md5 against previous patches.
Files that are matched show the filename and flagged 'SAME'. Use --link to
create a record linking them.

=head2 --link

Files that are md5 matched are linked so its in future not run again. Use with
care as if patches are exactly the same by content it WON'T be run.

=head2 --plugin

TBA - specify a plugin to load and provide defaults/custom handling

=head1 AUTHOR

Jason Tang, C<< <tang.jason.ch at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dbix-patch at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBIx-Patcher>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SEE ALSO

DBIx::Class

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBix::Patcher


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Jason Tang.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

