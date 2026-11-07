#!/usr/bin/perl
# Installed as .../intranet/cgi-bin/svc/quickadd-session (URL /cgi-bin/koha/svc/quickadd-session).
#
# Lets the Add books page (Quick Add) ask: "is this browser signed in to the staff site as
# someone allowed to edit the catalogue?" so staff do not have to log in a second time.
#
# It wraps Koha's own C4::Auth::check_cookie_auth (documented for exactly this: services that
# are invoked by pages authenticated in the usual way) and only answers callers that present a
# shared secret, so it cannot be used to probe sessions from outside. The browser's address is
# passed in explicitly, so Koha's "session is tied to the IP that logged in" rule keeps working.
use Modern::Perl;
use CGI qw( -utf8 );
use JSON qw( encode_json );
use Digest::SHA qw( sha256_hex );
use C4::Auth qw( check_cookie_auth );

my $q = CGI->new;

# Takes the CGI object as an argument: under Plack this file runs wrapped in a sub, where a named
# sub would otherwise see a stale copy of a file-level variable.
sub reply {
    my ( $q, $status, $data ) = @_;
    print $q->header( -type => 'application/json', -status => $status, -charset => 'utf-8', -cache_control => 'no-store' ),
        encode_json($data);
    exit;
}

# 1. The caller must know the shared secret (a file only the Koha user and root can read).
my $secret = '';
if ( open my $fh, '<', '/etc/koha/quickadd-sso.secret' ) { $secret = <$fh> // ''; $secret =~ s/\s+$//; close $fh }
my $given = $ENV{HTTP_X_QUICKADD_SECRET} // '';
reply( $q, '403 Forbidden', { status => 'forbidden' } )
    unless length($secret) >= 16 && sha256_hex($given) eq sha256_hex($secret);

# 2. Plausible-looking inputs only.
my $sid = $q->param('sid') // '';
my $ip  = $q->param('ip')  // '';
reply( $q, '200 OK', { status => 'failed' } )
    unless $sid =~ /\A[A-Za-z0-9]{16,64}\z/ && $ip =~ /\A[0-9A-Fa-f:.]{3,45}\z/;

# 3. Ask Koha. Staff who may edit the catalogue (superlibrarians always may) are let in.
my ( $status, $session ) = check_cookie_auth( $sid, { editcatalogue => 'edit_catalogue' }, { remote_addr => $ip } );
reply( $q, '200 OK', { status => 'ok', user => scalar $session->param('id') } ) if $status eq 'ok' && $session;
reply( $q, '200 OK', { status => $status || 'failed' } );
