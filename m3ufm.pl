#!/usr/bin/env perl
use strict;
use warnings;

use constant API_KEY => '113fce0260f113d9f09ecec04b9e9d97';
use constant API_SECRET => '1eb39de237529c017494da040ff835a7';

use File::Spec;
use Cwd 'abs_path';
use Net::LastFM;
use Data::Diver 'Dive';
use DBI;

#use Data::Dumper;

use constant DBFILE => 'files.db';
use constant QUERY => 'SELECT path, artist, title, filesize, length FROM files WHERE ';
use constant MEGABYTE => '1048576';
use constant M3U_HEADER => '#EXTM3U';
use constant M3U_EXTINF => '#EXTINF:%d,%s - %s' . "\n"; #secs, artist, title

my $SOURCE =
{
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
};
sub usage { "$0 path/to/music/directory [ " . (join ', ', map { "$_|$SOURCE->{$_}->{alias}" } keys %$SOURCE) . ' ] [size]' };

my ($ROOT, $SRC, $QUERY, $MAXSIZE) = @ARGV;

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

my $where = join 'AND ', map { "$_ like ? " } keys %{ $SOURCE->{$METHOD}->{rskey} };
my $sth = $dbh->prepare(QUERY . $where);
my $size;

print M3U_HEADER;
for my $q (@$response)
{
    $sth->execute(values %$q);
    while (my $row = $sth->fetchrow_hashref)
    {
        printf M3U_EXTINF, $row->{length}, $row->{artist}, $row->{title};
        print $row->{path}, "\n\n";
        $size += $row->{filesize};
        if ($MAXSIZE && $size > $MAXSIZE * MEGABYTE)
        {
            warn "max file size of $MAXSIZE reached";
            exit 0
        }
    }
}

sub request
{
    my $method = shift;
    my $query = shift;
    my $ret = $LFM->request(method => lc $method, %$query);

    my @list;
    # searching for our addressed list
    for my $item (@{ Dive($ret, @{ $SOURCE->{$method}->{rkey} }) })
    {
        my %track;
        my $rskey = $SOURCE->{$method}->{rskey};

        # fetching values from nested hash
        $track{$_} = Dive($item, @{ $rskey->{$_} })
            for (keys %$rskey);

        push @list, \%track;
    }

    return \@list;
}
