package DBIx::Patcher::Types;
use MooseX::Types::Moose qw(
    Bool Int Str ArrayRef RegexpRef ClassName
);
use MooseX::Types -declare => [qw(
    AccessibleDir
    ArrayRefOfDirs
    ArrayRefOfAccessibleDirs
    ArrayRefOfFiles
    ArrayRefOfStrings
    Pattern PatternList
    PositiveInt
    Base64Digest
    DBIC_Schema DBIC_RS
    SQLStatement
    Patch
    Applicator
)];

use MooseX::Types::Path::Class qw(Dir to_Dir is_Dir File to_File is_File);
use MooseX::Types::IO::All 'IO_All';
use List::MoreUtils qw(all);

subtype AccessibleDir, as Dir, 
    where   { -d $_[0] && -r $_[0] }, 
    message { "The directory ($_[0]) must exist and be readable." }
;
coerce AccessibleDir, 
    from Dir,       via { $_[0]               ->cleanup->resolve }, 
    from ArrayRef,  via { Dir->coerce( $_[0] )->cleanup->resolve }, 
    from Str,       via { Dir->coerce( $_[0] )->cleanup->resolve }
;
subtype ArrayRefOfAccessibleDirs, as ArrayRef,
    where   { return 1 unless @{ $_[0] }; all { AccessibleDir->check($_) } @{ $_[0] } };
coerce ArrayRefOfAccessibleDirs,
    from ArrayRef, via { [ map { AccessibleDir->coerce($_) } @{ $_[0] } ] },
    from AccessibleDir, via { [ $_[0] ] },
;


subtype ArrayRefOfDirs, as ArrayRef, where { @{$_[0]} ? all { Dir->check($_) } @{$_[0]} : 1 }; # hack hack bodge
coerce  ArrayRefOfDirs, from ArrayRef, via { [ map { Dir->coerce($_) } @{$_[0]} ] };

subtype ArrayRefOfFiles, as ArrayRef, where { @{$_[0]} ? all { File->check($_) } @{$_[0]} : 1 }; # hack hack bodge
coerce  ArrayRefOfFiles, from ArrayRef, via { [ map { File->coerce($_) } @{$_[0]} ] };
subtype PositiveInt, as Int, where { $_[0] };
subtype Pattern, as RegexpRef;
coerce Pattern, from Str, via { qr{ $_[0] }oxms },
                from RegexpRef, via { $_[0] };
subtype PatternList, as ArrayRef, where { all { Pattern->check($_) } @{ $_[0] } };
coerce PatternList, from ArrayRef, via { [ map { Pattern->coerce($_) } @{ $_[0] } ] };

subtype ArrayRefOfStrings, as ArrayRef, where { all { Str->check($_) } @{ $_[0] } };
subtype SQLStatement, as Str;

coerce ArrayRefOfStrings, from SQLStatement, via { split(/\n/, $_[0]) };
coerce SQLStatement, 
    from IO_All, via { $_[0]->slurp },
    from ArrayRefOfStrings, via { join("\n", @{$_[0]}) },
;

subtype Base64Digest, as Str, where { 
    length $_[0] == 22 && $_[0] !~ m{[^A-Za-z0-9+/]};
};
coerce Base64Digest, 
    from File, via {
        my $io = shift->open;
        $io->binmode;
        my $digester = Digest::MD5->new;
        $digester->addfile($io);
        $digester->b64digest;
},  from SQLStatement, via {
        my $str = shift;
        my $digester = Digest::MD5->new;
        $digester->add($str);
        $digester->b64digest;
};

subtype DBIC_Schema, as class_type("DBIx::Patcher::Schema");
subtype DBIC_RS,     as class_type("DBIx::Class::ResultSet");

subtype Patch, as class_type("DBIx::Patcher::Patch");
coerce Patch, from File, via { Patch->new(filename => $_[0]); };

subtype Applicator, as role_type("DBIx::Patcher::Applicator");
