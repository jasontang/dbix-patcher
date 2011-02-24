package Patcher;
use strict;
use warnings;
use FindBin::libs;

use Carp;
use Data::Dump qw/pp/;
use Getopt::Long;
use Path::Class;
use Time::HiRes     qw(usleep);
use Patcher::Schema;
use IO::File;
use Digest::MD5;

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
    my($package) = @_;

    GetOptions(
        'host=s'    => \$opts->{host},
        'user=s'    => \$opts->{user},
        'db=s'      => \$opts->{db},
        'pass=s'    => \$opts->{pass},
        'install'   => \$opts->{install},
        'plugin=s'  => \$opts->{plugin},
        'verbose'   => \$opts->{verbose},
        'dry'       => \$opts->{dry},
        'debug'     => \$opts->{debug},
        'retry'     => \$opts->{retry},
        'chop=s'    => \$opts->{chop},
        'add'       => \$opts->{add},
    );

    # FIXME: do we need to use a plugin?
    # merge in defaults into opt and share plugin
    $opts->{chop} = Path::Class::Dir->new(
        $opts->{chop} ? $opts->{chop} : '.' )
        ->absolute->resolve->cleanup;

    # initiate db
    my $type = $opts->{type};
    my $db = $opts->{db};
    my $host = $opts->{host};
    $schema = Patcher::Schema->connect(
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
        push @files, _collate_patches($dir);
    }

    # patch with the files
    print "  Found ". scalar @files ." file(s)\n" if ($opts->{verbose});
    if (scalar @files) {
        my $run = $schema->resultset('Patcher::Run')->create_run;

        # create run record
        foreach my $file (@files) {
            _patch_it($run,$file);
        }
        $run->update({ finish => \'default' });
    }

    print "opts: ". pp($opts) ."\n" if ($opts->{debug});
    print "argv: ". pp(\@ARGV) ."\n" if ($opts->{debug});
    print "file: ". scalar @files ."\n" if ($opts->{debug});
}


sub _patch_it {
    my($run,$file) = @_;
    my $state;

    my $chopped = _chop_file($file);
    # check $opts->{dry}
    print "    $chopped";

    my $md5 = _md5_it($file);
    print " ($md5)" if ($opts->{verbose});

    # find file order by desc
    my $last = $schema->resultset('Patcher::Patch')->search_file($chopped);

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
    }

    if (!$skip) {
        $state = _apply_patch($run,$file,$md5,$chopped);
    }

    if (!defined $state) {
        die "Expecting to have a state set by now!!";
    }
    print " .. $state\n";
}

sub _chop_file {
    my($chopped,$file) = @_;

    if ($opts->{chop}) {
        return $chopped->relative($opts->{chop});
    } else {
        # FIXME: relative to myself?
die "should be chop!!";
    }
#    return $chopped;
}

sub _apply_patch {
    my($run,$file,$md5,$chopped) = @_;

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
    my($file) = @_;
    my $io = IO::File->new;
    $io->open("< ". $file->relative);
    $io->binmode;

    my $digester = Digest::MD5->new;
    $digester->addfile($io);

    my $digest = $digester->b64digest;
    return $digest;
}

sub _collate_patches {
    my($path) = @_;
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
=pod

=head1 NAME patcher

=head1 SYNOPSIS

patcher [--host=localhost] [--user=www] [--db=my_db] [--install] [--plugin=NAP::DC] patch_dir

=head1 OPTIONS

=head2 --install

=head2 --host

=head2 --user

=head2 --database

=head2

=head2

=head1

=cut
