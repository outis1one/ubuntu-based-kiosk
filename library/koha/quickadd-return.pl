#!/usr/bin/perl
# Installed as .../intranet/cgi-bin/quickadd-return.pl (URL /cgi-bin/koha/quickadd-return.pl).
#
# Koha's REST API has no "check in" call, so the Add books / Lend page asks this small script to do it
# with Koha's own C4::Circulation::AddReturn (the same code the staff Check in screen runs: it clears
# the loan, handles holds and fines rules). Same shared-secret guard as quickadd-session: only callers
# that know the secret get an answer.
use Modern::Perl;
use CGI qw( -utf8 );
use JSON qw( encode_json );
use Digest::SHA qw( sha256_hex );
use C4::Context;
use C4::Circulation qw( AddReturn );
use Koha::Items;
use Koha::Patrons;

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

my $barcode = $q->param('barcode') // '';
reply( $q, '200 OK', { status => 'invalid' } ) unless $barcode =~ /\A[\x21-\x7e]{1,40}\z/;

my $item = Koha::Items->find( { barcode => $barcode } );
reply( $q, '200 OK', { status => 'unknown_barcode' } ) unless $item;

# AddReturn needs to know which branch it is happening at.
my $branch = $item->homebranch;
my ( $doreturn, $messages, $borrower, $was_out );
eval {
    C4::Context->set_userenv( 0, 0, 'quickadd', 'Quick', 'Add', $branch, $branch, 0, '', '' );
    $was_out = $item->checkout ? 1 : 0;
    ( $doreturn, $messages, undef, $borrower ) = AddReturn( $barcode, $branch );
    1;
} or reply( $q, '200 OK', { status => 'failed', error => "$@" } );
my $hold_for = '';
if ( ref $messages eq 'HASH' && ref $messages->{ResFound} ) {
    my $r   = $messages->{ResFound};
    my $bn  = eval { $r->can('borrowernumber') ? $r->borrowernumber : undef } // ( ref $r eq 'HASH' ? $r->{borrowernumber} : undef );
    my $pt  = $bn ? Koha::Patrons->find($bn) : undef;
    $hold_for = join ' ', grep { length } $pt->firstname, $pt->surname if $pt;
}
reply(
    $q, '200 OK',
    {
        hold_for => $hold_for,
        status   => $doreturn && $was_out ? 'returned' : ( $doreturn || exists $messages->{NotIssued} ) ? 'not_out' : 'failed',
        patron   => $borrower ? ( join ' ', grep { length } $borrower->{firstname}, $borrower->{surname} ) : '',
        messages => [ sort keys %{ $messages || {} } ],
    }
);
