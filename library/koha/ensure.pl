#!/usr/bin/perl
# Idempotent housekeeping, run on EVERY container start (after the first-time install or
# the schema upgrade), so existing installs pick these up too:
#   * removal of the Koha guest account an earlier version created (the guest login is Quick Add only)
#   * the "Library tools" block on the staff home page
use Modern::Perl;
use C4::Context;
use Koha::Patrons;
use Koha::Patron::Categories;

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

# Staff home page block (Koha 26.05 keeps these in the HTML customizations tool).
my ($have) = $dbh->selectrow_array(q{SELECT COUNT(*) FROM additional_contents WHERE code = 'library_tools'});
unless ($have) {
    my $html = '<div class="main-heading"><h3>Library tools</h3></div><ul class="list-unstyled">'
        . '<li><a class="btn btn-primary" href="/add/#find">Find a book</a></li>'
        . '<li><a href="/add/">Add books (scan an ISBN)</a></li></ul>';
    $dbh->do(q{INSERT INTO additional_contents (category, code, location, branchcode, published_on, number)
               VALUES ('html_customizations', 'library_tools', 'IntranetmainUserblock', NULL, CURDATE(), 1)});
    my $id = $dbh->last_insert_id( undef, undef, 'additional_contents', 'id' );
    $dbh->do( q{INSERT INTO additional_contents_localizations (additional_content_id, title, content, lang)
                VALUES (?, 'Library tools', ?, 'default')}, undef, $id, $html );
    say "ensure: added the staff home 'Library tools' block";
}
