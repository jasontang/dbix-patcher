package DBIx::Patcher::Schema;
use strict;
use warnings;
use base qw(DBIx::Class::Schema);
our $VERSION = '1.0';

use Scalar::Util qw(blessed);

__PACKAGE__->load_namespaces;

our $Upgrade_Patch = q{
    -- amend patcher DB schema 
    ALTER TABLE dbadmin.applied_patch
        ADD COLUMN b64digest text; 
    UPDATE dbadmin.applied_patch ap
    SET    b64digest = md5.b64digest 
    FROM   dbadmin.md5 md5 
    WHERE  md5.applied_patch_id = ap.id
    ;
    DROP TABLE dbadmin.md5;
};

sub upgrade {
    my $self = shift;
    Carp::croak("Can't call 'upgrade' as a class-method")   
        unless blessed $self;
    $self->storage->txn_do(sub {
        $self->storage->dbh_do(sub {
            my ($storage, $dbh) = @_;
            for my $line ($Upgrade_Patch =~ m!([^;]+;?)!g) {
                chomp $line;
                if ($line) {
                    $dbh->do($line);
                }
            }
        });
    });
}
    

1;
