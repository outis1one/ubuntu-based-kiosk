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
3. Otherwise the record is added with the **next barcode number**, the Dewey (or LC) call
   number from the record, the item type chosen at the top (Book, Movie, Music, Game) and
   the shelf you picked.
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

## Printing labels

Quick Add shows the barcode range for the session ("Barcodes 12 to 27"). In the staff
interface open **Cataloging → Label creator → Print barcode range**, enter those numbers,
and pick a template and layout:

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

Print at 100% scale (not "fit to page") so the labels line up.

## Finding the books

The public catalogue searches title, author, subject and ISBN, and shows each copy's
availability, call number and **shelving location**.

On the Add books page, pick the **Shelf / room** before you scan; every book you add
gets it, and the page remembers your choice. Change it whenever you move to another shelf.
The list comes from the staff interface (*Administration → Authorized values → LOC*), which
starts with a few rooms such as Fiction, General stacks and Reference. Add your own there,
for example "Living room - bookcase 2".

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
