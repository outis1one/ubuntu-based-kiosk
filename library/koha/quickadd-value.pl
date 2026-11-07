#!/usr/bin/perl
# Installed as .../intranet/cgi-bin/quickadd-value.pl (URL /cgi-bin/koha/quickadd-value.pl).
#
# Koha's REST API cannot add shelves/rooms (authorised value category LOC) or collections (CCODE),
# so the Library site asks this script to, with Koha's own Koha::AuthorisedValue class. Same shared-secret
# guard as quickadd-session / quickadd-return; only the two categories below can be touched.
use Modern::Perl;
use CGI qw( -utf8 );
use JSON qw( encode_json );
use Digest::SHA qw( sha256_hex );
use Koha::AuthorisedValues;
use Koha::AuthorisedValue;

my $q = CGI->new;

sub reply {
    my ( $q, $status, $data ) = @_;
    print $q->header( -type => 'application/json', -status => $status, -charset => 'utf-8', -cache_control => 'no-store' ),
        encode_json($data);
    exit;
}

my $secret = '';
if ( open my $fh, '<', '/etc/koha/quickadd-sso.secret' ) { $secret = <$fh> // ''; $secret =~ s/\s+$//; close $fh }
my $given = $ENV{HTTP_X_QUICKADD_SECRET} // '';
reply( $q, '403 Forbidden', { status => 'forbidden' } )
    unless length($secret) >= 16 && sha256_hex($given) eq sha256_hex($secret);

my $cat   = $q->param('category') // '';
my $value = $q->param('value')    // '';
my $desc  = $q->param('description') // '';
utf8::decode($desc);
reply( $q, '200 OK', { status => 'invalid' } )
    unless $cat =~ /\A(?:LOC|CCODE)\z/ && $value =~ /\A[A-Z0-9_-]{1,20}\z/ && length($desc) && length($desc) <= 80;

my $out = eval {
    my $exists = Koha::AuthorisedValues->search( { category => $cat, authorised_value => $value } )->count;
    return { status => 'exists' } if $exists;
    Koha::AuthorisedValue->new( { category => $cat, authorised_value => $value, lib => $desc, lib_opac => $desc } )->store;
    { status => 'added' };
};
reply( $q, '200 OK', $out // { status => 'failed', error => "$@" } );
