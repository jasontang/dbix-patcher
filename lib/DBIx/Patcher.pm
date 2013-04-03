package DBIx::Patcher;
use strict;
use warnings;
use FindBin::libs;

use Carp;
use Data::Dump qw/pp/;
use Getopt::Long;
use DBIx::Patcher::Core;

=pod

=head1 NAME

DBIx::Patcher - store history of patches applied in database schema

=cut


$|=1;
our $schema;

sub run {
    my($self) = @_;

    my $opts = $self->_process_commandline();
    $self->_version()   if ($opts->{version});
    $self->_help()      if ($opts->{help});

    foreach my $key (keys %{$opts}) {
        delete $opts->{$key} if (!defined $opts->{$key});
    }

    $self->_install     if ($opts->{install});

    DBIx::Patcher::Core->new($opts)->invoke(\@ARGV);
}

sub _process_commandline {
    my($self) = @_;
    my $opts;

    GetOptions(
        'host|h=s'      => \$opts->{host},
        'user|u=s'      => \$opts->{user},
        'db|d=s'        => \$opts->{db},
        'pass|p=s'      => \$opts->{pass},

        'retry|r'       => \$opts->{retry},
        'base|b=s'      => \$opts->{base},
        'add|a'         => \$opts->{add},
        'version'       => \$opts->{version},
        'verbose'       => \$opts->{verbose},

        'install'       => \$opts->{install},

        'debug'         => \$opts->{debug},
        'matchmd5'      => \$opts->{matchmd5},
        'link'          => \$opts->{link},
        'config|f=s'    => \$opts->{config},
#        'dry'           => \$opts->{dry},
#        'install'       => \$opts->{install},
#        'plugin=s'      => \$opts->{plugin},
#        'schema'        => \$opts->{schema},

    );

    if ($opts->{config}) {
        # FIXME: allow config file
        # load config
        # overlay with $opts
    }
    return $opts;
}

sub _version {
    print "  ". __PACKAGE__ ." $DBIx::Patcher::VERSION Jason Tang\n\n";
    exit;
}
sub _install {
    print DBIx::Patcher::Core->new()->install() ."\n";
    exit;
}

sub _help {
    print <<END;
  $0
    host|h
    user|u
    db|d
    pass|p
    base|b

    retry|r
    add|a
    version
    verbose
    debug
    matchmd5
    link
    config|f

States
SKIP
    Filename matched and successfully run preiously
RETRY
    Filename matched but didn't previously successfully run
CHANGED
    Filename matched but file content changed
END
    exit;
#SAME
#    MD5 matched but different filename.
#LINKED
#    MD5 matched and requested file is linked
#MULTIPLE
#    MD5 matching gave multiple matches
}

1;
__END__

=head1 SYNOPSIS

    # add patches already run on an existing db
    patcher -h db-server -u bob -d my_db sql/0.01 --add

    # running from within the location where the app/sql lives
    patcher -h db-server -u bob -d my_db sql/0.01

    # run patcher from anywhere and store filename correctly
    patcher -h db-server -u bob -d my_db /opt/app/sql/0.01 -b /opt/app

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

=head2 --base -b

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

