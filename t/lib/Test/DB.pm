package Test::DB;
use Moo;
use Test::More;
use Test::DBD;
use Test::Schema::Patcher::Run qw/create_run/;
use Test::Schema::Patcher::Patch qw/create_patch/;
use Test::Patcher;
use Data::Dump qw/pp/;

with 'Test::Role::WithSchema';

# 1 new passing
# 2 new failing
# 3 file passed same
# 4 file failed same
# 5 file passed diff
# 6 file failed diff
# 7 md5 passed same
# 8 md5 failed same

my $global_setup = [
    {
        run => {
            patches => [
                {
                    filename => 'file_3.sql',
                    success => 1,
                    b64digest => 'e9mVJXCK2+A6emuE7T/uoQ',
                },{
                    filename => 'file_4.sql',
                    success => 0,
                    b64digest => 'RIbrOdItfytcqEHsLZbWbg',
                },{
                    filename => 'file_5.sql',
                    success => 1,
                    b64digest => 'madeup1',
                },{
                    filename => 'file_6.sql',
                    success => 0,
                    b64digest => 'madeup2',
                },{
                    filename => 'file_7.sql',
                    success => 1,
                    b64digest => 'efe112e2626df8414943e3e651b31077',
                },{
                    filename => 'file_8.sql',
                    success => 0,
                    b64digest => '87f0bf3ee7d20a4bfdadd81b439620ae',
                },
            ],
        },
    },
];

my $test_cases = [
    {
        name => '1 new passing',
        setup => {
            file => {
                file => 'file_1.sql',
            },
        },
        expect => {
            needs_patching => 1,
            state => undef,
            is_success => 1,
        },
    },{
        name => '2 new failing',
        setup => {
            file => {
                file => 'file_2.sql',
            },
        },
        expect => {
            needs_patching => 1,
            state => undef,
            is_success => 0,
        },
    },{
        name => '3 file passed same',
        setup => {
            file => {
                file => 'file_3.sql',
            },
        },
        expect => {
            needs_patching => 0,
            state => 'SKIP',
            is_success => 0,
        },
    },{
        name => '4 file failed same',
        setup => {
            file => {
                file => 'file_4.sql',
            },
        },
        expect => {
            needs_patching => 0,
            state => 'RETRY',
            is_success => 0,
        },
    },{
        name => '5 file passed diff',
        setup => {
            file => {
                file => 'file_5.sql',
            },
        },
        expect => {
            needs_patching => 0,
            state => 'CHANGED',
            is_success => 0,
        },
    },{
        name => '6 file failed diff',
        setup => {
            file => {
                file => 'file_6.sql',
            },
        },
        expect => {
            needs_patching => 0,
            state => 'CHANGED',
            is_success => 0,
        },
#    },{
#        name => '7 md5 passed same',
#        setup => {
#            file => {
#                file => '7.sql',
#            },
#        },
#        expect => {
#            needs_patching => 0,
#            state => 'RETRY',
#            is_success => 0,
#        },
#    },{
#        name => '8 md5 failed same',
#        setup => {
#            file => {
#                file => '8.sql',
#            },
#        },
#        expect => {
#            needs_patching => 0,
#            state => 'RETRY',
#            is_success => 0,
#        },
    },
];

sub clear {
    my($self) = @_;
    my $schema = $self->schema;

    $schema->resultset('Patcher::Patch')->delete;
    $schema->resultset('Patcher::Run')->delete;

    return $self;
}

sub global_setup {
    my($self,$uuid) = @_;

    foreach my $setup (@{$global_setup}) {
        my $run_conf = \%{$setup->{run}};
        my $patches = delete $run_conf->{patches};
        my $run = create_run($uuid,$run_conf);
        note "  run: ". $run->id;
        if (defined $patches && ref($patches) eq 'ARRAY') {
            foreach my $patch_setup (@{$patches}) {
#                $patch_setup->{run_id} = $run->id;
                my $patch = create_patch($uuid,{
                    %{$patch_setup},
                    run_id => $run->id,
                });
                note "  patch: ". $patch->id ." - ". $patch->filename;
            }
        }
    }

    return $self;
}

sub run_test_cases {
    my($self) = @_;

    foreach my $test (@{$test_cases}) {
        diag "Test: ". $test->{name};
        my $setup = $test->{setup};
        my $expect = $test->{expect};

        $self->run_test_case($setup,$expect);
    }
}

sub run_test_case {
    my($self,$setup,$expect) = @_;
    my $file_setup = \%{$setup->{file}};

    
    if (defined $file_setup->{file}) {
        $file_setup->{file} = 't/data/'
            . $file_setup->{file};
    }

    my $file = Test::Patcher->create_file($file_setup);

    is(
        $file->needs_patching,
        $expect->{needs_patching},
        'needs patching - '. $expect->{needs_patching}
    );

    is(
        $file->state,
        $expect->{state},
        'matches state - '. ($expect->{state} || 'UNDEF')
    );

# FIXME: actually run patch
#    is(
#        $file->state,
#        $expect->{is_success},
#        'matches state - '. $expect->{is_success}
#    );
}

1;
