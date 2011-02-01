#!/usr/bin/env perl
use strict;
use warnings;

use constant API_KEY => '113fce0260f113d9f09ecec04b9e9d97';
use constant API_SECRET => '1eb39de237529c017494da040ff835a7';

use File::Spec;
use Cwd 'abs_path';
use Net::LastFM;
use Data::Diver 'Dive';
use Readonly;
use DBI;

use constant DBFILE => 'files.db';
use constant QUERY => 'SELECT path, artist, title, filesize, length FROM files WHERE ';
use constant MEGABYTE => '1048576';
use constant M3U_HEADER => '#EXTM3U';
use constant M3U_EXTINF => '#EXTINF:%d,%s - %s' . "\n"; #secs, artist, title

Readonly my %SOURCE =>
(
    'Artist.getSimilar' =>
    {
        alias => 'as',
        key => 'artist',
        rkey => [ similarartists => 'artist'],
        rskey =>
        {
            artist => [ 'name' ],
        }
    },
    'User.getLovedTracks' =>
    {
        alias => 'ul',
        key => 'user',
        rkey => [ lovedtracks => 'track' ],
        rskey =>
        {
            artist => [ artist => 'name'],
            title => [ 'name'],
        }
    }
);

sub usage { "$0 path/to/music/directory [ " . (join ', ', map { "$_|$SOURCE{$_}->{alias}" } keys %SOURCE) . ' ] [size]' };

my $root = abs_path shift @ARGV;
my ($src, $query, $maxsize) = @ARGV;
my $method = $SOURCE{$src} ? $src : (grep { $SOURCE{$_}->{alias} eq $src } keys %SOURCE)[0];

die usage
    unless $query and $method;

print M3U_HEADER;

my $lastfm = Net::LastFM->new(
    api_key    => API_KEY,
    api_secret => API_SECRET,
);
my $dbh = DBI->connect('dbi:SQLite:dbname=' . DBFILE ,'','');


my $response = $lastfm->request(method => lc $method, $SOURCE{$method}->{key} => $query);
my $sth = $dbh->prepare(QUERY . join 'AND ', map { "$_ like ? " } keys %{ $SOURCE{$method}->{rskey} });


my $size;
for my $item (@{ Dive($response, @{ $SOURCE{$method}->{rkey} }) })
{
    my %track;
    my $rskey = $SOURCE{$method}->{rskey};

    # fetching values from nested hash
    $track{$_} = Dive($item, @{ $rskey->{$_} })
        for (keys %$rskey);

    $sth->execute(values %track);
    while (my $row = $sth->fetchrow_hashref)
    {
        printf M3U_EXTINF, $row->{length}, $row->{artist}, $row->{title};
        print $row->{path}, "\n\n";
        $size += $row->{filesize};
        if ($maxsize && $size > $maxsize * MEGABYTE)
        {
            warn "max file size of $maxsize reached";
            exit 0
        }
    }

}
