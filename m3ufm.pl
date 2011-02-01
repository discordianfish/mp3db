#!/usr/bin/env perl
use strict;
use warnings;

use constant API_KEY => '113fce0260f113d9f09ecec04b9e9d97';
use constant API_SECRET => '1eb39de237529c017494da040ff835a7';

use File::Spec;
use Cwd 'abs_path';
use Net::LastFM;
use DBI;

use Data::Dumper;

use constant DBFILE => 'files.db';
use constant QUERY_ARTIST => 'SELECT path, filesize FROM files WHERE artist like ?';
use constant QUERY_ARTIST_TITLE => 'SELECT path, filesize FROM files WHERE artist like ? AND title like ?';
use constant MEGABYTE => '1048576';

my $SOURCE =
{
    'Artist.getSimilar' =>
    {
        alias => 'as',
        key => 'artist',
        rkey => [ similarartists => artist => 'name' ],
    },
    'User.getLovedTracks' =>
    {
        alias => 'ul',
        key => 'user',
        rkey => [ lovedtracks => track => artist => 'name' ],
    }
};
#$SOURCE
#$SOURCE->{'User.getTopArtists'} = { alias => 'ut => \&UserGetTopArtists ];
#$SOURCE->{'User.getLovedTracks'} = { alias => 'ul =>  \&UsergetLovedTracks ];
#$SOURCE->{'User.getRecentTracks'} = { alias => 'ur =>  \&UserGetRecentTracks ];
#$SOURCE->{'User.getRecommendedArtists'} = { alias =>  'ua => &UserGetRecommendedArtists ];

sub usage { "$0 path/to/music/directory [ " . (join ', ', map { "$_|$SOURCE->{$_}->{alias}" } keys %$SOURCE) . ' ] [size]' };

my ($ROOT, $SRC, $QUERY, $MAXSIZE) = @ARGV;
$MAXSIZE = $MAXSIZE * MEGABYTE;

die usage
    unless $QUERY;

my $METHOD = $SOURCE->{$SRC} ? $SRC : (grep { $SOURCE->{$_}->{alias} eq $SRC } keys %$SOURCE)[0]
    or die usage;

$ROOT = abs_path $ROOT;

my $LFM = Net::LastFM->new(
    api_key    => API_KEY,
    api_secret => API_SECRET,
);


my $response = request($METHOD => { $SOURCE->{$METHOD}->{key} => $QUERY });

my $dbh = DBI->connect('dbi:SQLite:dbname=' . DBFILE ,'','');
my $sth = $dbh->prepare(QUERY_ARTIST);
my $size;
for my $q (@$response)
{
    $sth->execute($q);
    while (my $row = $sth->fetchrow_hashref)
    {
        print Dumper($row), "\n";
        $size += $row->{filesize};
        if ($MAXSIZE && $size > $MAXSIZE)
        {
            warn "max file size of $MAXSIZE reached";
            exit 0
        }
    }
}


#my $update = $dbh->prepare(UPDATE);
#my $delete = $dbh->prepare(DELETE);
#


sub request
{
    my $method = shift;
    my $query = shift;
    warn Dumper({method => $method, %$query});
    my $ret = $LFM->request(method => lc $method, %$query);

    # searching for our addressed list
    while (ref $ret eq 'HASH')
    {
        my $key = shift @{ $SOURCE->{$method}->{rkey} };
        warn $key;
        $ret = $ret->{$key};
    }
    print Dumper $ret;

    # getting our tag(s) from list
    my @list;
    for my $item (@$ret)
    {
        $item = $item->{$_} for @{ $SOURCE->{$method}->{rkey} };
        print Dumper $item;
        push @list, $item;
    }
    return \@list;
}

sub ArtistGetSimilar
{
};
sub UserGetTopArtists {};
sub UsergetLovedTracks {};
sub UserGetRecommendedArtists {};
sub UserGetRecentTracks {};

