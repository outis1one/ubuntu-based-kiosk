#!/usr/bin/env python3
"""Quick Add - scan an ISBN, the book is in the catalogue.

A tiny web app that sits next to Koha. For each ISBN/UPC it:
  1. looks the item up (Z39.50 servers first, then Open Library over HTTPS),
  2. checks Koha for an existing copy,
  3. adds the record + an item (next free barcode) through Koha's REST API.

Standard library only; Z39.50 is done by shelling out to yaz-client.
"""
import base64
import hmac
import json
import os
import re
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KOHA_API = os.environ.get("KOHA_API", "http://koha:8081/api/v1").rstrip("/")
USER = os.environ.get("ADMIN_USER", "admin")
PASSWORD = os.environ.get("ADMIN_PASSWORD", "")
LIBRARY = os.environ.get("KOHA_LIBRARY", "HOME")
STAFF_PORT = os.environ.get("STAFF_PORT", "8081")
OPAC_PORT = os.environ.get("OPAC_PORT", "8080")
DATA_DIR = os.environ.get("DATA_DIR", "/data")
PORT = int(os.environ.get("PORT", "8082"))
SOURCES = [s.strip() for s in os.environ.get(
    "QUICKADD_SOURCES", "z3950:lx2.loc.gov:210/LCDB,openlibrary").split(",") if s.strip()]
Z3950_TIMEOUT = int(os.environ.get("Z3950_TIMEOUT", "12"))
ITEM_TYPES = {"BOOK": "Book", "DVD": "Movie", "CD": "Music", "GAME": "Game", "OTHER": "Other"}

NS = {"m": "http://www.loc.gov/MARC21/slim"}
ET.register_namespace("", NS["m"])
RECENT_FILE = os.path.join(DATA_DIR, "recent.json")
LOCK = threading.Lock()


# ---------------------------------------------------------------- identifiers
def clean_code(raw):
    code = re.sub(r"[\s-]", "", raw or "").upper()
    return code if re.fullmatch(r"[0-9]{8,14}|[0-9]{9}[0-9X]", code) else None


def isbn10_to_13(i10):
    body = "978" + i10[:9]
    s = sum(int(c) * (1 if n % 2 == 0 else 3) for n, c in enumerate(body))
    return body + str((10 - s % 10) % 10)


def isbn13_to_10(i13):
    if not i13.startswith("978"):
        return None
    body = i13[3:12]
    s = sum(int(c) * (10 - n) for n, c in enumerate(body))
    chk = (11 - s % 11) % 11
    return body + ("X" if chk == 10 else str(chk))


def is_isbn(code):
    return len(code) == 10 or (len(code) == 13 and code[:3] in ("978", "979"))


# -------------------------------------------------------------------- Z39.50
def z3950_search(spec, code):
    """spec = host:port/db. Returns MARCXML string or None."""
    host_port_db = spec
    attrs = ["@attr 1=7"] if is_isbn(code) else ["@attr 1=1007"]
    queries = [code]
    if len(code) == 13 and is_isbn(code):
        alt = isbn13_to_10(code)
        if alt:
            queries.append(alt)
    for q in queries:
        with tempfile.TemporaryDirectory() as tmp:
            dump = os.path.join(tmp, "rec.mrc")
            script = "format usmarc\nfind %s %s\nshow 1\nquit\n" % (attrs[0], q)
            try:
                out = subprocess.run(
                    ["yaz-client", "-m", dump, host_port_db], input=script,
                    capture_output=True, text=True, timeout=Z3950_TIMEOUT).stdout
            except (subprocess.TimeoutExpired, OSError):
                return None
            m = re.search(r"Number of hits: (\d+)", out)
            if not m or int(m.group(1)) == 0 or not os.path.exists(dump):
                if "Connection refused" in out or "Connecting...error" in out or "Unable to" in out:
                    return None
                continue
            raw = open(dump, "rb").read()
            args = ["yaz-marcdump", "-o", "marcxml"]
            if len(raw) > 9 and raw[9:10] == b" ":        # MARC-8 -> UTF-8
                args += ["-f", "MARC-8", "-t", "UTF-8", "-l", "9=97"]
            res = subprocess.run(args + [dump], capture_output=True, text=True, timeout=10)
            if res.returncode == 0 and "<record" in res.stdout:
                return res.stdout
    return None


# --------------------------------------------------------------- Open Library
def openlibrary_search(code):
    if not is_isbn(code):
        return None
    url = ("https://openlibrary.org/api/books?bibkeys=ISBN:%s&format=json&jscmd=data"
           % urllib.parse.quote(code))
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "library-quickadd/1.0"}), timeout=10) as r:
            data = json.load(r).get("ISBN:" + code)
    except (urllib.error.URLError, OSError, ValueError):
        return None
    if not data or not data.get("title"):
        return None
    rec = ET.Element("{%s}record" % NS["m"])
    ET.SubElement(rec, "{%s}leader" % NS["m"]).text = "00000nam a2200000 a 4500"

    def field(tag, subs, i1=" ", i2=" "):
        subs = [(c, str(v)) for c, v in subs if v]
        if not subs:                      # an empty datafield is invalid MARC
            return
        df = ET.SubElement(rec, "{%s}datafield" % NS["m"], tag=tag, ind1=i1, ind2=i2)
        for c, v in subs:
            ET.SubElement(df, "{%s}subfield" % NS["m"], code=c).text = v

    field("020", [("a", code)])
    dewey = (data.get("classifications") or {}).get("dewey_decimal_class") or []
    if dewey:
        field("082", [("a", dewey[0])], "0", "4")
    lcc = (data.get("classifications") or {}).get("lc_classifications") or []
    if lcc:
        field("050", [("a", lcc[0])], " ", "4")
    authors = data.get("authors") or []
    if authors:
        field("100", [("a", authors[0].get("name"))], "1")
    title = data["title"] + (": " + data["subtitle"] if data.get("subtitle") else "")
    field("245", [("a", title)], "1" if authors else "0", "0")
    pubs = [p.get("name") for p in data.get("publishers") or []]
    field("264", [("b", pubs[0] if pubs else None), ("c", data.get("publish_date"))], " ", "1")
    if data.get("number_of_pages"):
        field("300", [("a", "%s pages" % data["number_of_pages"])])
    for subj in (data.get("subjects") or [])[:6]:
        field("650", [("a", subj.get("name"))], " ", "0")
    return ET.tostring(rec, encoding="unicode")


# ----------------------------------------------------------- MARC XML helpers
def parse_marc(xml_text):
    root = ET.fromstring(xml_text)
    rec = root if root.tag.endswith("record") else root.find(".//m:record", NS)
    return rec


def sub(rec, tag, code):
    for df in rec.findall("m:datafield[@tag='%s']" % tag, NS):
        for sf in df.findall("m:subfield[@code='%s']" % code, NS):
            if sf.text:
                return sf.text.strip()
    return ""


def describe(rec):
    title = " ".join(x for x in (sub(rec, "245", "a"), sub(rec, "245", "b")) if x).rstrip(" /:;,")
    author = sub(rec, "100", "a").rstrip(",.") or sub(rec, "110", "a").rstrip(",.")
    year = re.search(r"\d{4}", sub(rec, "264", "c") or sub(rec, "260", "c") or "")
    return {"title": title or "(untitled)", "author": author, "year": year.group(0) if year else "",
            "publisher": (sub(rec, "264", "b") or sub(rec, "260", "b")).rstrip(" ,:;")}


def call_number(rec, author):
    dewey = sub(rec, "082", "a").replace("/", "")
    if dewey:
        cutter = sub(rec, "082", "b")
        if not cutter and author:
            cutter = re.sub(r"[^A-Za-z]", "", author.split(",")[0])[:3].upper()
        return (dewey + " " + cutter).strip()
    lc = sub(rec, "050", "a")
    if lc:
        return (lc + " " + sub(rec, "050", "b")).strip()
    return ""


def set_item_type(rec, itype):
    for df in rec.findall("m:datafield[@tag='942']", NS):
        rec.remove(df)
    df = ET.SubElement(rec, "{%s}datafield" % NS["m"], tag="942", ind1=" ", ind2=" ")
    ET.SubElement(df, "{%s}subfield" % NS["m"], code="c").text = itype


def ensure_identifier(rec, code):
    """Make sure the scanned code is on the record, so scanning it again is
    recognised as a duplicate (a Z39.50 hit for a UPC often lacks the UPC)."""
    wanted = {code}
    if len(code) == 13 and code[:3] == "978":
        wanted.add(isbn13_to_10(code) or code)
    elif len(code) == 10:
        wanted.add(isbn10_to_13(code))
    for tag in ("020", "024"):
        for df in rec.findall("m:datafield[@tag='%s']" % tag, NS):
            for sf in df.findall("m:subfield[@code='a']", NS):
                if re.sub(r"[^0-9X]", "", (sf.text or "").upper())[:13] in wanted:
                    return
    tag, i1 = ("020", " ") if is_isbn(code) else ("024", "1")
    df = ET.SubElement(rec, "{%s}datafield" % NS["m"], tag=tag, ind1=i1, ind2=" ")
    ET.SubElement(df, "{%s}subfield" % NS["m"], code="a").text = code


def manual_record(code, title, author, year, publisher):
    rec = ET.Element("{%s}record" % NS["m"])
    ET.SubElement(rec, "{%s}leader" % NS["m"]).text = "00000nam a2200000 a 4500"

    def field(tag, subs, i1=" ", i2=" "):
        subs = [(c, str(v)) for c, v in subs if v]
        if not subs:                      # an empty datafield is invalid MARC
            return
        df = ET.SubElement(rec, "{%s}datafield" % NS["m"], tag=tag, ind1=i1, ind2=i2)
        for c, v in subs:
            ET.SubElement(df, "{%s}subfield" % NS["m"], code=c).text = v

    if code:
        field("020" if is_isbn(code) else "024", [("a", code)], " " if is_isbn(code) else "1")
    if author:
        field("100", [("a", author)], "1")
    field("245", [("a", title)], "1" if author else "0", "0")
    field("264", [("b", publisher), ("c", year)], " ", "1")
    return rec


# ------------------------------------------------------------------ Koha API
class KohaError(Exception):
    def __init__(self, status, body):
        super().__init__("Koha API %s: %s" % (status, body[:200]))
        self.status, self.body = status, body


def koha(method, path, body=None, ctype="application/json", headers=None, query=None):
    url = KOHA_API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else None)
    h = {"Authorization": "Basic " + base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode(),
         "Accept": "application/json"}
    if data is not None:
        h["Content-Type"] = ctype
    h.update(headers or {})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=h), timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise KohaError(e.code, e.read().decode("utf8", "replace"))
    except (urllib.error.URLError, OSError) as e:
        raise KohaError(503, str(e))


_LOC_CACHE = {"at": 0.0, "value": []}


def get_locations():
    """Shelving locations (Koha authorised-value category LOC), cached for 30 s."""
    if time.time() - _LOC_CACHE["at"] < 30:
        return _LOC_CACHE["value"]
    try:
        vals = koha("GET", "/authorised_value_categories/LOC/authorised_values") or []
        _LOC_CACHE["value"] = [{"value": v["value"], "label": v.get("description") or v["value"]} for v in vals]
        _LOC_CACHE["at"] = time.time()
    except KohaError:
        pass
    return _LOC_CACHE["value"]


def valid_location(code):
    return code if code and any(l["value"] == code for l in get_locations()) else None


def find_existing(code):
    variants = {code}
    if len(code) == 13:
        alt = isbn13_to_10(code)
        if alt:
            variants.add(alt)
    elif len(code) == 10:
        variants.add(isbn10_to_13(code))
    for v in variants:
        q = {"-or": [{"isbn": {"-like": "%" + v + "%"}}, {"ean": {"-like": "%" + v + "%"}}]}
        res = koha("GET", "/biblios", query={"q": json.dumps(q), "_per_page": "1"})
        if res:
            b = res[0]
            items = koha("GET", "/biblios/%s/items" % b["biblio_id"]) or []
            return {"biblio_id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"),
                    "author": b.get("author") or "", "copies": len(items)}
    return None


def next_barcode():
    last = koha("GET", "/items", query={"_per_page": "1", "_order_by": "-item_id"})
    n = 0
    if last and re.fullmatch(r"\d+", last[0].get("external_id") or ""):
        n = int(last[0]["external_id"])
    return max(n, state_counter()) + 1


def state_counter():
    try:
        return int(open(os.path.join(DATA_DIR, "barcode")).read())
    except (OSError, ValueError):
        return 0


def save_counter(n):
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        open(os.path.join(DATA_DIR, "barcode"), "w").write(str(n))
    except OSError:
        pass


def add_item(biblio_id, itype, callnum, location=None):
    """Create an item with the next free barcode (retrying on collisions)."""
    start = next_barcode()
    for attempt in range(10):
        bc = str(start + attempt)
        try:
            item = koha("POST", "/biblios/%s/items" % biblio_id, {
                "external_id": bc, "item_type_id": itype, "home_library_id": LIBRARY,
                "holding_library_id": LIBRARY, "callnumber": callnum or None,
                "location": location})
            save_counter(start + attempt)
            return item
        except KohaError as e:
            if e.status == 409 or "Duplicate" in e.body:
                continue
            raise
    raise KohaError(409, "could not find a free barcode")


# --------------------------------------------------------------------- state
def load_recent():
    try:
        return json.load(open(RECENT_FILE))
    except (OSError, ValueError):
        return []


def remember(entry):
    with LOCK:
        rec = load_recent()
        rec.insert(0, entry)
        try:
            os.makedirs(DATA_DIR, exist_ok=True)
            json.dump(rec[:300], open(RECENT_FILE, "w"))
        except OSError:
            pass


def forget(item_id):
    with LOCK:
        rec = [r for r in load_recent() if r.get("item_id") != item_id]
        try:
            json.dump(rec, open(RECENT_FILE, "w"))
        except OSError:
            pass


# ----------------------------------------------------------------- operations
def lookup(code):
    """Try each configured source; returns (xml, source_name) or (None, None)."""
    for src in SOURCES:
        xml = None
        if src.startswith("z3950:"):
            xml = z3950_search(src[len("z3950:"):], code)
            name = "Z39.50 " + src.split(":", 1)[1].split("/")[0].split(":")[0]
        elif src == "openlibrary":
            xml = openlibrary_search(code)
            name = "Open Library"
        if xml:
            return xml, name
    return None, None


def op_add(payload):
    code = clean_code(payload.get("code"))
    itype = payload.get("type") if payload.get("type") in ITEM_TYPES else "BOOK"
    location = valid_location(payload.get("location"))
    if not code:
        return 400, {"status": "invalid", "message": "That doesn't look like an ISBN or barcode."}
    with LOCK:
        existing = find_existing(code)
    if existing and not payload.get("copy"):
        return 200, dict(existing, status="duplicate", code=code)
    if existing:                                    # add another copy of a known title
        with LOCK:
            item = add_item(existing["biblio_id"], itype, None, location)
        entry = entry_for(code, existing["title"], existing["author"], item, existing["biblio_id"], "extra copy")
        remember(entry)
        return 200, dict(entry, status="added")
    xml, source = lookup(code)
    if not xml:
        return 200, {"status": "notfound", "code": code}
    rec = parse_marc(xml)
    info = describe(rec)
    ensure_identifier(rec, code)
    set_item_type(rec, itype)
    with LOCK:
        bib = koha("POST", "/biblios", ET.tostring(rec, encoding="utf-8"), "application/marcxml+xml",
                   {"x-confirm-not-duplicate": "1"})
        item = add_item(bib["id"], itype, call_number(rec, info["author"]), location)
    entry = entry_for(code, info["title"], info["author"], item, bib["id"], source)
    remember(entry)
    return 200, dict(entry, status="added")


def op_manual(payload):
    title = (payload.get("title") or "").strip()
    if not title:
        return 400, {"status": "invalid", "message": "A title is required."}
    code = clean_code(payload.get("code"))
    itype = payload.get("type") if payload.get("type") in ITEM_TYPES else "BOOK"
    location = valid_location(payload.get("location"))
    rec = manual_record(code, title[:240], (payload.get("author") or "").strip()[:120],
                        (payload.get("year") or "").strip()[:8], (payload.get("publisher") or "").strip()[:120])
    set_item_type(rec, itype)
    with LOCK:
        bib = koha("POST", "/biblios", ET.tostring(rec, encoding="utf-8"), "application/marcxml+xml",
                   {"x-confirm-not-duplicate": "1"})
        item = add_item(bib["id"], itype, None, location)
    entry = entry_for(code or "", title, payload.get("author") or "", item, bib["id"], "typed in")
    remember(entry)
    return 200, dict(entry, status="added")


def entry_for(code, title, author, item, biblio_id, source):
    return {"time": int(time.time()), "code": code, "title": title, "author": author,
            "barcode": item.get("external_id"), "callnumber": item.get("callnumber") or "",
            "item_id": item.get("item_id"), "biblio_id": biblio_id, "source": source,
            "location": next((l["label"] for l in get_locations() if l["value"] == item.get("location")), "")}


def op_undo(payload):
    item_id = payload.get("item_id")
    biblio_id = payload.get("biblio_id")
    if not isinstance(item_id, int) or not isinstance(biblio_id, int):
        return 400, {"status": "invalid"}
    with LOCK:
        koha("DELETE", "/items/%d" % item_id)
        remaining = koha("GET", "/biblios/%d/items" % biblio_id) or []
        if not remaining:                           # drop the now-empty record too
            try:
                koha("DELETE", "/biblios/%d" % biblio_id)
            except KohaError:
                pass
    forget(item_id)
    return 200, {"status": "undone"}


# ----------------------------------------------------------------------- HTTP
INDEX = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html"), "rb").read()


class Handler(BaseHTTPRequestHandler):
    server_version = "QuickAdd/1.0"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype="application/json", extra=None):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; img-src 'self' https://covers.openlibrary.org data:; "
                         "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        if not PASSWORD:
            return False
        header = self.headers.get("Authorization", "")
        if header.startswith("Basic "):
            try:
                u, _, p = base64.b64decode(header[6:]).decode().partition(":")
                ok_u = hmac.compare_digest(u.encode(), USER.encode())
                ok_p = hmac.compare_digest(p.encode(), PASSWORD.encode())
                return ok_u and ok_p
            except (ValueError, UnicodeDecodeError):
                return False
        return False

    def _guard(self):
        if not self._authed():
            self._send(401, b"Login required", "text/plain",
                       {"WWW-Authenticate": 'Basic realm="Library quick add"'})
            return False
        return True

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, b"ok", "text/plain")
        if not self._guard():
            return
        path = self.path.split("?")[0]
        if path == "/":
            return self._send(200, INDEX, "text/html; charset=utf-8")
        if path == "/api/state":
            return self._send(200, {"recent": load_recent()[:100], "types": ITEM_TYPES,
                                    "library": LIBRARY, "locations": get_locations(), "staff_port": STAFF_PORT, "opac_port": OPAC_PORT,
                                    "sources": [s.split(":", 1)[0] if s.startswith("z3950") else s for s in SOURCES]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._guard():
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 20000:
                return self._send(413, {"error": "too large"})
            payload = json.loads(self.rfile.read(length) or b"{}")
            ops = {"/api/add": op_add, "/api/manual": op_manual, "/api/undo": op_undo}
            fn = ops.get(self.path)
            if not fn:
                return self._send(404, {"error": "not found"})
            code, body = fn(payload)
            self._send(code, body)
        except KohaError as e:
            msg = ("Koha is still starting up - try again in a minute." if e.status == 503
                   else "Koha refused that: %s" % e.body[:160])
            self._send(502, {"status": "error", "message": msg})
        except (ValueError, ET.ParseError):
            self._send(400, {"status": "invalid", "message": "Bad request."})
        except Exception as e:  # keep the scanner loop alive whatever happens
            self._send(500, {"status": "error", "message": "Unexpected error: %s" % e})


if __name__ == "__main__":
    if not PASSWORD:
        raise SystemExit("ADMIN_PASSWORD is required")
    os.makedirs(DATA_DIR, exist_ok=True)
    print("quick add listening on :%d  sources=%s" % (PORT, SOURCES), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
