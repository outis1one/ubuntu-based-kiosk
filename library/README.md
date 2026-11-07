# Room for Books: a home library (Koha + the Room for Books site, in Docker)

A self-hosted library catalogue you can set up in one command:

```bash
sudo ./install.sh
```

It installs Docker if it is missing, generates the passwords, builds the images,
starts everything and prints the addresses and your login. Running it again is safe;
it never overwrites your `.env` (passwords) or your data.

| What | Address | Login |
|---|---|---|
| **Your library**: add books, find a book, people, lending, labels, settings | `http://<this machine>:8098` | `admin` and the generated password |
| **Add books** (scan an ISBN, or use the phone camera) | `http://<this machine>:8098/add/` | same login (asked once more) |
| **Public catalogue** (search only, for a kiosk or visitors) | `http://<this machine>:8097` | none |

For home use you only need the first address: sign in to **Your library**, and use the **Add books**
button on its home page. The Add books page has a **Find a book** tab (title, author or ISBN, with the
shelf and whether it is on the shelf or checked out) and a **Manage** link back to the staff site. The
public catalogue exists for a kiosk screen or visitors and does not need a login. (Koha gives its public and
staff sites the same URL shapes, so they cannot share one address; Add books can, and does.)

Ports move up to the next free number if one is taken; the final addresses are printed
at the end and by `sudo ./install.sh --status`. Add books is also reachable directly on its own port
(`8099`), which is handy behind a proxy but not needed otherwise.

## What it is made of

* **Koha**: the open-source library system, built from the Koha project's own Debian
  packages (no third-party Koha images). Installed and configured automatically; there is
  no web installer to click through.
* **Quick Add** (`quickadd/`): a small page that turns "scan an ISBN" into "book added".
* **MariaDB**: the database.

Needs about 2 GB of RAM and 3 GB of disk. The first build takes 5-10 minutes.

## Adding books

Open **Add books** and scan (or type) an ISBN, then Enter. A USB or Bluetooth barcode
scanner works as a keyboard, so just scan.

1. The ISBN is looked up on the Library of Congress over **Z39.50**. If that server cannot
   be reached (many networks block port 210), **Open Library** over HTTPS is used instead.
2. If you already have the title, you are asked whether to add **another copy**.
3. Otherwise the record is added with a barcode (see **Barcodes** below), the Dewey (or LC) call
   number from the record, the item type chosen at the top (Book, Movie, Music, Game) and the shelf
   you picked.
4. Nothing found? A short form lets you type the title and it is added anyway.
5. **Undo** removes an item (and the record, if it was the only copy). Freed barcode numbers
   are never reused, because a label may already be printed.

DVDs and CDs work by scanning the **UPC** under the barcode; they are matched against what you
own the same way ISBNs are. Few UPCs are in the free catalogues, so expect to type a title
for many of them.

The page beeps: high for added, double for a duplicate, low for not found. You can scan a
stack of books without looking at the screen.

### Scanning with a phone camera

Open the Add books page in your phone's browser and tap **Scan with camera**. Your phone's own camera app
opens; take a photo with the barcode filling the frame, and the book is looked up and added just as if you had
typed it. In "scan a pre-printed sticker" mode the same button appears on the sticker step.

* It works over plain HTTP on both iPhone and Android: the photo is taken by the phone's camera app, shrunk on
  the phone, and read on the server (`zbarimg`). Only JPEG and PNG photos are accepted.
* It reads ISBN-13 and ISBN-10 barcodes, and UPC/EAN codes on discs and games.
* Tips: get close so the barcode fills most of the frame, keep it flat and well lit, and hold steady. If it
  can't read the photo you are told, and nothing is added.
* A live viewfinder that reads continuously would need HTTPS (browsers only allow that for secure pages); a
  Bluetooth scanner paired to the phone also works, since it types into the page.

## Barcodes: your choice

Barcodes are optional. Open **Barcodes and settings** at the bottom of the Add books page:

| Choice | What happens |
|---|---|
| **Number them automatically** (default) | Each new item gets the next number, zero-padded to 7 digits (`0000042`). |
| **I stick a pre-printed barcode on each one** | After the ISBN is recognised you scan the sticker on the book. A sticker that is already in use is refused. |
| **No barcodes for now** | Items are added without one; the catalogue still shows them. |

Later, in the same panel:

* **Give them barcodes** numbers every item that has none, in one go, and shows the range to print.
* **Print a sheet of barcodes ahead of time** reserves a block (say 80 numbers), and the link opens
  Koha's label printer with that range filled in. Print the sheet, and stick the labels on whenever you like.
  Reserved numbers are never handed out again.

Good to know:

* Koha's range printer needs both ends to be the same length, so barcodes are fixed-width digits. They are
  **at least 7 digits** on purpose: 6-digit all-number Code 39 barcodes can be misread as the pharmacy
  "Code 32" format by some scanners (checked with a decoder: 7 digits read back perfectly, 6 did not).
* Prefixes (such as `HOME-0042`) are not offered: Koha's range printer cannot print them.
* Barcode types Koha can print: Code 39 (default, read by every scanner), Code 39 with a Modulo-43 or
  Modulo-10 check digit (needs a scanner set up for check digits), EAN-13 (exactly 12-13 digits),
  COOP 2 of 5 and Industrial 2 of 5. Change it under *Cataloging → Label creator → Label layouts*.
* Koha's own automatic barcode is switched off so there is one numbering scheme. Items added in the staff
  interface have no barcode until you press **Give them barcodes**.

## Printing labels

From the Add books page, **Print labels** opens Koha's label printer with the barcode range of what you
just added filled in (you may be asked to log in to the staff interface). Pick a template and layout
and print at 100% scale (not "fit to page") so the labels line up.

| Template | Sheet |
|---|---|
| Avery 5160, 1 x 2-5/8 | 30 per sheet; spine label + barcode |
| Avery 5167, 1/2 x 1-3/4 | 80 per sheet; barcode only |
| Demco spine, 1 x 1.5 | 50 per sheet; call number on up to four lines |

| Layout | Prints |
|---|---|
| Spine + barcode | call number (split over lines) with the barcode below |
| Spine - call number | call number only |
| Barcode only | barcode |

## People and lending

Lending is set up for a home library: 3-week loans, up to 25 items, 3 renewals, **no fines**.
Change it under *Administration → Circulation and fines rules*.

1. **Add a person**: staff interface → *Patrons → New patron → Friend / borrower*. Only the name is
   required; the **library card number is assigned automatically** (`1000001`, `1000002`, ...). Numbers
   start well away from item barcodes so a scan can never mean both.
2. **Print the card**: *Tools → Patron card creator → New batch*, add the patron's number, *Export card
   batch*, template **Avery 5371**, layout **Library card**. The card carries the name and a scannable barcode.
3. **Check out**: *Circulation → Check out*. Scan the person's card, then scan each book. The due date appears
   on screen.
4. **Check in**: *Circulation → Check in*, scan the book.

A USB or Bluetooth scanner types the number and presses Enter, so it works in all of these boxes.

## Finding the books

The public catalogue searches title, author, subject and ISBN, and shows each copy's
availability, call number and **shelving location**.

On the Add books page, pick the **Shelf / room** before you scan; every book you add
gets it. The choice is saved on the server, so every device shares it. If all your books are in one
place, leave it on *(not set / all in one place)*; nothing is shown and nothing needs changing. Change it
whenever you move to another shelf.
The list comes from the staff interface (*Administration → Authorized values → LOC*), which
starts with a few rooms such as Fiction, General stacks and Reference. Add your own there,
for example "Living room - bookcase 2". (Koha has no way to add a room from the Add books page.)

## Common tasks

```bash
sudo ./install.sh --status     # addresses, login, container health
sudo ./install.sh --update     # rebuild with the latest Koha release (your data is kept)
sudo ./install.sh --stop       # stop everything
sudo ./install.sh --start      # start again
sudo docker logs -f library-koha
```

Settings live in `.env` (created on first run, mode 600). Useful ones:

| Setting | Meaning |
|---|---|
| `BIND_ADDR` | `0.0.0.0` (default) reachable from the network, `127.0.0.1` this machine only. Docker bypasses `ufw`, so this is the setting that actually limits access |
| `OPAC_PORT`, `STAFF_PORT`, `QUICKADD_PORT` | published ports |
| `QUICKADD_SOURCES` | lookup order, e.g. `z3950:lx2.loc.gov:210/LCDB,openlibrary`. Add more `z3950:host:port/database` entries |
| `LIBRARY_NAME` | name shown on the catalogue (first install only) |

After editing `.env` run `sudo docker compose up -d`.

## Behind a proxy or on a locked-down network

* Building behind a TLS-inspecting proxy: `sudo EXTRA_CA=/path/to/ca.crt ./install.sh`.
* Docker Hub limits anonymous pulls (HTTP 429). The installer retries with a growing pause.
* Z39.50 needs outbound TCP port 210. Without it, Open Library is used automatically.

## Backups

Your books live in two Docker volumes: `library_db-data` (the catalogue) and
`library_koha-data` (search index, uploads). Back up the database with:

```bash
sudo docker exec library-db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction koha_library' > library-backup.sql
```

The search index is rebuilt automatically if it is lost.

## Security notes

* The staff interface and Quick Add are protected by the generated password, over plain HTTP.
  Keep them on a trusted network, or set `BIND_ADDR=127.0.0.1` and put a reverse proxy with
  HTTPS in front.
* Quick Add uses the staff `admin` login to talk to Koha's API.

## Layout

```
install.sh            one-command setup and --status/--update/--stop/--start
docker-compose.yml    db + koha + quickadd
koha/                 Dockerfile (Koha from the project's Debian repo), entrypoint,
                      bootstrap.pl (headless install), seed/ (item types, Z39.50
                      servers, label templates/layouts)
quickadd/             the scan-to-add service (Python standard library + yaz)
```

## Signing in once

Staff who are signed in to the library site (and allowed to edit the catalogue) open **Add books** without a second login. Koha itself confirms the sign-in; the shared secret is `SSO_SECRET` in `.env`. The read-only `guest` login still uses the Add books prompt, and the direct Add books port never accepts a Koha sign-in. If `SSO_SECRET` is empty, Add books just asks for its own login as before.

## The home page (the Room for Books site at `/add/`)

**One address.** `http://<ip>:<port>/` (and later `https://your-domain/` behind Caddy) opens this page; there is no separate
port to remember. Koha's own staff screens live on the same address at `/cgi-bin/koha/mainpage.pl`, reached from the menu
(*Koha (full staff screens)*). Everyone signs in at the same prompt: staff with the admin login, borrowers with their card number
and password, the guest with the guest login.

One simple page: a **Look up** box (books by title, author or ISBN, and people by name or card number), four big buttons
(**Check out**, **Return**, **Add books**, **Add a person**) and **Recently added** books with their covers. The **menu**
(top right) holds the rest: browse all books, lend / return, people and library cards, barcodes and settings, export / import,
and a link to Koha's own staff screens. Borrowers and the read-only guest see just the lookup, recent books and (borrowers) My books.

**One search box for everything:** it matches a book's title, author, ISBN, **tags**, **shelf / room** and **collection** (type `kids`, `garage`, `to read`...), and people by name or card number.

**Adding by title:** on Add books, scan or type an ISBN to add it straight away; type a title or author instead and you get a list
of matches (cover, author, year, publisher) from Open Library and the Library of Congress to choose from. Books you already have
are marked, with an *Add another copy* button.

## Everyday use (details)

One page for the day-to-day, so you rarely need Koha's own screens:

- **Library**: a cover grid of everything you own. Search by title, author or ISBN; filter by shelf, format
  (book/DVD/CD) and status (on the shelf / checked out); sort by title, author or newest. Click a book for its
  page: copies with barcode, status, who has it and when it is due; change a copy's shelf or call number,
  add another copy, remove a copy, or delete the book. (Title/author edits are one click away in Koha.)
- **Lend / return**: scan or type a library card number (or search by name), then scan books to check them out;
  "Return a book" takes a scan with no person needed; **Renew** extends a loan; the list below shows everything
  that is out, overdue ones flagged. Check-in goes through Koha's own check-in code, so holds and rules still apply.
- **People**: add someone with just a name (the card number is assigned automatically), search, and
  **Print card** for a library card with a scannable Code 39 barcode.
- **Add books**: scan an ISBN (or use the phone camera), as before.

The read-only `guest` login only sees the Library and book pages (no copy status names, no editing, no lending).

### Collections, QR cards, more about a book

- **Collections** (Kids, Cookbooks, ...) are per copy, shown on the book page next to the shelf, and filterable on the
  Library page. Choose **+ New collection...** (or **+ New shelf...**) in the dropdown to add one: no Koha screens needed.
- **Library cards** carry a Code 39 barcode and a **QR code** of the card number. **Save as picture** makes an image to text
  or AirDrop to a phone; on Lend / return, **Scan card or phone QR with camera** reads either one from a photo.
  **Print everyone's cards** (People) lays out a sheet of cards.
- **More about a book**: a description and subjects from Open Library, plus look-up links (Goodreads, LibraryThing,
  WorldCat). **AR BookFind** is a link only: Renaissance's terms forbid automated access, so nothing is fetched from it.

### Reading levels (AR) and spreadsheets

AR BookFind has no public feed or import, and its terms forbid automated look-ups, so this site does not fetch from it.
Instead: the book page has an **Open AR BookFind** link (plus **Copy title** to paste into its search) and boxes to record the
**level, points and quiz number** you find there (the read-only guest sees them). **Library page -> Export / import** downloads
`library.csv` (one row per copy, with any reading level) and imports a CSV of `isbn, level, points[, quiz]` you made yourself
(for example from a spreadsheet or a Renaissance report you are entitled to export). Levels are stored in `reading-levels.json`
in the Add books data volume, keyed by ISBN, so they survive a Koha reinstall and are included in the usual backups of that folder.

### Live camera scanning (needs HTTPS)

Browsers only allow a live camera on HTTPS pages (or on the machine itself). Put the library site behind Caddy with a real
certificate and **Live scan** buttons appear: Add books (scan a stack of ISBNs one after another), Lend / return (live card or
phone-QR scan, live book check-out for the chosen person, live returns). Chrome on Android reads codes in the browser; other
browsers send small camera frames to the server's decoder a couple of times a second. On plain HTTP the photo buttons stay.

### Copying reading levels from AR BookFind

On the AR BookFind book page, select everything (Ctrl/Cmd+A), copy, and paste into the box on the book page here: the level,
points, quiz number and interest level fill in by themselves; check them and press Save.

### Tags, and borrowers signing in

- **Tags**: any number per book (to read, kids, signed...). Add and remove them on the book page; click one to see every
  book that has it; the Library page can filter by tag. They are stored in `tags.json` in the Add books data volume, which
  the usual backups of that folder include.
- **Borrowers sign in**: every person gets a login, **their library card number + a password**. Adding someone shows
  their password once (a different easy one like `maple482`, or the same one for everyone: People -> *Sign-in passwords for new
  people*). *Give everyone a sign-in* covers people added earlier; *New password* resets one person. A borrower who signs in
  sees the library and a **My books** page: what they have out, when each is due (or overdue), **Renew**, and **Change my
  password**. They cannot lend, edit or see other people. Passwords are Koha's own patron passwords; this stack relaxes Koha's
  default strength rule (4+ characters instead of 8 with upper/lower/digit) once, at install or update.
  Ten wrong guesses from one address locks sign-in attempts from it for five minutes.

### Reading levels: pop-up or in-page AR BookFind

The book page's AR box has **Open beside this page** (a pop-up window next to the book) and **Show it here** (AR BookFind inside the
page; some browsers block its cookies inside another page, then use the pop-up). Either copies the title first so you can paste
it into AR's search; AR's own page cannot be pre-filled from here.

### Same ports on every install

New installs of this stack use the same three ports whether you install it from the kiosk add-on or from `ubuntu-post-install`:
**8098** is the one to use (the Room for Books home page, with Koha behind the menu), 8099 is Add books direct, and 8097 is the
public catalogue, which stays closed. If one is taken, the next free port is used and the installer prints it. Existing installs
keep the ports they already have.

## HTTPS with Caddy (and the live camera scanner)

Phones only allow a live camera on an HTTPS page. One command adds Caddy in front of the library:

```bash
# a real domain that points at this machine (ports 80 and 443 reachable): the certificate is automatic
sudo ./install.sh --domain library.example.com

# a name only your own network knows (library.home.lan): Caddy makes its own certificate authority
sudo ./install.sh --domain library.home.lan --lan-tls     # then install caddy-root.crt on your phones
```

It writes `Caddyfile`, starts a `caddy` container (the compose `caddy` profile), sets `STAFF_URL=https://<name>` and closes the plain-HTTP
ports to the network (`BIND_ADDR=127.0.0.1`; add `--keep-direct` to leave them open). Then use `https://<name>/`: everything works
as before, and the **Live scan** buttons appear on Add books and Lend / return. Behind your own Caddy instead, point it at the library
port: `library.example.com { reverse_proxy <this machine>:8098 }` and set `STAFF_URL=https://library.example.com` in `.env`.
