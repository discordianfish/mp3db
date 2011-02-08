#!/usr/bin/env perl
use strict;
use warnings;

=head1 NAME

m3ufm.pl - generates m3u playlists from files in sqlite database

=head1 SYNOPSIS

m3ufm.pl path function[(params)] name [size]

 Options:
   path         the path to your music directory
   function     a query function with optional params
   name         the target the function operates on
   size         optional size in MB to limit playlist length

=head1 EXAMPLE

m3ufm.pl /data/music 'User.getTopArtists(6month)' discordianfish 4000

This will fetch discordianfish's the top artists in the last 6 month,
queries the database to get all files matching those artists and return
a playlist with max size (all files aggregated) of 4GB.

=cut
 
use constant API_KEY => '113fce0260f113d9f09ecec04b9e9d97';
use constant API_SECRET => '1eb39de237529c017494da040ff835a7';

use File::Spec;
use Cwd 'abs_path';
use Net::LastFM;
use Data::Diver qw( Dive DiveDie );
use List::Util 'shuffle';
use Pod::Usage;
use Readonly;
use DBI;

use constant DBFILE => 'files.db';
use constant QUERY => 'SELECT path, artist, title, filesize, length FROM files WHERE ';
use constant MEGABYTE => '1048576';
use constant M3U_HEADER => "#EXTM3U\n";
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
    },
    'User.getTopArtists' =>
    {
        alias => 'ua',
        key => 'user',
        opt => 'period',
        rkey => [ topartists => 'artist' ],
        rskey =>
        {
            artist => [ 'name' ],
        }
   },
);

sub usage
{
   pod2usage(
    -verbose => 99,
    -sections => [qw(SYNOPSIS EXAMPLE)],
    -msg => "$0 Available functions: " . join ', ', map {
    "$_|$SOURCE{$_}->{alias}" . ($SOURCE{$_}->{opt} ? "($SOURCE{$_}->{opt})" : "")
   } keys %SOURCE)
};

my $root = shift @ARGV;
my ($src, $query, $maxsize) = @ARGV;
#die "src: $src, query: $query, maxsize: $maxsize";

die usage
    unless $query;

$root = abs_path $root;
$src =~ s/\(([^\)]*)\)//;
my $opt = $1;

my $method = $SOURCE{$src} ? $src : (grep { $SOURCE{$_}->{alias} eq $src } keys %SOURCE)[0];

die usage
    unless $method;


print M3U_HEADER;

my $lastfm = Net::LastFM->new(
    api_key    => API_KEY,
    api_secret => API_SECRET,
);
my $dbh = DBI->connect('dbi:SQLite:dbname=' . DBFILE ,'','');


my %req = (method => lc $method, $SOURCE{$method}->{key} => $query);

$req{$SOURCE{$method}->{opt}} = $opt
    if $opt and $SOURCE{$method}->{opt};

my $response = $lastfm->request(%req);

my $sth = $dbh->prepare(QUERY . join 'AND ', map { "$_ like ? " } keys %{ $SOURCE{$method}->{rskey} });

# use Data::Dumper; warn Dumper($response);
my $list = Dive($response, @{ $SOURCE{$method}->{rkey} })
    or DiveDie;

my @matched_files;
for my $item (@$list)
{
    my %track;
    my $rskey = $SOURCE{$method}->{rskey};

    # fetching values from nested hash
    $track{$_} = Dive($item, @{ $rskey->{$_} })
        for (keys %$rskey);

    $sth->execute(values %track);

    push @matched_files, $_
        while $_ = $sth->fetchrow_hashref;
}

my $size;
for my $file
(
    $maxsize ?
        sort { $a->{path} cmp $b->{path} } 
            grep { ($size += $_->{filesize}) < $maxsize * MEGABYTE }
                shuffle @matched_files
    : @matched_files
)
{
    printf M3U_EXTINF, $file->{length} || 0, $file->{artist} || '', $file->{title} || '';
    print $file->{path}, "\n";
}

