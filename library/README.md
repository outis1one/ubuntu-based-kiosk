# Home library: Koha + Quick Add (Docker)

A self-hosted library catalogue you can set up in one command:

```bash
sudo ./install.sh
```

It installs Docker if it is missing, generates the passwords, builds the images,
starts everything and prints the addresses and your login. Running it again is safe;
it never overwrites your `.env` (passwords) or your data.

| What | Address | Login |
|---|---|---|
| **Catalogue** (public search, no login) | `http://<this machine>:8080` | none |
| **Staff interface** (cataloguing, labels, Z39.50) | `http://<this machine>:8081` | `admin` and the generated password |
| **Add books** (scan an ISBN) | `http://<this machine>:8082` | same login |

Ports move up to the next free number if one is taken; the final addresses are printed
at the end and by `sudo ./install.sh --status`.

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

Phone camera scanning is not built in (browsers only allow the camera on HTTPS or
`localhost`). A scanner-app that "types" the code into the box works.

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
