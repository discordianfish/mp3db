#!/usr/bin/env perl
use strict;
use warnings;

use constant API_KEY => '113fce0260f113d9f09ecec04b9e9d97';
use constant API_SECRET => '1eb39de237529c017494da040ff835a7';

use constant DBFILE => 'files.db';
use constant CREATE => <<EOF;
CREATE TABLE IF NOT EXISTS files
(
    path VARCHAR PRIMARY KEY,
    artist VARCHAR,
    title VARCAHR,
    filesize INTEGER
)
EOF

use constant UPDATE => <<EOF;
INSERT OR REPLACE INTO files (path, artist, title, filesize) VALUES (?,?,?,?)
EOF

use constant DELETE => <<EOF;
DELETE FROM files WHERE path = ?
EOF

my %MAP =
(
    add => [ [ qw/IN_MODIFY IN_CREATE IN_MOVED_TO/ ] => \&add_file ],
    del => [ [ qw/IN_DELETE IN_MOVED_FROM/ ] => \&del_file ],
);

use File::Spec;
use Audio::Scan;
use File::Find;
use Cwd 'abs_path';
use Linux::Inotify2;
use Log::Log4perl qw(:easy);
use DBI;
use Proc::Daemon;

use Data::Dumper;

my $ROOT = abs_path shift
    or die "$0 path/to/music/directory [scan|watch]";

my $dbh = DBI->connect('dbi:SQLite:dbname=' . DBFILE ,'','');
my $log = Log::Log4perl->easy_init('DEBUG');

$dbh->do(CREATE);

my $update = $dbh->prepare(UPDATE);
my $delete = $dbh->prepare(DELETE);




unless (lc shift eq 'watch')
{
    find({wanted => \&add_file, no_chdir => 1}, $ROOT);
    exit;
}

my $notify = Linux::Inotify2->new
    or die $!;

find({ wanted => sub
{
    return unless -d;
    DEBUG "watching $_";
    $notify->watch($_, IN_ALL_EVENTS, \&handle_event) or die $!;
}, no_chdir => 1 }, $ROOT);


INFO 'waiting for events';
my $pid = Proc::Daemon::Init;
1 while $notify->poll;


# ====

sub handle_event
{
    my $event = shift;
    my $file = $event->fullname;
    $file =~ s/^$ROOT\/?//;

    warn "got event for $file";

    for my $action (keys %MAP)
    {
        my ($mask, $call) = @{ $MAP{$action} };
        $call->($file)
           if grep { $event->$_ } @$mask
    }
}

sub del_file
{
    my $file = shift;
    print '-', $file, "\n";
    $delete->execute($file);
}

sub add_file
{
    my $file_rel = shift;
    my $file_abs = $_;
    die 'need rel or abs path' unless $file_rel || $file_abs;

    $file_rel = File::Spec->abs2rel($file_abs, $ROOT)
        unless $file_rel;

    $file_abs = File::Spec->rel2abs($file_rel, $ROOT)
        unless $file_abs && ref $file_abs eq 'SCALAR';

    my $data = eval { Audio::Scan->scan($file_abs) };
    if ($@)
    {
        warn "could not read $file_abs: $@";
        return
    }
    my $artist = $data->{tags}->{TPE1};
    my $title = $data->{tags}->{TIT2};
    my $size = $data->{info}->{file_size};

    print '+', $file_rel, "\n";
    $update->execute($file_rel, $artist, $title, $size);
}
