package Test::Patcher;
use Moo;
use DBIx::Patcher::Core;
use DBIx::Patcher::File;
use Path::Class::Dir;
use Path::Class::File;
use Test::Framework;




sub create_core {
    return DBIx::Patcher::Core->new({
#        base => Path::Class::Dir->new('t/data')->absolute->resolve->cleanup,
        base => 't/data',
    });
}

sub create_file {
    my($self,$conf) = @_;

    $conf->{base} = Path::Class::Dir->new('t/data')
        if (!exists $conf->{base});

    if (!exists $conf->{file}) {
        $conf->{file} = Path::Class::File->new('t/data/file_2.sql');
    } else {
        $conf->{file} = Path::Class::File->new($conf->{file});
    }

    $conf->{schema} = Test::Framework->get_schema
        if (!exists $conf->{schema});

    return DBIx::Patcher::File->new($conf);
}

1;
