#!/usr/bin/perl
# Idempotent housekeeping, run on EVERY container start (after the first-time install or
# the schema upgrade), so existing installs pick these up too:
#   * removal of the Koha guest account an earlier version created (the guest login is Quick Add only)
#   * the "Library tools" block on the staff home page
use Modern::Perl;
use C4::Context;
use Koha::Patrons;
use Koha::Patron::Categories;
use Koha::Caches;

my $dbh  = C4::Context->dbh;
# The read-only "guest" login lives in Quick Add only (the Find a book page), NOT in Koha:
# Koha's own "catalogue" permission also allows editing label layouts and templates, so a
# Koha account cannot be made truly read-only. Remove any guest account an earlier version created.
for my $p ( Koha::Patrons->search( { categorycode => 'VIEWER' } )->as_list ) {
    say "ensure: removing the old Koha guest account '" . $p->userid . "'";
    $p->delete;
}
if ( my $cat = Koha::Patron::Categories->find('VIEWER') ) {
    $cat->delete unless Koha::Patrons->search( { categorycode => 'VIEWER' } )->count;
}

# Patron logins use short, easy-to-remember passwords (a home library, not a bank): Koha's defaults
# (8+ characters, upper+lower+digit) are relaxed once, unless an admin has changed them since.
my $flag = '/var/lib/koha/' . ( $ENV{KOHA_INSTANCE} || 'library' ) . '/.password-policy-set';
unless ( -e $flag ) {
    my ($strong) = $dbh->selectrow_array(q{SELECT value FROM systempreferences WHERE variable = 'RequireStrongPassword'});
    my ($minlen) = $dbh->selectrow_array(q{SELECT value FROM systempreferences WHERE variable = 'minPasswordLength'});
    if ( ( $strong // 1 ) == 1 && ( $minlen // 8 ) == 8 ) {
        $dbh->do(q{UPDATE systempreferences SET value = 0 WHERE variable = 'RequireStrongPassword'});
        $dbh->do(q{UPDATE systempreferences SET value = 4 WHERE variable = 'minPasswordLength'});
        say "ensure: patron passwords may be short (4+ characters, no strength rule)";
        Koha::Caches->get_instance->flush_all;    # preferences are cached; direct SQL edits need this
    }
    if ( open my $fh, '>', $flag ) { close $fh }
}

# Staff home page block (Koha 26.05 keeps these in the HTML customizations tool). Rewritten each start.
my $html = '<div class="main-heading"><h3>A Room for Books</h3></div><ul class="list-unstyled">'
    . '<li><a class="btn btn-primary" href="/add/">Open A Room for Books</a> (library, lend / return, people, add books)</li>'
    . '<li><a href="/add/#find">Find a book</a></li></ul>';
my ($id) = $dbh->selectrow_array(q{SELECT id FROM additional_contents WHERE code = 'library_tools'});
unless ($id) {
    $dbh->do(q{INSERT INTO additional_contents (category, code, location, branchcode, published_on, number)
               VALUES ('html_customizations', 'library_tools', 'IntranetmainUserblock', NULL, CURDATE(), 1)});
    $id = $dbh->last_insert_id( undef, undef, 'additional_contents', 'id' );
    $dbh->do( q{INSERT INTO additional_contents_localizations (additional_content_id, title, content, lang)
                VALUES (?, 'A Room for Books', ?, 'default')}, undef, $id, $html );
    say "ensure: added the staff home 'A Room for Books' block";
}
else {
    $dbh->do( q{UPDATE additional_contents_localizations SET title = 'A Room for Books', content = ? WHERE additional_content_id = ? AND lang = 'default'},
        undef, $html, $id );
}
