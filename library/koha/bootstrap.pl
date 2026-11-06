#!/usr/bin/perl
# Headless replacement for Koha's web installer + onboarding wizard.
# Run as the instance user:  koha-shell -c "perl bootstrap.pl" <instance>
#
# Mirrors what /cgi-bin/koha/installer/install.pl does step by step (so a
# future Koha upgrade keeps working), then seeds a home-library setup.
use Modern::Perl;
use C4::Context;
use C4::Installer;
use Koha;
use Koha::Libraries;
use Koha::Patrons;
use Koha::Patron::Categories;
use Koha::CirculationRules;
use Koha::ItemTypes;
use Koha::AuthorisedValues;

$| = 1;
my $seed_dir = $ENV{KOHA_SEED_DIR} || '/opt/koha-init/seed';
my $admin_pass = $ENV{KOHA_ADMIN_PASS};
die "KOHA_ADMIN_PASS not set\n" unless defined $admin_pass && length $admin_pass;
my %env = (
    admin_user => $ENV{KOHA_ADMIN_USER} || 'admin',
    admin_pass => $admin_pass,
    library    => $ENV{KOHA_LIBRARY_NAME} || 'My Library',
    code       => uc( ( $ENV{KOHA_LIBRARY_CODE} || 'HOME' ) =~ s/[^A-Za-z0-9]//gr ) || 'HOME',
);

my $installer = C4::Installer->new();
my $dbh       = C4::Context->dbh;
my $intranet  = C4::Context->config('intranetdir');
my $data      = "$intranet/installer/data/mysql";

# Already installed? (the entrypoint checks too; this is a safety net)
my ($tables) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()");
if ($tables) { say "bootstrap: database already has $tables tables - nothing to do."; exit 0; }

say "bootstrap: loading database schema...";
if ( my $err = $installer->load_db_schema() ) { die "schema load failed: $err\n"; }

$installer->set_marcflavour_syspref('marc21');

# Same ordering rules the web installer applies (sysprefs first, userflags last).
my @files = (
    sort( glob("$data/en/mandatory/*.sql"), glob("$data/en/mandatory/*.yml") ),
    sort( glob("$data/en/marcflavour/marc21/mandatory/*.yml"), glob("$data/en/marcflavour/marc21/mandatory/*.sql") ),
);
# Optional data worth having: matching rules, "Fast add" framework (a short
# cataloguing form - title/author/ISBN/call number/barcode), MARC-coded values.
for my $f (qw(
    marcflavour/marc21/optional/marc21_default_matching_rules.yml
    marcflavour/marc21/optional/marc21_sample_fastadd_framework.yml
    optional/marc21_holdings_coded_values.yml
    optional/marc21_relatorterms.yml
    optional/auth_val.yml
    optional/csv_profiles.yml
)) {
    push @files, "$data/en/$f" if -f "$data/en/$f";
}

say "bootstrap: loading ", scalar(@files), " framework / data files...";
my ( undef, $list ) = $installer->load_sql_in_order( 'en', [], @files );
for my $lvl (@$list) {
    for my $f ( @{ $lvl->{fwklist} } ) {
        say "  ! $f->{fwkname}: $f->{error}" if $f->{error};
    }
}

$installer->set_version_syspref();
$installer->set_languages_syspref('en');

# ---- Home-library seed data (YAML in the same format Koha ships) ----------
for my $y (sort glob("$seed_dir/*.yml")) {
    my $err = $installer->load_sql($y);
    say "  seed $y: ", ( $err ? "ERROR $err" : 'ok' );
}

# ---- Library, patron categories, owner account ----------------------------
Koha::Library->new({
    branchcode => $env{code}, branchname => $env{library},
})->store unless Koha::Libraries->find( $env{code} );

for my $c ( [ 'OWNER', 'Owner / librarian', 'S' ], [ 'FRIEND', 'Friend / borrower', 'A' ] ) {
    Koha::Patron::Category->new({
        categorycode => $c->[0], description => $c->[1], category_type => $c->[2],
        enrolmentperiod => 999, overduenoticerequired => 0,
    })->store unless Koha::Patron::Categories->find( $c->[0] );
}

my $admin = Koha::Patron->new({
    cardnumber => '1000000', surname => 'Librarian', userid => $env{admin_user},
    branchcode => $env{code}, categorycode => 'OWNER', flags => 1,   # 1 = superlibrarian
})->store;
$admin->set_password({ password => $env{admin_pass}, skip_validation => 1 });

# ---- Make "add a book" need as few decisions as possible -------------------
# The item type (942$c) is mandatory in Koha's frameworks; default it to Book so
# a Z39.50 import can be saved without touching that field.
$dbh->do(q{UPDATE marc_subfield_structure SET defaultvalue = 'BOOK'
           WHERE tagfield = '942' AND tagsubfield = 'c'});

# UPC/EAN barcodes (DVDs, CDs, games) live in 024$a, which the stock framework
# leaves unmapped - so Koha can neither search nor de-duplicate on them. Map it
# to the catalogue's `ean` column (used by the quick-add page's duplicate check).
$dbh->do(q{UPDATE marc_subfield_structure SET kohafield = 'biblioitems.ean'
           WHERE tagfield = '024' AND tagsubfield = 'a' AND (kohafield IS NULL OR kohafield = '')});

# ---- Extra item types and shelves chosen at install time -------------------
# KOHA_ITEM_TYPES / KOHA_SHELVES: "CODE=Description;CODE=Description". Koha has no
# API for adding shelves later, so they are declared here (more can be added in
# Administration -> Authorized values -> LOC).
sub pairs {
    my ($raw) = @_;
    return map { my ( $c, $d ) = split /=/, $_, 2; $c =~ s/[^A-Za-z0-9_]//g; ( uc $c, ( $d // $c ) =~ s/^\s+|\s+$//gr ) }
        grep { /\S/ } split /;/, ( $raw // '' );
}
{
    my @t = pairs( $ENV{KOHA_ITEM_TYPES} );
    while ( my ( $c, $d ) = splice @t, 0, 2 ) {
        next unless length $c;
        Koha::ItemType->new( { itemtype => substr( $c, 0, 10 ), description => $d } )->store
            unless Koha::ItemTypes->find( substr( $c, 0, 10 ) );
    }
    my @s = pairs( $ENV{KOHA_SHELVES} );
    while ( my ( $c, $d ) = splice @s, 0, 2 ) {
        next unless length $c;
        Koha::AuthorisedValue->new( { category => 'LOC', authorised_value => substr( $c, 0, 80 ), lib => $d, lib_opac => $d } )->store
            unless Koha::AuthorisedValues->search( { category => 'LOC', authorised_value => substr( $c, 0, 80 ) } )->count;
    }
}

# ---- Lending rules --------------------------------------------------------
# A fresh Koha refuses every checkout ("No circulation rule is defined for this
# patron and itemtype combination") until a default rule exists. One catch-all
# rule for a home library: 3 weeks, 25 items, 3 renewals, no fines.
Koha::CirculationRules->set_rules({
    branchcode => undef, categorycode => undef, itemtype => undef,
    rules => {
        issuelength => 21, lengthunit => 'days', maxissueqty => 25, maxonsiteissueqty => '',
        renewalsallowed => 3, renewalperiod => 21, norenewalbefore => '', noautorenewalbefore => '',
        auto_renew => 0, no_auto_renewal_after => '', no_auto_renewal_after_hard_limit => '',
        unseen_renewals_allowed => '',
        fine => 0, finedays => 0, firstremind => 0, chargeperiod => 0, chargeperiod_charge_at => 0,
        overduefinescap => '', cap_fine_to_replacement_price => 0, rentaldiscount => 0,
        maxsuspensiondays => '', suspension_chargeperiod => 1,
        hardduedate => '', hardduedatecompare => -1,
        reservesallowed => 5, holds_per_record => 1, holds_per_day => '', onshelfholds => 1,
        opacitemholds => 'N', decreaseloanholds => '', article_requests => 'no',
        recalls_allowed => undef, recalls_per_record => undef, on_shelf_recalls => undef,
        recall_due_date_interval => undef, recall_overdue_fine => undef,
        recall_shelf_time => undef, holds_pickup_period => undef,
    },
});

# ---- Staff home page: a "Library tools" block with a link to the Add books page ----
# (Koha 26.05 stores these in the HTML customizations tool, not in a preference.)
{
    my $html = '<div class="main-heading"><h3>Library tools</h3></div><ul class="list-unstyled">'
        . '<li><a class="btn btn-primary" href="/add/">Add books (scan an ISBN)</a></li>'
        . '<li><a href="/add/#find">Find a book</a></li></ul>';
    $dbh->do(q{INSERT INTO additional_contents (category, code, location, branchcode, published_on, number)
               VALUES ('html_customizations', 'library_tools', 'IntranetmainUserblock', NULL, CURDATE(), 1)});
    my $id = $dbh->last_insert_id( undef, undef, 'additional_contents', 'id' );
    $dbh->do( q{INSERT INTO additional_contents_localizations (additional_content_id, title, content, lang)
                VALUES (?, 'Library tools', ?, 'default')}, undef, $id, $html );
}

# ---- Preferences ----------------------------------------------------------
my %prefs = (
    autoBarcode              => 'OFF',          # barcodes are assigned by Quick Add (zero-padded, or none/scanned on request)
    autoMemberNum            => 1,              # new patrons get the next library-card number automatically
    finesMode                => 'off',          # a home library does not charge overdue fines
    itemcallnumber           => '082ab',        # Dewey call number copied from the MARC record
    RESTBasicAuth            => 1,              # lets the quick-add page use the REST API
    OpenLibraryCovers        => 1,              # cover images in the catalogue
    OPACSearchForTitleIn     => '',
    BiblioDefaultView        => 'normal',
    OpacPublic               => 1,
    opacuserlogin            => 0,              # catalogue is browse-only; no patron logins needed
    OpacMaintenance          => 0,
    ExpireReservesMaxPickUpDelay => 0,
    AllowOfflineCirculation  => 0,
    marcflavour              => 'MARC21',
    LibraryName              => $env{library},
    timezone                 => $ENV{TZ} || 'UTC',
);
C4::Context->set_preference( $_, $prefs{$_} ) for sort keys %prefs;

say "bootstrap: done. Staff login: $env{admin_user}";
