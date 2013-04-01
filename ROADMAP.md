# ROADMAP

* Moo-ify & Test Basic Features for Pg & Simple SQL Installation
* Driver for SQLite & Test Basic Features

SQLite doesn't seem to have schema implemented so might have to avoid using
them for consistency's sake.

* Release

* Config File

Config to contain all the settings to avoid having to enter them

* Release

* MD5 Matching/Handling
 
In practice there are situatations where the file name changes but the content
doesn't. When it comes to database patches the content is the value bit.

* Install Option



# STRUCTURE

## DBIx::Patcher

Commandline interface implementation - not sure what other implementations
one might want.

* run

## DBIx::Patcher::Core

Core interface to Patcher. Hopefully the split is right so one can possibly
call this within an application if you fancied.

* invoke
* collate_patches (tested)
* try_patching
* find_patches (tested)
* driver - Storage instance. Pg for now. SQLite later
* cmd - System command to apply patch

## DBIx::Patcher::File
* needs_patching (tested)
* apply_patch
* md5 (tested)
* state (tested)
* chopped (tested)

## DBIx::Patcher::DBD::Pg
* cmd (tested)
* dsn (tested)
* type (tested)

## DBIx::Patcher::DBD::SQLite
* cmd
* dsn
* type

## DBIx::Patcher::Schema
### Result::Patcher::Run
* add_patch
* add_successful_patch
* finish_now

### Result::Patcher::Patch
* is_successful

### ResultSet::Patcher::Run
* create_run

### ResultSet::Patcher::Patch
* search_file
* search_md5



# STATES

DBIx::Patcher::File->needs_patching will set ->state to one of the below. This
is an indicator of what state the file is in and what might need doing at this
point.

* UNDEF (tested) - Need to attempt patching
* SKIP (tested) - Filename matched and previously successful run.
* RETRY (tested) - Filename matched and previously failed.
* CHANGED (tested) - Filename matched but content has since changed.

* SAME - Failed filename match, succeeded content match
* LINKED
* MULTIPLE



# COMMANDLINE
* --add
* --verbose
* --retry
* --install

* --matchmd5
* --link

