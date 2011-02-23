use MooseX::Declare;

class DBIx::Patcher::Patch {
    use DBIx::Patcher::Types qw( Base64Digest SQLStatement );
    use MooseX::Types::Moose qw( Bool );
    use MooseX::Types::Path::Class qw(File Dir);
    use MooseX::Types::IO::All qw(IO_All);

    has 'filename' => ( isa => File, is => 'ro', required => 1, );
    has 'content' => ( isa => SQLStatement, is => 'ro', lazy_build => 1, coerce => 1, );
    has ['applied', 'success'] => ( isa => Bool, is => 'rw', default => sub { 0 } );
    has 'b64digest' => ( isa => Base64Digest, is => 'rw', lazy_build => 1, coerce => 1, );

    method _build_content   () { $self->filename->slurp }
    method _build_b64digest () { $self->content }

    method filename_relative_to (Dir $base_path does coerce) {
        my $new = $self->filename->absolute->cleanup->resolve->relative($base_path);
        $new;
    }

    sub BUILDARGS {
        my $class = shift;
        my $args = (@_ % 2 == 0) ? { @_ } : $_[0];
        if (exists $args->{filename}) {
            $args->{filename} = $args->{filename}->absolute->cleanup->resolve;
        }
        $args;
    }
}

class DBIx::Patcher::Runner 
 with MooseX::Getopt::Dashes 
 with MooseX::SimpleConfig {
    use MooseX::MultiMethods;
    use MooseX::Types::Path::Class qw(Dir);
    use Path::Class qw(dir file);
    use DBIx::Patcher::Types qw( ArrayRefOfAccessibleDirs );
    use List::MoreUtils qw(any);

    has 'database' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Str',
        required    => 1,
        cmd_aliases => [qw(d dbname)],
        default     => "xt_central"
    );
    has 'host' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Str',
        required    => 0,
        cmd_aliases => 'h',
        default     => sub { "localhost" },
    );
    has 'user' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Str',
        required    => 1,
        cmd_aliases => [qw( u username )],
        default     => "www",
    );
    has 'retry' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Bool',
        required    => 0,
        cmd_aliases => 'r',
    );
    has 'force' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Bool',
        required    => 0,
        cmd_aliases => 'f',
    );

    has 'paths_relative_to' => (
        traits      => ['Getopt'],
        is          => 'ro',
        isa         => 'Str',
        required    => 0,
        cmd_aliases => 'p',
        predicate   => '_has_paths_relative_to',
    );

    sub BUILDARGS {
        my $class = shift;
        my $args = (@_ % 2 == 0) ? { @_ } : $_[0];
        unless (any { exists $args->{$_} } qw(paths_relative_to install upgrade)) {
            printf STDERR 
                "Required option missing: '--paths-relative-to' is required ", 
                "unless 'install' or 'upgrade' commands were specified\n";
            exit 50;
        }
        $args;
    }


    # just_add means "store b64digest, etc, but don't actually apply patch to DB"
    has 'just_add'  => ( traits => [ 'Getopt' ], is => 'ro', isa => 'Bool', required => 0, cmd_aliases => 'j',);
    has 'install'   => ( traits => [ 'Getopt' ], is => 'ro', isa => 'Bool', required => 0, );
    has 'upgrade'   => ( traits => [ 'Getopt' ], is => 'ro', isa => 'Bool', required => 0, );
    has 'report'    => ( traits => [ 'Getopt' ], is => 'ro', isa => 'Bool', required => 0, );

    has 'patcher' => (
        traits     => ['NoGetopt'],
        isa        => "DBIx::Patcher",
        is         => 'ro',
        lazy_build => 1,
        handles    => [qw(deploy report_on_files process_files just_add_files do_upgrade )]
    );

    has patch_dirs => (
        traits => [ 'NoGetopt', 'Array' ],
        isa    => 'ArrayRef[Str]',
        is     => 'rw',
        handles => { 'count_patch_dirs' => "count", "add_to_patch_dirs" => 'push', },
        default => sub { [] },
    );

    has patch_files => (
        isa       => 'ArrayRef[Str]',
        is        => 'rw',
        traits    => [ 'NoGetopt', 'Array' ],
        predicate => 'has_patch_files',
        handles   => { 'count_patch_files' => "count", "add_to_patch_files" => "push", },
        default => sub { [] },
    );
    
    method _build_patcher () {
        my %patcher_args = (
            connect_info => [
                "dbi:Pg:database=" . $self->database . ";host=" . $self->host,
                $self->user,
            ],
            force     => $self->force,
            retry     => $self->retry,
            report    => $self->report,
        );

        $patcher_args{installation_base_path} = $self->paths_relative_to
            if $self->_has_paths_relative_to;

        $patcher_args{patch_dirs}  
            = $self->count_patch_dirs  ? $self->patch_dirs  : [];
        $patcher_args{extra_patch_files} 
            = $self->count_patch_files ? $self->patch_files : [];

        DBIx::Patcher->new( %patcher_args );
    }

    method BUILD {
        if (defined $self->extra_argv and @{ $self->extra_argv }) {
            $self->add_to_patches($self->extra_argv);
        }
    }

    multi method add_to_patches (ArrayRef $paths) {
        $self->add_to_patches($_) for @{ $paths };
    }

    multi method add_to_patches (Str $path) {
        my $dir  = dir ($self->paths_relative_to, $path);
        my $file = file($self->paths_relative_to, $path);
        if      (-d $dir  ) {
            $self->add_to_patch_dirs( $path);
        } elsif (-f $file ) {
            $self->add_to_patch_files($path);
        } else {
            printf STDERR "WARNING: Couldn't understand path '%s' as either a directory or a file.\n",
                $file->stringify;
        }
    }
}

class DBIx::Patcher {
    use File::ShareDir;
    use MooseX::Types::Moose qw(
        Bool Int Str ArrayRef RegexpRef ClassName HashRef
    );

    use DBIx::Patcher::Schema;
    use DBIx::Patcher::Types 
        qw( AccessibleDir ArrayRefOfDirs ArrayRefOfAccessibleDirs ArrayRefOfFiles 
            Pattern PatternList 
            PositiveInt Base64Digest DBIC_Schema DBIC_RS 
            Patch Applicator );

    use MooseX::Types::Path::Class qw(Dir to_Dir is_Dir File to_File is_File);
    use MooseX::Types::IO::All qw(IO_All);

    use MooseX::Lexical::Types 
        qw( AccessibleDir ArrayRefOfFiles Pattern PatternList 
            PositiveInt Base64Digest IO_All );

    use Carp qw(carp croak);
    use Cwd qw(abs_path);
    use File::Find::Rule;
    use Pod::Usage;
    use Digest::MD5;
    use TryCatch;
    use Term::ANSIColor ':constants';
    use Sub::Name qw(subname);
    use Lingua::EN::Inflect qw(PL_N PL_V);

    use namespace::autoclean;


    has 'schema_sql_root' => (
        isa => AccessibleDir, is => 'ro', coerce => 1, required => 0, lazy_build => 1,
    );

    has 'installation_base_path' => (
        isa       => AccessibleDir,
        is        => 'ro',
        coerce    => 1,
        required  => 0,
        predicate => '_has_installation_base_path',
    );

    # this is a little baroque - this would like to be a required attribute but it
    # isn't needed to run --upgrade or --install so we make it optional and add this
    # hack hack bodge design pattern
    before installation_base_path {
        Carp::croak("'installation_base_path' must be defined to use this method")
            unless $self->_has_installation_base_path;
    }

    has 'patch_dirs' => (
        isa       => ArrayRefOfDirs,
        is        => 'ro',
        required  => 0,
        coerce    => 1,
        predicate => 'has_patch_dirs',
        default   => sub { [] },
        traits     => [qw(Array)],
        handles    => {
            each_patch_dirs  => 'map',
            count_patch_dirs => 'count',
        },
    );

    has 'patch_files' => (
        isa        => ArrayRefOfFiles,
        is         => 'ro',
        coerce     => 1,
        lazy_build => 1,
        traits     => [qw(Array)],
        handles    => {
            each_patch_files   => 'map',
            count_patch_files => 'count',
        },
    );
    has 'extra_patch_files' => (
        isa        => ArrayRefOfFiles,
        is         => 'ro',
        coerce     => 1,
        traits     => [qw(Array)],
        handles    => {
            each_extra_patch_file   => 'map',
            count_extra_patch_files => 'count',
        },
    );
    has 'patch_file_extensions' =>
      ( isa => 'ArrayRef[Str]', is => 'rw', default => sub { [qw(sql pl)] } );
    has 'patch_search_depth' =>
      ( isa => PositiveInt, is => 'ro', default => sub { 1 } );

    has 'file_skip_patterns' => (
        isa => PatternList, is => 'ro', lazy_build => 1, coerce => 1, traits => [ qw(Array) ],
        handles => {
            add_file_skip_pattern  => 'push',
            all_file_skip_patterns => 'elements',
        },
    );

    has 'dbadmin_schema_name' => ( isa => Str, is => 'ro', required => 0, default => sub { "dbadmin" } );

    has 'connect_info' => ( isa => 'ArrayRef[Str]|CodeRef', is => 'ro', required => 1, auto_deref => 1, );
    has 'schema_class' => ( isa => ClassName, is => 'ro', default => sub { 'DBIx::Patcher::Schema' }, );
    has 'schema' => ( isa => DBIC_Schema, is => 'ro', lazy_build => 1, handles => {
        resultset   => 'resultset',
        storage     => 'storage',
        do_upgrade  => 'upgrade',
    });
    
    has 'applied_patches_rs' => (
        isa => DBIC_RS, is => 'ro', lazy_build => 1,
    );

    has 'patch_apply_error_regex' => (
        isa => RegexpRef, is => 'ro', default => sub { qr{(?:ERROR|FATAL|could\s+not.+):}xms },
    );

    has 'retry'  => ( isa => Bool, is => 'rw', required => 0, default => sub { 0 }, );
    has 'force'  => ( isa => Bool, is => 'rw', required => 0, default => sub { 0 }, );
    has 'report' => ( isa => Bool, is => 'rw', required => 0, default => sub { 0 }, );

    has applicators => (
        is => 'ro',
        isa => HashRef[Applicator],
        lazy_build => 1,
        traits => ['Hash'],
        handles => {
            get_applicator => 'get',
        }
    );

  
    # TODO: This should probably be a better TC that can coerce from a Patch,
    around get_applicator (Str $filename) {

      my ($ext) = $filename =~ /(\.[^.]+)$/;
      defined $ext or $ext = $filename;

      return $self->$orig($ext);
      
    }

    has applicator_classes => ( 
        isa => HashRef[ClassName], 
        is => 'ro', 
        default => sub {
            { '.pl'  => "DBIx::Patcher::Applicator::Perl",
              '.sql' => "DBIx::Patcher::Applicator::PSQL",
            }
        }
    );

    method _build_schema_sql_root () {
        [ File::ShareDir::module_dir("DBIx::Patcher"), "sql", "schema" ];
    }

    method _build_applicators () {
        my $classes = $self->applicator_classes;
        my $connection = $self->schema->storage->dbh;

        my @args = (
            host     => $connection->{pg_host},
            port     => $connection->{pg_port},
            database => $connection->{pg_db},
            user     => $connection->{pg_user},
        );

        return {
            map {
                $_ => $classes->{$_}->new( @args )
            } keys %$classes
        }
    }

    method _build_patches () { $self->patch_files }

    method _build_schema () { $self->schema_class->connect( $self->connect_info ); }

    method _build_file_skip_patterns () {
        return [
            qr{\A\.\.?\z},
            qr{\A.+?\.swp\z},
    #        qr{mysql}i,    # this is something a calling script should push onto the skip patterns
            qr{rollback}i, # these are rollback patches, not to be applied when patching normally
            qr{\.svn}i,
        ];
    }

    method file_skip_rules () {
        my @rules = 
            map { File::Find::Rule->new->name( $_ ) } 
                $self->all_file_skip_patterns; 
        \@rules;
    }

    method patch_file_patterns () {
        map { "*.$_" }  @{ $self->patch_file_extensions };
    }

    method _absolute_patch_dirs () {
        map { Path::Class::Dir->new($self->installation_base_path, $_) } @{ $self->patch_dirs };
    }

        
    method _build_patch_files () {
        my @patch_files;
        if ($self->has_patch_dirs) {
            my $base = $self->installation_base_path;
            for my $dir ($self->_absolute_patch_dirs) {
                push @patch_files, map { s{\A$base/}{}oxms; $_ } sort { $a cmp $b }
                    File::Find::Rule
                        ->maxdepth( $self->patch_search_depth )
                        ->none(  @{ $self->file_skip_rules })
                        ->name($self->patch_file_patterns)
                        ->file
                        ->in( $dir->stringify )
                ;
            }
        }

        push @patch_files, @{ $self->extra_patch_files };
        if (@patch_files) {
            return [  @patch_files ];
        } else {
            my $msg = "WARNING: ";
            if ($self->has_patch_dirs) {
                my $count = $self->count_patch_dirs;
                $msg .= qq/the patch @{[PL_N("directory", $count)]} passed on command line @{[PL_V("was", $count)]} empty. /;
            } else {
                $msg .= "no patch directory OR patch files found on command line. ";    
            }
            $msg .= "Not applying any patches.";    
            print STDERR "$msg\n";
            return [];
        }
    }

    method _build_applied_patches_rs () { $self->resultset("DBAdmin::AppliedPatch"); }

    method report_on_files () {
        $self->each_patch_files( subname report_on_files_callback =>
            sub { $self->patch_status_report( [$self->installation_base_path, $_] ) }
        );
    }

    method process_files () { 
        $self->each_patch_files( subname process_files_callback => 
            sub { $self->single_patch( [$self->installation_base_path, $_] ) }
        ); 
    }
   
    method just_add_files () { 
        $self->each_patch_files( subname just_add_files_callback => 
            sub { $self->just_add_patch([$self->installation_base_path, $_]) }
        ); 
    }
   
    before each_patch_files (CodeRef $sub) {
        return if $self->count_patch_files;
        printf STDERR "ERROR:   no patches found in patch directory '%s'.\n", 
            join ", ", map { $_->stringify } @{ $self->patch_dirs };
        exit 1;
    }

    method _make_patch (File $filename does coerce) {
        my $patch = DBIx::Patcher::Patch::->new(
            base_path => $self->installation_base_path,
            filename => $filename,
        );
    }

    method patch_status_report (File $filename does coerce) {
        my $patch = $self->_make_patch($filename);
        $filename = $patch->filename_relative_to($self->installation_base_path);
        print CYAN, "$filename", RESET, ":\n\t";

        my $file_rs = $self->patch_status_rs($patch, 
            { ( $self->retry ? ( succeeded => 1 ) : () ) },
        );

        if (my $count = $file_rs->count) {
            my $record = $file_rs->next;
            if (defined($record->b64digest) and $record->b64digest) {
                if ($record->b64digest eq $patch->b64digest) {
                    print YELLOW();
                    if ($record->succeeded) {
                        print "already successfully applied.\n";
                    } else {
                        print "previously failed to apply ($count attempts so far).\n";
                        print "\tre-run with '--retry' to retry.\n";
                    }
                    print RESET();
                } else {
                    print RED, "patchfile changed.", RESET, "\n";
                }
            } else {
                # I'm not sure we can get here any more -- we could during development, I think.
                print "already processed (no MD5 value).\n"
            }
        } else {
            print GREEN, "never attempted.", RESET, "\n";
        }
    }

    method just_add_patch (File $filename does coerce) {
        my $patch = $self->_make_patch($filename);
        $self->log_work_done($patch, 1, "[manually applied, logged with patcher --just-add]");
    }

    method single_patch (File $filename does coerce) {
        my $patch = $self->_make_patch($filename);

        my $applicator = $self->get_applicator($patch->filename->stringify);
    
        my $digest_ok = $self->force ? 1 : $self->ensure_not_tried_before($patch);
        my $sql_ok    = $self->force ? 1 : $applicator->is_transactional($patch);
        printf STDERR "patch '%s' does not appear to use transactions and cannot be " 
                    . "rolled-back if it is errorful. skipping.\n", $patch->filename
                unless $sql_ok;

        if ($digest_ok and $sql_ok) {
            my ($success, $patch_output) = $self->apply_patch($patch);
            $success = 0 if $applicator->did_rollback($patch_output);
            $self->log_work_done($patch, $success, $patch_output);
        }
    }

    method apply_patch (Patch $patch) {
        my ($success, $patch_output) = (0,"");
        try {
            my $applicator = $self->get_applicator($patch->filename->stringify);
            ($success, $patch_output) = $applicator->run_patch($patch);
        } catch ($e where { $_ =~ $self->patch_apply_error_regex } ) {
            my $patchtext = $patch->content;
            carp "caught error running patch - $e\n[patch]\n$patchtext\n[/patch]\n";
            $success = 0;
            $patch_output = "$e\n$patch_output";
        } catch ($e) { 
            Carp::confess($e);
        }

        return ($success, $patch_output);
    }


    method log_work_done (Patch $patch, Bool $success = 1, Str $output = "") {
        my $update = $self->applied_patches_rs->create({
            filename    => $patch->filename_relative_to($self->installation_base_path),
            basename    => $patch->filename->basename,
            succeeded   => $success ? 1 : 0, 
            output      => $output,
            b64digest   => $patch->b64digest,
        });
        $update;
    }

    method _filename_match (Patch $patch) {
        filename => $patch->filename_relative_to($self->installation_base_path);
    }


    method patch_status_rs (Patch $patch, HashRef $where_clause = {}) {
        my $where = {
            $self->_filename_match($patch),
            %$where_clause,
        };

        my $file_rs;
        try {
            $file_rs = $self->applied_patches_rs->search( 
                $where,
                { order_by => { -desc => [qw/ created /] }, } 
            );
        } catch ($e where { m/schema "dbadmin" does not exist/ }) {
            print "patcher not installed. No tracking table found. ",
                "Maybe you want to install it - patcher --install\n\n";
            exit;
        } catch ($e) {
            Carp::croak(qq{\nUnknown error: $e\n});
        }

        $file_rs;
    }

    method ensure_not_tried_before (Patch $patch) {
        my $filename = $patch->filename;
        my $file_rs = $self->patch_status_rs($patch, 
            { ( $self->retry ? ( succeeded => 1 ) : () ) },
        );

        if ($file_rs->count) {
            my $record = $file_rs->next;
            if (defined($record->b64digest) and $record->b64digest) {
                if ($record->b64digest eq $patch->b64digest) {
                    if ($record->succeeded) {
                        print "$filename: already successfully applied.  Skipping.\n";
                    } else {
                        print "$filename: previously failed to apply - skipping.\n";
                        print " " x (2 + length $filename), "re-run with '--retry' to retry.\n";
                    }
                    return 0;
                } else {
                    print "$filename: ", RED, "patchfile changed.", RESET, " Ignoring.\n";
                    return 0;
                }
            } else {
                # I'm not sure we can get here any more -- we could during development, I think.
                print "$filename: already processed (no MD5 value)."
                    ."  Ignoring.\n";
                return 0;
            }
        } else {
            # not seen this file before
            return 1;
        }
    }

    method _resultsource_exists (DBIC_RS $rs) {
        my $count;
        try {
            # hack hack bodge!
            $count = $rs->search({ 1 => 0 })->count;
        } catch ($e) {
            return 0;
        }
        return 1;
    }

    method ensure_patcher_table_exists () {
        $self->_resultsource_exists( $self->applied_patches_rs );
    }

    method ensure_connected {
        $self->schema->storage->ensure_connected;
    }


    method deploy (Bool $do_anyway = 0) {
        $do_anyway = 1 if $self->force;
        $self->ensure_connected;
        if ($self->ensure_patcher_table_exists and $self->applied_patches_rs->count and not $do_anyway) {
            carp "user asked to deploy patcher schema, but we already have patch logs in the database!\n"
              .  "re-run passing a true argument to ->deploy if you want to force this!"
            ;
        } else {
            try {
                printf STDERR "about to deploy schema from '%s'\n", $self->schema_sql_root;
                $self->schema->deploy({}, $self->schema_sql_root);
            } catch ($e) {
                carp "caught error while trying to deploy schema:\n$e\n";
            }
        }
        return 1;
    }

    method upgrade () {
        try {
            $self->do_upgrade;
            print STDERR "Upgrade successful.\n";
        } catch ($e) {
            print STDERR "ERROR upgrading patch database: $e\n";
            print STDERR "Is this patch database already upgraded?\n";
            return 0;
        }
        
        return 1;
    }

}

role DBIx::Patcher::Applicator {
    requires 'run_patch';
    requires 'did_rollback';
    requires 'is_transactional';

}

role DBIx::Patcher::Applicator::Executable 
with DBIx::Patcher::Applicator {
    requires '_build_cmd_line_flags';
    
    has 'executable' => ( isa => 'Str', is => 'ro', required => 1 );

    for my $attr (qw(database host user port)) {
        has $attr => ( 
            isa => 'Value|Undef', is => 'ro', required => 0, 
            predicate => "_has_$attr",
        );
    }

    has cmd_line_flags => (
        isa     => 'HashRef[Str]',
        is      => 'ro',
        builder => '_build_cmd_line_flags',
        traits  => ['Hash'],
        handles => {
            has_cmd_line_flag_for => 'exists',
            all_cmd_line_flags    => 'keys',
            get_cmd_line_flag_for => 'get',
        },
    );

    method get_dynamic_cmdline () {
        return [
            map  { $self->get_cmd_line_flag_for($_), $self->$_ }
            grep { my $m = "_has_$_"; $self->can($m) and $self->$m } # HACK HACK BODGE 
                $self->all_cmd_line_flags
        ];
    }

    method get_static_cmdline () { [] }

}

class DBIx::Patcher::Applicator::Perl {
    use IPC::Cmd qw/run/;

    method did_rollback     (Str $patch_output)           { 0 }
    method is_transactional (DBIx::Patcher::Patch $patch) { 1 }
    
    method run_patch (DBIx::Patcher::Patch $patch) {

        my $cmd = [
            $self->executable,
            $patch->filename,
            @{$self->get_static_cmdline},
            @{$self->get_dynamic_cmdline},
        ];

        print "running: $cmd\n";
        my $output = "";
        my $success = run(command => $cmd, verbose => 1, buffer => \$output );

        # if we have any errors, yell about them
        if (!$success) {
            print "not ok\n";
            print STDERR "errors whilst running script:\n$output";
            return (0, $output);
        } else {
            print "OK\n";
        }
        return (1, $output);
    }


    sub _build_cmd_line_flags {
        {
            user     => '--user',
            host     => '--host',
            database => '--dbname',
            port     => '--dbport',
        };
    };

    with 'DBIx::Patcher::Applicator::Executable';

    has '+executable' => ( default => $^X, );
}


class DBIx::Patcher::Applicator::PSQL {
    use IPC::Cmd qw/run can_run/;

    sub _build_cmd_line_flags {
        {
            user     => '-U',
            host     => '-h',
            database => '-d',
            port     => '-p',
        };
    };

    method cmdline () {
        return [
            $self->executable,
            @{$self->get_static_cmdline},
            @{$self->get_dynamic_cmdline},
        ];
    }

    method did_rollback (Str $patch_output) { $patch_output =~ m{\bROLLBACK;} ? 1 : 0; }

    method run_patch (DBIx::Patcher::Patch $patch) {
        my @cmdline = @{$self->cmdline};
        my $command = $cmdline[0];
        my $full_command = can_run($command);
        if (not $full_command) {
            warn $command
                . q{: executable not found in path}
                . "\n";
            exit -1;
        }
        # use the full path to the executable
        $cmdline[0] = $full_command;

        my $cmd = [
            @cmdline,
            '-f',
            $patch->filename,
        ];
        print "about to run: @{$cmd} 2>&1\n";
        my $output = "";
        my $success = run(command => $cmd, verbose => 0, buffer => \$output );

        # if we have any errors, yell about them
        if (!$success || $output =~ m{(?:ERROR|FATAL|could\s+not.+):}xms) {
            print "not ok\n";
            print STDERR "errors whilst running SQL patch:\n$output";
            return (0, $output);
        } else {
            print "OK\n";
        }
        return (1, $output);
    }



    has 'static_cmdline' => (
        isa => 'ArrayRef[Str]', traits => ['Array'], is => 'ro', default => sub { [] },
        handles => { add_to_static_cmdline => 'push' }
    );

    method get_static_cmdline () {
        return $self->static_cmdline;
    }


    our $work_re             = qr{(?: \s+ (TRANSACTION|WORK) \s* )?}ix;
    our $transaction_mode_re = qr{(?: \s+ ISOLATION \s+ LEVEL \s+ [\w\s]+)?}ix;
    method is_transactional (DBIx::Patcher::Patch $patch) {
        my $content = $patch->content;
        return $content =~ m{\bBEGIN  $work_re $transaction_mode_re ;}ixs 
            && $content =~ m{\bCOMMIT $work_re \s* ;}ixs
        ;
    }
    
    with 'DBIx::Patcher::Applicator::Executable';
    has '+executable' => ( default => "psql", );
}

class DBIx::Patcher::Patch::Ownership {
    has 'owner' => ( isa => 'Str', is => 'rw', default => "www" );
    
    my $types = join "|", map { uc($_) } 
        qw(database domain function group index operator role schema sequence trigger type view);
    my $grammar = qr{ \A (?:CREATE|ALTER) \s+ ($types) \s+ (\S+) }omsx; 

    has '_regex' => ( isa => 'Regexp', is => 'ro', default => sub { $grammar } );

    method match (Str $line) {
        if ($line =~ $self->_regex) {
            my ($type, $what) = ($1, $2);
            my $who = $self->owner;
            my $newline = "ALTER $type $what SET OWNER TO $who;";
            return ($line, $newline);
        }
    }

    use DBIx::Patcher::Types   qw(SQLStatement ArrayRefOfStrings Patch);
    use MooseX::Lexical::Types qw(SQLStatement Patch);
    method related_patch (Patch $patch does coerce) {
        my Patch $newpatch = Patch->new( filename => $patch->filename );
        my SQLStatement $newsql = 
            to_SQLStatement(
                map { $self->match($_) } 
                    @{ to_ArrayRefOfStrings($patch->content) } 
            )
        ;
        $newpatch->content( $newsql );
        $newpatch;
    }
}


__END__

=pod

=head1 NAME

patcher - attempt to keep track of applied patches

=head1 SYNOPSIS

patcher [options] directory

 Options:

   --retry          re-run failed files
   --force          run all files, regardless of status
   --justadd        store the files but don't actually run them

   --database       specify a database to connect to
                    [default: xt_central]

   --patcherdb      specify a patcher database to connect to (data about
                    applied patches is stored here)
                    [default: from fulcrum cfg]

   --user           specify the user to connect as
                    [default: undefined]
   --host           specify a host to connect to
                    [default: undefined]

   --help           brief help message

=cut
