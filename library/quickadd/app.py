#!/usr/bin/env python3
"""Quick Add - scan an ISBN, the book is in the catalogue.

A tiny web app that sits next to Koha. For each ISBN/UPC it:
  1. looks the item up (Z39.50 servers first, then Open Library over HTTPS),
  2. checks Koha for an existing copy,
  3. adds the record + an item (next free barcode) through Koha's REST API.

Standard library only; Z39.50 is done by shelling out to yaz-client.
"""
import base64
import hashlib
from concurrent.futures import ThreadPoolExecutor
import hmac
import json
import os
import re
import secrets
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
# Optional read-only login to hand out: may open the page and search, nothing else.
# Single sign-on: requests that reach us through the staff site's web server carry this secret in
# X-Quickadd-Proxy; we then ask Koha whether the browser's login cookie is a staff user who may edit
# the catalogue. Unset = feature off (only the Basic logins below work).
SSO_SECRET = os.environ.get("SSO_SECRET", "")
KOHA_RETURN_URL = KOHA_API.rsplit("/api/v1", 1)[0] + "/cgi-bin/koha/quickadd-return.pl"
KOHA_SESSION_URL = KOHA_API.rsplit("/api/v1", 1)[0] + "/cgi-bin/koha/svc/quickadd-session"
VIEWER_USER = os.environ.get("VIEWER_USER", "")
VIEWER_PASSWORD = os.environ.get("VIEWER_PASSWORD", "")
LIBRARY = os.environ.get("KOHA_LIBRARY", "HOME")
STAFF_PORT = os.environ.get("STAFF_PORT", "8081")
OPAC_PORT = os.environ.get("OPAC_PORT", "8080")
# Set these when the site is behind a reverse proxy (different hostnames than host:port).
OPAC_URL = os.environ.get("OPAC_URL", "").rstrip("/")
STAFF_URL = os.environ.get("STAFF_URL", "").rstrip("/")
DATA_DIR = os.environ.get("DATA_DIR", "/data")
PORT = int(os.environ.get("PORT", "8082"))
SOURCES = [s.strip() for s in os.environ.get(
    "QUICKADD_SOURCES", "z3950:lx2.loc.gov:210/LCDB,openlibrary").split(",") if s.strip()]
Z3950_TIMEOUT = int(os.environ.get("Z3950_TIMEOUT", "12"))
DEFAULT_TYPES = {"BOOK": "Book", "DVD": "Movie", "CD": "Music", "GAME": "Game", "OTHER": "Other"}

NS = {"m": "http://www.loc.gov/MARC21/slim"}
ET.register_namespace("", NS["m"])
RECENT_FILE = os.path.join(DATA_DIR, "recent.json")


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


def koha(method, path, body=None, ctype="application/json", headers=None, query=None, raw=False):
    url = KOHA_API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else None)
    h = {"Authorization": "Basic " + base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode(),
         "Accept": "application/json"}
    if data is not None:
        h["Content-Type"] = ctype
    h.update(headers or {})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=h), timeout=30) as r:
            payload = r.read()
            if raw:
                return payload
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        raise KohaError(e.code, e.read().decode("utf8", "replace"))
    except (urllib.error.URLError, OSError) as e:
        raise KohaError(503, str(e))


_TYPE_CACHE = {"at": 0.0, "value": dict(DEFAULT_TYPES)}


def get_item_types():
    """Item types as Koha has them (so types added at install or later in Koha
    appear here), cached for 60 s; falls back to the built-in five."""
    if time.time() - _TYPE_CACHE["at"] < 60:
        return _TYPE_CACHE["value"]
    try:
        vals = koha("GET", "/item_types", query={"_per_page": "100"}) or []
        found = {v["item_type_id"]: v.get("description") or v["item_type_id"] for v in vals}
        if found:
            _TYPE_CACHE["value"] = found
        _TYPE_CACHE["at"] = time.time()
    except KohaError:
        pass
    return _TYPE_CACHE["value"]


def valid_type(code):
    types = get_item_types()
    return code if code in types else ("BOOK" if "BOOK" in types else next(iter(types)))


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


_COLL_CACHE = {"at": 0.0, "value": []}


def get_collections():
    """Collections (Koha authorised-value category CCODE): 'Kids', 'Cookbooks', ... one per copy."""
    if time.time() - _COLL_CACHE["at"] < 30:
        return _COLL_CACHE["value"]
    try:
        vals = koha("GET", "/authorised_value_categories/CCODE/authorised_values") or []
        _COLL_CACHE["value"] = [{"value": v["value"], "label": v.get("description") or v["value"]} for v in vals]
        _COLL_CACHE["at"] = time.time()
    except KohaError:
        pass
    return _COLL_CACHE["value"]


def valid_collection(code):
    return code if code and any(c["value"] == code for c in get_collections()) else None


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


# ------------------------------------------------------------------- settings
SETTINGS_FILE = os.path.join(DATA_DIR, "settings.json")
COUNTER_FILE = os.path.join(DATA_DIR, "counter.json")
MIN_WIDTH, MAX_WIDTH = 7, 10     # 6 all-digit Code 39 symbols can be misread as Code 32 by some scanners
DEFAULT_SETTINGS = {"barcode_mode": "auto", "width": MIN_WIDTH, "location": "", "patron_password_mode": "generated", "patron_password": ""}
BARCODE_MODES = ("auto", "scan", "none")
LOCK = threading.RLock()


def load_settings():
    s = dict(DEFAULT_SETTINGS)
    try:
        s.update(json.load(open(SETTINGS_FILE)))
    except (OSError, ValueError):
        pass
    try:
        s["width"] = min(max(int(s["width"]), MIN_WIDTH), MAX_WIDTH)
    except (TypeError, ValueError):
        s["width"] = MIN_WIDTH
    return s


def save_json(path, data):
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def clean_settings(payload, current):
    s = dict(current)
    if payload.get("barcode_mode") in BARCODE_MODES:
        s["barcode_mode"] = payload["barcode_mode"]
    if "width" in payload:
        try:
            s["width"] = min(max(int(payload["width"]), MIN_WIDTH), MAX_WIDTH)
        except (TypeError, ValueError):
            pass
    if payload.get("patron_password_mode") in ("generated", "same"):
        s["patron_password_mode"] = payload["patron_password_mode"]
    if "patron_password" in payload:
        pw = str(payload["patron_password"] or "").strip()
        if pw == "" or 4 <= len(pw) <= 40:
            s["patron_password"] = pw
    if "location" in payload:
        loc = payload["location"] or ""
        if loc == "" or valid_location(loc):
            s["location"] = loc
    return s


# ------------------------------------------------------------------ barcodes
# Fixed-width digits ("000042"): Koha's "Print barcode range" needs both ends
# the same length, and it cannot take a prefix, so neither is offered.
def fmt_barcode(n, s):
    return "%0*d" % (s["width"], n)


def scan_max():
    """Highest all-digit barcode already in Koha (paged; only when needed)."""
    mx, page = 0, 1
    while True:
        items = koha("GET", "/items", query={"_per_page": "100", "_page": str(page), "_order_by": "item_id"}) or []
        for it in items:
            bc = it.get("external_id") or ""
            if bc.isdigit():
                mx = max(mx, int(bc))
        if len(items) < 100:
            return mx
        page += 1


def read_counter():
    try:
        return int(json.load(open(COUNTER_FILE))["n"])
    except (OSError, ValueError, KeyError, TypeError):
        n = scan_max()               # first use (or lost state): start after what exists
        save_json(COUNTER_FILE, {"n": n})
        return n


def peek_next():
    with LOCK:
        return read_counter() + 1


def reserve(count):
    """Reserve `count` consecutive numbers and return the first. Reserved
    numbers are never handed out again - a label may already be printed."""
    with LOCK:
        n = read_counter()
        save_json(COUNTER_FILE, {"n": n + count})
        return n + 1


def add_item(biblio_id, itype, callnum, location, mode, scanned=None):
    s = load_settings()
    base = {"item_type_id": itype, "home_library_id": LIBRARY, "holding_library_id": LIBRARY,
            "callnumber": callnum or None, "location": location or None}
    path = "/biblios/%s/items" % biblio_id
    if mode == "none":
        return koha("POST", path, base)
    if mode == "scan":
        return koha("POST", path, dict(base, external_id=scanned))
    for _ in range(25):
        bc = fmt_barcode(reserve(1), s)
        try:
            return koha("POST", path, dict(base, external_id=bc))
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
            save_json(RECENT_FILE, rec[:300])
        except OSError:
            pass


def forget(item_id):
    with LOCK:
        rec = [r for r in load_recent() if r.get("item_id") != item_id]
        try:
            save_json(RECENT_FILE, rec)
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


PENDING = {}            # token -> (expires, plan): waiting for a scanned sticker
PENDING_TTL = 1800


def prune_pending():
    now = time.time()
    for k in [k for k, (exp, _) in PENDING.items() if exp < now]:
        del PENDING[k]


def chosen_location(payload):
    """The shelf for this add: an explicit choice wins, else the saved default."""
    if "location" in payload:
        return valid_location(payload.get("location"))
    return valid_location(load_settings().get("location"))


def make_plan(payload):
    """Look the code up. Returns ("done", http_status, body) or ("plan", plan)."""
    code = clean_code(payload.get("code"))
    itype = valid_type(payload.get("type"))
    if not code:
        return "done", 400, {"status": "invalid", "message": "That doesn't look like an ISBN or barcode."}
    location = chosen_location(payload)
    with LOCK:
        existing = find_existing(code)
    if existing and not payload.get("copy"):
        return "done", 200, dict(existing, status="duplicate", code=code)
    if existing:
        return "plan", {"code": code, "itype": itype, "location": location, "existing": existing,
                        "xml": None, "title": existing["title"], "author": existing["author"],
                        "callnum": None, "source": "extra copy"}
    xml, source = lookup(code)
    if not xml:
        return "done", 200, {"status": "notfound", "code": code}
    rec = parse_marc(xml)
    info = describe(rec)
    ensure_identifier(rec, code)
    set_item_type(rec, itype)
    return "plan", {"code": code, "itype": itype, "location": location, "existing": None,
                    "xml": ET.tostring(rec, encoding="utf-8"), "title": info["title"], "author": info["author"],
                    "callnum": call_number(rec, info["author"]), "source": source}


def commit(plan, scanned=None):
    mode = load_settings()["barcode_mode"]
    with LOCK:
        created = None
        if plan["existing"]:
            biblio_id = plan["existing"]["biblio_id"]
        else:
            bib = koha("POST", "/biblios", plan["xml"], "application/marcxml+xml", {"x-confirm-not-duplicate": "1"})
            biblio_id = created = bib["id"]
        try:
            item = add_item(biblio_id, plan["itype"], plan["callnum"], plan["location"], mode, scanned)
        except KohaError:
            if created:                       # don't leave an item-less record behind
                try:
                    koha("DELETE", "/biblios/%s" % created)
                except KohaError:
                    pass
            raise
    entry = entry_for(plan["code"], plan["title"], plan["author"], item, biblio_id, plan["source"])
    remember(entry)
    prefetch_cover(plan["code"])
    return dict(entry, status="added")


def need_barcode(plan):
    token = secrets.token_urlsafe(12)
    prune_pending()
    PENDING[token] = (time.time() + PENDING_TTL, plan)
    return 200, {"status": "need_barcode", "token": token, "code": plan["code"],
                 "title": plan["title"], "author": plan["author"]}


def finish_or_ask(plan):
    if load_settings()["barcode_mode"] == "scan":
        return need_barcode(plan)
    return 200, commit(plan)


def op_add(payload):
    kind, *rest = make_plan(payload)
    if kind == "done":
        return rest[0], rest[1]
    return finish_or_ask(rest[0])


def op_manual(payload):
    title = (payload.get("title") or "").strip()
    if not title:
        return 400, {"status": "invalid", "message": "A title is required."}
    code = clean_code(payload.get("code"))
    itype = valid_type(payload.get("type"))
    rec = manual_record(code, title[:240], (payload.get("author") or "").strip()[:120],
                        (payload.get("year") or "").strip()[:8], (payload.get("publisher") or "").strip()[:120])
    set_item_type(rec, itype)
    plan = {"code": code or "", "itype": itype, "location": chosen_location(payload), "existing": None,
            "xml": ET.tostring(rec, encoding="utf-8"), "title": title, "author": (payload.get("author") or "").strip(),
            "callnum": None, "source": "typed in"}
    return finish_or_ask(plan)


STICKER_RE = re.compile(r"[A-Za-z0-9.$/+% -]{1,32}")


def op_finish(payload):
    """Second step of 'scan a pre-printed sticker' mode."""
    token = payload.get("token")
    barcode = (payload.get("barcode") or "").strip()
    prune_pending()
    entry = PENDING.get(token)
    if not entry:
        return 200, {"status": "error", "message": "That one timed out - scan the ISBN again."}
    if not STICKER_RE.fullmatch(barcode):
        return 200, {"status": "barcode_invalid", "token": token, "message": "That barcode has characters Koha can't use."}
    try:
        result = commit(entry[1], barcode)
    except KohaError as e:
        if e.status == 409 or "Duplicate" in e.body:
            return 200, {"status": "barcode_taken", "token": token, "barcode": barcode}
        raise
    PENDING.pop(token, None)
    return 200, result


def op_cancel(payload):
    PENDING.pop(payload.get("token"), None)
    return 200, {"status": "cancelled"}


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


# ----------------------------------------------------------- settings / tools
def items_without_barcode():
    found, page = [], 1
    while len(found) < 5000:
        chunk = koha("GET", "/items", query={"q": json.dumps({"external_id": None}), "_per_page": "100",
                                              "_page": str(page), "_order_by": "item_id"}) or []
        found += chunk
        if len(chunk) < 100:
            break
        page += 1
    return found


def settings_view():
    s = load_settings()
    try:
        missing = len(items_without_barcode())
    except KohaError:
        missing = None
    return {"settings": s, "next": fmt_barcode(peek_next(), s) if s["barcode_mode"] == "auto" else None,
            "without_barcode": missing, "locations": get_locations()}


def op_settings(payload):
    with LOCK:
        s = clean_settings(payload, load_settings())
        save_json(SETTINGS_FILE, s)
    return 200, settings_view()


def op_reserve(payload):
    try:
        count = int(payload.get("count"))
    except (TypeError, ValueError):
        count = 0
    if not 1 <= count <= 2000:
        return 400, {"status": "invalid", "message": "Choose between 1 and 2000."}
    s = load_settings()
    first = reserve(count)
    return 200, {"status": "reserved", "count": count, "first": fmt_barcode(first, s),
                 "last": fmt_barcode(first + count - 1, s)}


def op_assign(payload):
    """Give a barcode to every item that has none."""
    s = load_settings()
    with LOCK:
        items = items_without_barcode()
        if not items:
            return 200, {"status": "assigned", "count": 0}
        first = reserve(len(items))
        for i, it in enumerate(items):
            koha("PUT", "/biblios/%s/items/%s" % (it["biblio_id"], it["item_id"]), {
                "external_id": fmt_barcode(first + i, s), "item_type_id": it["item_type_id"],
                "home_library_id": it["home_library_id"], "holding_library_id": it["holding_library_id"]})
    return 200, {"status": "assigned", "count": len(items), "first": fmt_barcode(first, s),
                 "last": fmt_barcode(first + len(items) - 1, s)}


# ------------------------------------------------------------------- search
def item_status(it):
    if it.get("lost_status"):
        return "Lost"
    if it.get("withdrawn"):
        return "Withdrawn"
    if it.get("checked_out_date"):
        return "Checked out"
    if it.get("damaged_status"):
        return "Damaged"
    return "On shelf"


def op_search(term):
    """Find books by title, author or ISBN; each result lists its copies with shelf and status."""
    term = re.sub(r"[%_\\]", "", term or "").strip()[:80]
    if len(term) < 2:
        return {"results": []}
    like = {"-like": "%" + term + "%"}
    q = {"-or": [{"title": like}, {"author": like}, {"isbn": like}, {"ean": like}]}
    biblios = koha("GET", "/biblios", query={"q": json.dumps(q), "_per_page": "25", "_order_by": "title"}) or []
    if not biblios:
        return {"results": []}
    ids = [b["biblio_id"] for b in biblios]
    items = koha("GET", "/items", query={"q": json.dumps({"biblio_id": ids}), "_per_page": "500"}) or []
    where = {l["value"]: l["label"] for l in get_locations()}
    by_bib = {}
    for it in items:
        by_bib.setdefault(it["biblio_id"], []).append({
            "barcode": it.get("external_id"), "callnumber": it.get("callnumber") or "",
            "location": where.get(it.get("location"), ""), "status": item_status(it)})
    return {"results": [{
        "biblio_id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"), "author": b.get("author") or "",
        "year": b.get("copyright_date") or "", "copies": by_bib.get(b["biblio_id"], [])} for b in biblios]}


# ------------------------------------------------------------ library / book page
PAGE_SIZE = 48
ITEM_FILTER_CAP = 2000


def _shape_book(b, items, where):
    mine = [i for i in items if i["biblio_id"] == b["biblio_id"]]
    out = sum(1 for i in mine if item_status(i) == "Checked out")
    shelves = sorted({where.get(i.get("location"), "") for i in mine} - {""})
    colls = {c["value"]: c["label"] for c in get_collections()}
    collections = sorted({colls.get(i.get("collection_code"), "") for i in mine} - {""})
    return {"cover": cover_key(b.get("isbn"), b["biblio_id"]), "tags": _tags_load().get(str(b["biblio_id"]), []), "collections": collections, "id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"), "author": b.get("author") or "",
            "year": b.get("copyright_date") or "", "isbn": b.get("isbn") or "", "type": b.get("item_type") or "",
            "copies": len(mine), "out": out, "shelves": shelves,
            "callnumber": next((i.get("callnumber") for i in mine if i.get("callnumber")), "") or ""}


def _extra_matches(term):
    """Book ids whose tag, shelf/room or collection name contains the search words (so one box finds them all)."""
    t = term.lower()
    ids = {int(k) for k, v in _tags_load().items() if any(t in x.lower() for x in v)}
    locs = [l["value"] for l in get_locations() if t in l["label"].lower() or t == l["value"].lower()]
    colls = [c["value"] for c in get_collections() if t in c["label"].lower() or t == c["value"].lower()]
    conds = ([{"location": locs}] if locs else []) + ([{"collection_code": colls}] if colls else [])
    if re.fullmatch(r"[A-Za-z0-9-]{3,40}", term):          # a scanned item barcode finds its book
        conds.append({"external_id": term})
    if conds:
        try:
            its = koha("GET", "/items", query={"q": json.dumps(conds[0] if len(conds) == 1 else {"-or": conds}),
                                               "_per_page": str(ITEM_FILTER_CAP)}) or []
            ids |= {i["biblio_id"] for i in its}
        except KohaError:
            pass
    return sorted(ids)[:ITEM_FILTER_CAP]


def op_library(qs):
    """The Library grid: filter by shelf / format / status, search, sort, page."""
    def one(k):
        return (qs.get(k) or [""])[0]
    term = re.sub(r"[%_\\]", "", one("q")).strip()[:80]
    shelf, itype, status, coll, tag = one("shelf"), one("type"), one("status"), one("collection"), one("tag")
    sort = one("sort") or "title"
    try:
        page = max(1, int(one("page") or 1))
    except ValueError:
        page = 1
    conds = []
    if term:
        like = {"-like": "%" + term + "%"}
        match = [{"title": like}, {"author": like}, {"isbn": like}, {"ean": like}]
        extra = _extra_matches(term)
        if extra:
            match.append({"biblio_id": extra})
        conds.append({"-or": match})
    if tag:
        ids_t = sorted(int(k) for k, v in _tags_load().items() if any(t.lower() == tag.lower() for t in v))
        if not ids_t:
            return {"books": [], "page": page, "more": False}
        conds.append({"biblio_id": ids_t})
    order = {"title": "title", "author": "author", "new": "-biblio_id"}.get(sort, "title")
    item_q = {}
    if shelf == "-":
        item_q["location"] = None
    elif shelf:
        item_q["location"] = shelf
    if itype:
        item_q["item_type_id"] = itype
    if coll == "-":
        item_q["collection_code"] = None
    elif coll:
        item_q["collection_code"] = coll
    if status == "out":
        item_q["checked_out_date"] = {"!=": None}
    elif status == "in":
        item_q["checked_out_date"] = None
    query = {"_order_by": order}
    if item_q:
        its = koha("GET", "/items", query={"q": json.dumps(item_q), "_per_page": str(ITEM_FILTER_CAP)}) or []
        ids = sorted({i["biblio_id"] for i in its})
        if not ids:
            return {"books": [], "page": page, "more": False}
        conds.append({"biblio_id": ids})
    if conds:
        query["q"] = json.dumps(conds[0] if len(conds) == 1 else {"-and": conds})
    query.update({"_per_page": str(PAGE_SIZE + 1), "_page": str(page)})
    books = koha("GET", "/biblios", query=query) or []
    more = len(books) > PAGE_SIZE
    books = books[:PAGE_SIZE]
    if not books:
        return {"books": [], "page": page, "more": False}
    ids = [b["biblio_id"] for b in books]
    items = koha("GET", "/items", query={"q": json.dumps({"biblio_id": ids}), "_per_page": "1000"}) or []
    where = {l["value"]: l["label"] for l in get_locations()}
    return {"books": [_shape_book(b, items, where) for b in books], "page": page, "more": more}


def _checkout_info(item_ids, names):
    """item_id -> {who, due} for items currently out (staff only)."""
    if not item_ids:
        return {}
    cos = koha("GET", "/checkouts", query={"q": json.dumps({"item_id": item_ids}), "_per_page": "100"}) or []
    out = {}
    for c in cos:
        who = ""
        if names:
            try:
                p = koha("GET", "/patrons/%s" % c["patron_id"])
                who = ("%s %s" % (p.get("firstname") or "", p.get("surname") or "")).strip()
            except KohaError:
                pass
        out[c["item_id"]] = {"who": who, "patron_id": c["patron_id"], "due": (c.get("due_date") or "")[:10],
                             "checkout_id": c["checkout_id"]}
    return out


def op_book(biblio_id, staff, patron_id=None):
    # independent Koha calls run side by side (each takes a fraction of a second on small machines)
    with ThreadPoolExecutor(max_workers=3) as ex:
        f_bib = ex.submit(koha, "GET", "/biblios/%d" % biblio_id)
        f_items = ex.submit(koha, "GET", "/biblios/%d/items" % biblio_id)
        f_holds = ex.submit(koha, "GET", "/holds", query={"q": json.dumps({"biblio_id": biblio_id}), "_per_page": "50"})
        b = f_bib.result()
        items = f_items.result() or []
        try:
            raw_holds = f_holds.result() or []
        except KohaError:
            raw_holds = []
    where = {l["value"]: l["label"] for l in get_locations()}
    out = _checkout_info([i["item_id"] for i in items if item_status(i) == "Checked out"], staff)
    copies = []
    for i in items:
        c = {"item_id": i["item_id"], "barcode": i.get("external_id") or "", "callnumber": i.get("callnumber") or "",
             "shelf": i.get("location") or "", "shelf_label": where.get(i.get("location"), ""),
             "collection": i.get("collection_code") or "",
             "collection_label": {c["value"]: c["label"] for c in get_collections()}.get(i.get("collection_code"), ""),
             "status": item_status(i), "type": i.get("item_type_id") or ""}
        if staff and c["status"] == "Checked out":
            c["out"] = out.get(i["item_id"])
        copies.append(c)
    res = {"cover": cover_key(b.get("isbn"), b["biblio_id"]), "id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"), "subtitle": b.get("subtitle") or "",
            "author": b.get("author") or "", "year": b.get("copyright_date") or b.get("publication_year") or "",
            "isbn": b.get("isbn") or "", "publisher": b.get("publisher") or "", "pages": b.get("pages") or "",
            "edition": b.get("edition_statement") or "", "summary": b.get("abstract") or b.get("notes") or "",
            "series": b.get("series_title") or "", "type": b.get("item_type") or "", "copies": copies,
            "shelves": get_locations(), "collections": get_collections(),
            "tags": _tags_load().get(str(b["biblio_id"]), []), "all_tags": tag_counts()}
    holds = _hold_rows(raw_holds)
    if staff:
        res["holds"] = holds
    elif patron_id is not None:
        res["my_hold"] = next((h["hold_id"] for h in holds if h["patron_id"] == patron_id), None)
        res["can_hold"] = True
    res["hold_count"] = len(holds)
    return res


def op_item_update(payload):
    item_id = payload.get("item_id")
    if not isinstance(item_id, int):
        return 400, {"status": "invalid"}
    with LOCK:
        it = koha("GET", "/items/%d" % item_id)
        if "shelf" in payload:
            it["location"] = valid_location(payload.get("shelf")) or None
        if "collection" in payload:
            it["collection_code"] = valid_collection(payload.get("collection")) or None
        if "callnumber" in payload:
            it["callnumber"] = (str(payload.get("callnumber") or "").strip()[:80]) or None
        # Koha's update route rejects the computed fields the GET adds.
        for k in [k for k in it if k.startswith("effective_")] + [
                "checkouts_count", "holds_count", "renewals_count", "localuse", "timestamp", "call_number_sort",
                "bookable", "extended_subfields"]:
            it.pop(k, None)
        koha("PUT", "/biblios/%d/items/%d" % (it["biblio_id"], item_id), it)
    return 200, {"status": "saved"}


def op_item_delete(payload):
    item_id, biblio_id = payload.get("item_id"), payload.get("biblio_id")
    if not isinstance(item_id, int) or not isinstance(biblio_id, int):
        return 400, {"status": "invalid"}
    return op_undo({"item_id": item_id, "biblio_id": biblio_id})


def op_book_delete(payload):
    biblio_id = payload.get("biblio_id")
    if not isinstance(biblio_id, int):
        return 400, {"status": "invalid"}
    with LOCK:
        items = koha("GET", "/biblios/%d/items" % biblio_id) or []
        if any(item_status(i) == "Checked out" for i in items):
            return 409, {"status": "error", "message": "A copy is checked out - return it first."}
        for i in items:
            koha("DELETE", "/items/%d" % i["item_id"])
            forget(i["item_id"])
        koha("DELETE", "/biblios/%d" % biblio_id)
        d = _tags_load()
        if d.pop(str(biblio_id), None) is not None:
            save_json(TAGS_FILE, d)
    return 200, {"status": "deleted"}


def op_item_copy(payload):
    """Another copy of a book already in the library (new barcode per the barcode setting)."""
    biblio_id = payload.get("biblio_id")
    if not isinstance(biblio_id, int):
        return 400, {"status": "invalid"}
    with LOCK:
        b = koha("GET", "/biblios/%d" % biblio_id)
        items = koha("GET", "/biblios/%d/items" % biblio_id) or []
        base = items[0] if items else {}
        mode = load_settings()["barcode_mode"]
        if mode == "scan":
            mode = "auto"           # no scanner step here: number it, or leave it blank in 'none' mode
        item = add_item(biblio_id, base.get("item_type_id") or valid_type(b.get("item_type")), base.get("callnumber"),
                        valid_location(payload.get("shelf")) or base.get("location"), mode)
    return 200, {"status": "added", "item_id": item["item_id"], "barcode": item.get("external_id") or ""}


# ------------------------------------------------------------ lending / people
import datetime as _dt

PATRON_CATEGORY = os.environ.get("PATRON_CATEGORY", "FRIEND")


def _patron_name(p):
    return ("%s %s" % (p.get("firstname") or "", p.get("surname") or "")).strip() or p.get("cardnumber") or "?"


def _shape_patron(p):
    return {"id": p["patron_id"], "name": _patron_name(p), "card": p.get("cardnumber") or "",
            "email": p.get("email") or "", "phone": p.get("phone") or ""}


def op_patron_search(term):
    term = re.sub(r"[%_\\]", "", term or "").strip()[:60]
    if not term:
        res = koha("GET", "/patrons", query={"_per_page": "50", "_order_by": "surname"}) or []
    else:
        like = {"-like": "%" + term + "%"}
        conds = [{"surname": like}, {"firstname": like}, {"cardnumber": {"-like": term + "%"}}]
        parts = term.split()
        if len(parts) == 2:                      # "Jane Smith"
            conds.append({"-and": [{"firstname": {"-like": parts[0] + "%"}}, {"surname": {"-like": parts[1] + "%"}}]})
        res = koha("GET", "/patrons", query={"q": json.dumps({"-or": conds}), "_per_page": "25", "_order_by": "surname"}) or []
    return {"patrons": [_shape_patron(p) for p in res]}


def _loan_rows(cos):
    """Checkouts (with embedded item) -> rows with titles and an overdue flag."""
    if not cos:
        return []
    bib_ids = sorted({c["item"]["biblio_id"] for c in cos if c.get("item")})
    titles = {}
    if bib_ids:
        for b in koha("GET", "/biblios", query={"q": json.dumps({"biblio_id": bib_ids}), "_per_page": str(len(bib_ids) + 1)}) or []:
            titles[b["biblio_id"]] = ((b.get("title") or "").rstrip(" /:"), b.get("author") or "", b.get("isbn") or "")
    today = _dt.date.today().isoformat()
    rows = []
    for c in cos:
        it = c.get("item") or {}
        t = titles.get(it.get("biblio_id"), ("(unknown)", "", ""))
        due = (c.get("due_date") or "")[:10]
        rows.append({"checkout_id": c["checkout_id"], "patron_id": c["patron_id"], "barcode": it.get("external_id") or "",
                     "biblio_id": it.get("biblio_id"), "title": t[0], "author": t[1], "isbn": t[2], "due": due,
                     "overdue": bool(due) and due < today, "renewals": c.get("renewals_count") or 0,
                     "checkout_date": (c.get("checkout_date") or "")[:10],
                     "returned": (c.get("checkin_date") or "")[:10]})
    return rows


def op_patron(patron_id):
    p = koha("GET", "/patrons/%d" % patron_id)
    cos = koha("GET", "/checkouts", query={"q": json.dumps({"patron_id": patron_id}), "_per_page": "200",
                                           "_order_by": "due_date"}, headers={"x-koha-embed": "item"}) or []
    d = _shape_patron(p)
    d["loans"] = _loan_rows(cos)
    d["category"] = p.get("category_id") or ""
    return d


def op_out():
    """Everything checked out right now, soonest due first (overdue on top)."""
    cos = koha("GET", "/checkouts", query={"_per_page": "500", "_order_by": "due_date"}, headers={"x-koha-embed": "item"}) or []
    rows = _loan_rows(cos)
    names, contact = {}, {}
    for pid in sorted({r["patron_id"] for r in rows}):
        try:
            p = koha("GET", "/patrons/%d" % pid)
            names[pid] = _patron_name(p)
            contact[pid] = (p.get("phone") or "", p.get("email") or "")
        except KohaError:
            names[pid] = "?"
            contact[pid] = ("", "")
    today = _dt.date.today()
    for r in rows:
        r["who"] = names.get(r["patron_id"], "?")
        r["phone"], r["email"] = contact.get(r["patron_id"], ("", ""))
        try:
            r["days_late"] = max(0, (today - _dt.date.fromisoformat(r["due"])).days)
        except ValueError:
            r["days_late"] = 0
    return {"loans": rows}


def _item_by_barcode(code):
    code = (code or "").strip()
    if not code or len(code) > 40:
        return None
    res = koha("GET", "/items", query={"q": json.dumps({"external_id": code}), "_per_page": "1"}) or []
    return res[0] if res else None


def _title_of(biblio_id):
    try:
        return (koha("GET", "/biblios/%d" % biblio_id).get("title") or "").rstrip(" /:")
    except KohaError:
        return ""


def op_checkout(payload):
    pid, code = payload.get("patron_id"), payload.get("barcode")
    if not isinstance(pid, int):
        return 400, {"status": "invalid", "message": "Pick the person first."}
    it = _item_by_barcode(code)
    if not it:
        return 200, {"status": "unknown", "message": "No book has the barcode %s." % str(code)[:40]}
    title = _title_of(it["biblio_id"])
    if item_status(it) == "Checked out":
        return 200, {"status": "already_out", "title": title, "barcode": it["external_id"],
                     "message": "That one is already checked out. Scan it as a return first."}
    try:
        co = koha("POST", "/checkouts", {"patron_id": pid, "item_id": it["item_id"]})
    except KohaError as e:
        try:
            msg = json.loads(e.body).get("error") or ""
        except ValueError:
            msg = ""
        return 200, {"status": "refused", "title": title, "message": msg or "Koha would not allow that checkout."}
    return 200, {"status": "checked_out", "title": title, "barcode": it["external_id"], "due": (co.get("due_date") or "")[:10]}


def op_return(payload):
    code = str(payload.get("barcode") or "").strip()
    if not SSO_SECRET:
        return 200, {"status": "error", "message": "Returns need SSO_SECRET in .env (run the installer's Update)."}
    req = urllib.request.Request(KOHA_RETURN_URL + "?" + urllib.parse.urlencode({"barcode": code}),
                                 headers={"X-Quickadd-Secret": SSO_SECRET})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            res = json.loads(r.read())
    except (urllib.error.URLError, OSError, ValueError):
        return 502, {"status": "error", "message": "Koha did not answer the return - try again."}
    it = _item_by_barcode(code) if res.get("status") in ("returned", "not_out") else None
    res["title"] = _title_of(it["biblio_id"]) if it else ""
    return 200, res


def op_renew(payload):
    cid = payload.get("checkout_id")
    if not isinstance(cid, int):
        return 400, {"status": "invalid"}
    try:
        co = koha("POST", "/checkouts/%d/renewal" % cid)
    except KohaError as e:
        try:
            msg = json.loads(e.body).get("error") or ""
        except ValueError:
            msg = ""
        return 200, {"status": "refused", "message": msg or "That one can't be renewed (limit reached or someone is waiting)."}
    return 200, {"status": "renewed", "due": (co.get("due_date") or "")[:10]}


_NAME_CACHE = {"at": 0.0, "value": ""}


def library_name():
    if time.time() - _NAME_CACHE["at"] > 300:
        try:
            _NAME_CACHE["value"] = koha("GET", "/libraries/%s" % urllib.parse.quote(LIBRARY)).get("name") or ""
        except (KohaError, AttributeError):
            pass
        _NAME_CACHE["at"] = time.time()
    return _NAME_CACHE["value"]


def op_patron_add(payload):
    def clean(k, n=60):
        return re.sub(r"\s+", " ", str(payload.get(k) or "")).strip()[:n]
    surname, first = clean("surname"), clean("firstname")
    if not surname:
        return 400, {"status": "invalid", "message": "A name is needed."}
    body = {"surname": surname, "firstname": first or None, "category_id": PATRON_CATEGORY, "library_id": LIBRARY,
            "email": clean("email", 100) or None, "phone": clean("phone", 30) or None}
    try:
        p = koha("POST", "/patrons", body, headers={"x-confirm-not-duplicate": "1"} if payload.get("confirm") else None)
    except KohaError as e:
        if e.status == 409 or "already exists" in e.body:
            return 200, {"status": "duplicate", "message": "Someone named %s is already in the library." % _patron_name(body)}
        raise
    out = dict(_shape_patron(p), status="added")
    if not payload.get("nologin"):
        pw = new_password()
        try:
            set_patron_password(p["patron_id"], pw)
            out["password"] = pw
        except KohaError:
            out["password"] = ""
    return 200, out


# ------------------------------------------------ new shelves / collections, QR codes, book info
KOHA_VALUE_URL = KOHA_API.rsplit("/api/v1", 1)[0] + "/cgi-bin/koha/quickadd-value.pl"


def op_value_add(payload):
    """Add a shelf/room or a collection (Koha's REST API cannot; a small guarded Koha script does)."""
    kind = payload.get("kind")
    cat = {"shelf": "LOC", "collection": "CCODE"}.get(kind)
    name = re.sub(r"\s+", " ", str(payload.get("name") or "")).strip()[:60]
    if not cat or not name:
        return 400, {"status": "invalid", "message": "A name is needed."}
    if not SSO_SECRET:
        return 200, {"status": "error", "message": "Adding these needs SSO_SECRET in .env (run the installer's Update)."}
    existing = get_locations() if cat == "LOC" else get_collections()
    for v in existing:                      # same name again: hand back the one that exists
        if v["label"].strip().lower() == name.lower():
            return 200, {"status": "added", "value": v["value"], "label": v["label"]}
    base = re.sub(r"[^A-Z0-9]+", "", name.upper())[:12] or "X"
    have = {v["value"] for v in existing}
    code, n = base, 2
    while code in have:
        code = base[:10] + str(n)
        n += 1
    req = urllib.request.Request(KOHA_VALUE_URL + "?" + urllib.parse.urlencode({"category": cat, "value": code, "description": name}),
                                 headers={"X-Quickadd-Secret": SSO_SECRET})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            res = json.loads(r.read())
    except (urllib.error.URLError, OSError, ValueError):
        return 502, {"status": "error", "message": "Koha did not answer - try again."}
    if res.get("status") != "added":
        return 200, {"status": "error", "message": "Koha would not add that."}
    _LOC_CACHE["at"] = _COLL_CACHE["at"] = 0.0
    return 200, {"status": "added", "value": code, "label": name}


def qr_svg(text):
    if not re.fullmatch(r"[A-Za-z0-9-]{1,40}", text or ""):
        raise ValueError("bad text")
    return subprocess.run(["qrencode", "-t", "SVG", "-m", "2", "-s", "8", "-l", "M", "-o", "-", text],
                          capture_output=True, timeout=10, check=True).stdout


MORE_FILE = os.path.join(DATA_DIR, "more.json")
MORE_TTL = 30 * 86400


def _http_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "library-quickadd/1 (home library)"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read())


def _ol_text(v):
    if isinstance(v, dict):
        v = v.get("value")
    return re.sub(r"\s+", " ", v).strip() if isinstance(v, str) else ""


def op_more(biblio_id):
    """Extra details from Open Library (description, subjects) plus look-up links, cached on disk.
    AR BookFind is a link only: its terms forbid automated access, so nothing is fetched from it."""
    b = koha("GET", "/biblios/%d" % biblio_id)
    isbn = re.sub(r"[^0-9Xx]", "", (b.get("isbn") or "").split(" ")[0].split("|")[0])
    title = (b.get("title") or "").rstrip(" /:")
    out = {"links": [], "description": "", "subjects": [], "first_published": "", "isbn": isbn,
           "ar": _ar_load().get(_isbn13(isbn) or "", {})}
    q = urllib.parse.quote(title + " " + (b.get("author") or ""))
    if isbn:
        out["links"] = [
            {"label": "Open Library", "url": "https://openlibrary.org/isbn/" + isbn},
            {"label": "Goodreads", "url": "https://www.goodreads.com/book/isbn/" + isbn},
            {"label": "LibraryThing", "url": "https://www.librarything.com/isbn/" + isbn},
            {"label": "WorldCat", "url": "https://search.worldcat.org/search?q=bn%3A" + isbn}]
    out["links"].append({"label": "AR BookFind (reading level)", "url": "https://www.arbookfind.com/", "note": "search for: " + title})
    if not isbn:
        return out
    with LOCK:
        try:
            cache = json.load(open(MORE_FILE))
        except (OSError, ValueError):
            cache = {}
    hit = cache.get(isbn)
    if hit and time.time() - hit["at"] < (MORE_TTL if hit["ok"] else 3600):
        return dict(out, **hit["data"])
    data, ok = {}, False
    try:
        ed = _http_json("https://openlibrary.org/isbn/%s.json" % isbn)
        work = (ed.get("works") or [{}])[0].get("key")
        data["description"] = _ol_text(ed.get("description"))
        data["subjects"] = []
        if work:
            w = _http_json("https://openlibrary.org%s.json" % work)
            data["description"] = _ol_text(w.get("description")) or data["description"]
            data["subjects"] = [str(x) for x in (w.get("subjects") or [])][:12]
            data["first_published"] = str(w.get("first_publish_date") or "")
            out["links"][0] = {"label": "Open Library", "url": "https://openlibrary.org" + work}
        data["description"] = data["description"].split("----------")[0].strip()[:1500]
        ok = True
    except Exception:
        pass
    if ok:
        data["link0"] = out["links"][0]
    cache[isbn] = {"at": time.time(), "ok": ok, "data": data}
    with LOCK:
        try:
            tmp = MORE_FILE + ".tmp"
            json.dump(cache, open(tmp, "w"))
            os.replace(tmp, MORE_FILE)
        except OSError:
            pass
    if ok and data.get("link0"):
        out["links"][0] = data.pop("link0")
    return dict(out, **data)


# ------------------------------------------------ reading levels (AR) and CSV in/out
# AR BookFind has no public feed and its terms forbid automated access, so reading levels are kept
# here instead: typed in on the book page, or imported from a CSV you made yourself. Keyed by ISBN-13.
AR_FILE = os.path.join(DATA_DIR, "reading-levels.json")


def _isbn13(raw):
    c = clean_code(raw)
    if not c:
        return None
    return isbn10_to_13(c) if len(c) == 10 else c


def _ar_load():
    try:
        return json.load(open(AR_FILE))
    except (OSError, ValueError):
        return {}


def _ar_save(d):
    tmp = AR_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, AR_FILE)


def _num(v, maxlen=8):
    v = str(v or "").strip()[:maxlen]
    return v if re.fullmatch(r"[0-9]{0,4}(\.[0-9]{1,2})?", v) else None


def op_ar_set(payload):
    key = _isbn13(payload.get("isbn"))
    level, points, quiz = _num(payload.get("level")), _num(payload.get("points")), re.sub(r"[^0-9]", "", str(payload.get("quiz") or ""))[:8]
    interest = re.sub(r"[^A-Za-z+]", "", str(payload.get("interest") or ""))[:4].upper()
    if not key or level is None or points is None:
        return 400, {"status": "invalid", "message": "Level and points are numbers like 4.5 and 6."}
    with LOCK:
        d = _ar_load()
        if level or points or quiz or interest:
            d[key] = {"level": level, "points": points, "quiz": quiz, "interest": interest}
        else:
            d.pop(key, None)
        _ar_save(d)
    return 200, {"status": "saved"}


def op_ar_import(payload):
    """CSV with a header row; needs an isbn column and any of level, points, quiz."""
    import csv, io
    text = str(payload.get("csv") or "")[:2_000_000]
    rows = list(csv.reader(io.StringIO(text)))
    if len(rows) < 2:
        return 400, {"status": "invalid", "message": "That file has no rows."}
    head = [re.sub(r"[^a-z0-9]", "", h.lower()) for h in rows[0]]
    def col(*names):
        for n in names:
            if n in head:
                return head.index(n)
        return None
    cint = col("interest", "interestlevel", "il")
    ci, cl, cp, cq = col("isbn", "isbn13"), col("level", "arlevel", "bl", "booklevel"), col("points", "arpoints", "pts"), col("quiz", "quizno", "quiznumber")
    if ci is None or (cl is None and cp is None and cq is None):
        return 400, {"status": "invalid", "message": "Need a header row with an isbn column and at least one of: level, points, quiz."}
    done = skipped = 0
    with LOCK:
        d = _ar_load()
        for r in rows[1:]:
            get = lambda i: r[i] if i is not None and i < len(r) else ""
            key = _isbn13(get(ci))
            lv, pt = _num(get(cl)), _num(get(cp))
            if not key or lv is None or pt is None:
                skipped += 1
                continue
            old = d.get(key, {})
            d[key] = {"level": lv or old.get("level", ""), "points": pt or old.get("points", ""),
                      "quiz": re.sub(r"[^0-9]", "", get(cq))[:8] or old.get("quiz", ""),
                      "interest": re.sub(r"[^A-Za-z+]", "", get(cint))[:4].upper() or old.get("interest", "")}
            done += 1
        _ar_save(d)
    return 200, {"status": "imported", "count": done, "skipped": skipped}


def export_csv():
    """One row per copy: what you have, where it is, and any reading level on file."""
    import csv, io
    where = {l["value"]: l["label"] for l in get_locations()}
    colls = {c["value"]: c["label"] for c in get_collections()}
    ar = _ar_load()
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["title", "author", "isbn", "year", "barcode", "call number", "shelf", "collection", "status", "ar level", "ar points", "ar quiz", "ar interest"])
    page = 1
    while True:
        books = koha("GET", "/biblios", query={"_per_page": "200", "_page": str(page), "_order_by": "title"}) or []
        if not books:
            break
        ids = [b["biblio_id"] for b in books]
        items = koha("GET", "/items", query={"q": json.dumps({"biblio_id": ids}), "_per_page": "2000"}) or []
        for b in books:
            isbn = b.get("isbn") or ""
            a = ar.get(_isbn13(isbn) or "", {})
            mine = [i for i in items if i["biblio_id"] == b["biblio_id"]] or [{}]
            for i in mine:
                w.writerow([(b.get("title") or "").rstrip(" /:"), b.get("author") or "", isbn, b.get("copyright_date") or "",
                            i.get("external_id") or "", i.get("callnumber") or "", where.get(i.get("location"), ""),
                            colls.get(i.get("collection_code"), ""), item_status(i) if i else "", a.get("level", ""), a.get("points", ""), a.get("quiz", ""), a.get("interest", "")])
        if len(books) < 200:
            break
        page += 1
    return out.getvalue().encode("utf-8-sig")


# ------------------------------------------------------------------ tags
TAGS_FILE = os.path.join(DATA_DIR, "tags.json")


def _tags_load():
    try:
        d = json.load(open(TAGS_FILE))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def clean_tags(raw):
    out, seen = [], set()
    for t in (raw if isinstance(raw, list) else []):
        t = re.sub(r"\s+", " ", str(t)).strip(" ,;#")[:30]
        if t and t.lower() not in seen:
            seen.add(t.lower())
            out.append(t)
    return out[:20]


def tag_counts():
    counts = {}
    for tags in _tags_load().values():
        for t in tags:
            counts[t] = counts.get(t, 0) + 1
    return [{"tag": t, "count": n} for t, n in sorted(counts.items(), key=lambda x: x[0].lower())]


def op_tags_set(payload):
    bid = payload.get("biblio_id")
    if not isinstance(bid, int):
        return 400, {"status": "invalid"}
    tags = clean_tags(payload.get("tags"))
    with LOCK:
        d = _tags_load()
        if tags:
            d[str(bid)] = tags
        else:
            d.pop(str(bid), None)
        save_json(TAGS_FILE, d)
    return 200, {"status": "saved", "tags": tags, "all": tag_counts()}


# ------------------------------------------------------- patron logins / my books
LOGINS_FILE = os.path.join(DATA_DIR, "logins.json")           # patron ids that have a login set up
PW_WORDS = ["maple", "river", "cedar", "tiger", "lemon", "panda", "otter", "robin", "sunny", "cloud", "apple", "grape",
            "daisy", "heron", "frost", "amber", "coral", "ember", "fable", "ivory", "brook", "pearl", "tulip", "wheat"]
_LOGIN_FAILS = {}            # client address -> [count, window start]
_LOGIN_OK = {}               # (user, sha256(pw)) -> (expires, patron_id)


def new_password():
    s = load_settings()
    if s.get("patron_password_mode") == "same" and s.get("patron_password"):
        return s["patron_password"]
    return secrets.choice(PW_WORDS) + "%03d" % secrets.randbelow(1000)


def _logins():
    try:
        d = json.load(open(LOGINS_FILE))
        return d if isinstance(d, list) else []
    except (OSError, ValueError):
        return []


def _mark_login(pid):
    with LOCK:
        d = _logins()
        if pid not in d:
            d.append(pid)
            save_json(LOGINS_FILE, d)


def set_patron_password(pid, pw):
    koha("POST", "/patrons/%d/password" % pid, {"password": pw, "password_2": pw})
    _mark_login(pid)


def patron_login(user, pw, addr):
    """Check a patron's card number / userid and password with Koha. Returns the patron id or None.
    Failures are counted per address so a password cannot be guessed at speed."""
    if not re.fullmatch(r"[A-Za-z0-9._@-]{1,40}", user or "") or not pw or len(pw) > 100:
        return None
    now = time.time()
    fails = _LOGIN_FAILS.get(addr)
    if fails and now - fails[1] < 300 and fails[0] >= 10:
        return None
    key = (user, hashlib.sha256(pw.encode()).hexdigest())
    hit = _LOGIN_OK.get(key)
    if hit and hit[0] > now:
        return hit[1]
    pid = None
    try:
        r = koha("POST", "/auth/password/validation", {"identifier": user, "password": pw})
        pid = (r or {}).get("patron_id")
    except KohaError:
        pid = None
    if pid:
        _LOGIN_OK[key] = (now + 60, pid)
        _LOGIN_FAILS.pop(addr, None)
        return pid
    f = _LOGIN_FAILS.get(addr)
    if not f or now - f[1] >= 300:
        f = _LOGIN_FAILS[addr] = [0, now]
    f[0] += 1
    return None


def op_me(pid):
    p = koha("GET", "/patrons/%d" % pid)
    cos = koha("GET", "/checkouts", query={"q": json.dumps({"patron_id": pid}), "_per_page": "200", "_order_by": "due_date"},
               headers={"x-koha-embed": "item"}) or []
    try:
        holds = holds_of_patron(pid)
    except KohaError:
        holds = []
    return {"name": _patron_name(p), "card": p.get("cardnumber") or "", "loans": _loan_rows(cos), "holds": holds}


def op_me_renew(pid, payload):
    cid = payload.get("checkout_id")
    if not isinstance(cid, int):
        return 400, {"status": "invalid"}
    co = koha("GET", "/checkouts/%d" % cid)
    if not co or co.get("patron_id") != pid:
        return 403, {"status": "error", "message": "That is not one of your books."}
    return op_renew({"checkout_id": cid})


def op_me_password(pid, addr, payload):
    new = str(payload.get("new") or "")
    if not 4 <= len(new) <= 40:
        return 400, {"status": "invalid", "message": "Use 4 to 40 characters."}
    p = koha("GET", "/patrons/%d" % pid)
    if not patron_login(p.get("cardnumber") or p.get("userid") or "", str(payload.get("old") or ""), addr):
        return 403, {"status": "error", "message": "The current password is not right."}
    try:
        set_patron_password(pid, new)
    except KohaError as e:
        return 200, {"status": "error", "message": "Koha would not accept that password: " + e.body[:100]}
    _LOGIN_OK.clear()
    return 200, {"status": "saved"}


def op_reset_login(payload):
    """Give someone a (new) login password and show it once."""
    pid = payload.get("patron_id")
    if not isinstance(pid, int):
        return 400, {"status": "invalid"}
    p = koha("GET", "/patrons/%d" % pid)
    pw = new_password()
    set_patron_password(pid, pw)
    _LOGIN_OK.clear()
    return 200, {"status": "saved", "name": _patron_name(p), "card": p.get("cardnumber") or "", "password": pw}


def op_logins_all(payload):
    """Logins for everyone who has none yet (people added before logins existed). Passwords are shown once."""
    have = set(_logins())
    made, page = [], 1
    while True:
        res = koha("GET", "/patrons", query={"q": json.dumps({"category_id": PATRON_CATEGORY}), "_per_page": "100", "_page": str(page)}) or []
        for p in res:
            if p["patron_id"] in have:
                continue
            pw = new_password()
            try:
                set_patron_password(p["patron_id"], pw)
            except KohaError:
                continue
            made.append({"name": _patron_name(p), "card": p.get("cardnumber") or "", "password": pw})
        if len(res) < 100:
            break
        page += 1
    _LOGIN_OK.clear()
    return 200, {"status": "done", "made": made}


# ------------------------------------------------------------ title / author search
def z3950_candidates(spec, term, limit=8):
    """Title search (falling back to any field) on a Z39.50 server; returns summaries with an ISBN."""
    out = []
    for attr in ("@attr 1=4", "@attr 1=1016"):
        with tempfile.TemporaryDirectory() as tmp:
            dump = os.path.join(tmp, "rec.mrc")
            q = term.replace('"', " ")
            script = 'format usmarc\nfind %s "%s"\nshow 1+%d\nquit\n' % (attr, q, limit)
            try:
                res = subprocess.run(["yaz-client", "-m", dump, spec], input=script, capture_output=True, text=True,
                                     timeout=Z3950_TIMEOUT).stdout
            except (subprocess.TimeoutExpired, OSError):
                return out
            m = re.search(r"Number of hits: (\d+)", res)
            if not m or int(m.group(1)) == 0 or not os.path.exists(dump):
                continue
            raw = open(dump, "rb").read()
            args = ["yaz-marcdump", "-o", "marcxml"]
            if len(raw) > 9 and raw[9:10] == b" ":
                args += ["-f", "MARC-8", "-t", "UTF-8", "-l", "9=97"]
            conv = subprocess.run(args + [dump], capture_output=True, text=True, timeout=15)
            if conv.returncode != 0:
                continue
            try:
                root = ET.fromstring(conv.stdout if conv.stdout.lstrip().startswith("<collection") else "<c xmlns='%s'>%s</c>" % (NS["m"], conv.stdout))
            except ET.ParseError:
                continue
            for rec in root.iter("{%s}record" % NS["m"]):
                info = describe(rec)
                isbn = ""
                for df in rec.findall("m:datafield[@tag='020']", NS):
                    for sf in df.findall("m:subfield[@code='a']", NS):
                        c = clean_code((sf.text or "").split(" ")[0])
                        if c and len(c) in (10, 13) and not isbn:
                            isbn = isbn10_to_13(c) if len(c) == 10 else c
                if isbn:
                    out.append(dict(info, isbn=isbn, source="Library of Congress"))
            if out:
                return out
    return out


def openlibrary_candidates(term, limit=10):
    url = "https://openlibrary.org/search.json?" + urllib.parse.urlencode(
        {"q": term, "limit": str(limit), "fields": "title,author_name,first_publish_year,isbn,publisher,cover_i"})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "library-quickadd/1.0"}), timeout=10) as r:
            docs = json.load(r).get("docs") or []
    except (urllib.error.URLError, OSError, ValueError):
        return []
    out = []
    for d in docs:
        isbns = [clean_code(i) for i in (d.get("isbn") or [])]
        isbns = [i for i in isbns if i and len(i) == 13 and i[:3] in ("978", "979")] or [isbn10_to_13(i) for i in isbns if i and len(i) == 10]
        if not isbns or not d.get("title"):
            continue
        out.append({"title": d["title"], "author": ", ".join((d.get("author_name") or [])[:2]), "year": str(d.get("first_publish_year") or ""),
                    "publisher": ((d.get("publisher") or [""])[0])[:60], "isbn": isbns[0], "source": "Open Library"})
    return out


def op_lookup(term):
    """Books matching a title/author, to choose from; each has an ISBN so choosing one is a normal add."""
    term = re.sub(r"\s+", " ", term or "").strip()[:100]
    if len(term) < 3:
        return {"candidates": []}
    found, seen = [], set()
    for src in SOURCES:
        got = []
        if src == "openlibrary":
            got = openlibrary_candidates(term)
        elif src.startswith("z3950:"):
            got = z3950_candidates(src[len("z3950:"):], term)
        for c in got:
            key = (c["isbn"], (c["title"] + c["author"]).lower()[:40])
            if c["isbn"] in {k[0] for k in seen} or key in seen:
                continue
            seen.add(key)
            found.append(c)
    found = found[:12]
    if found:                                    # which of these do we already own? one query for all
        conds = [{"isbn": {"-like": "%" + c["isbn"] + "%"}} for c in found] + [{"ean": {"-like": "%" + c["isbn"] + "%"}} for c in found]
        try:
            owned = " ".join((b.get("isbn") or "") + " " + (b.get("ean") or "") for b in
                             (koha("GET", "/biblios", query={"q": json.dumps({"-or": conds}), "_per_page": "50"}) or []))
        except KohaError:
            owned = ""
        for c in found:
            alt = isbn13_to_10(c["isbn"]) or ""
            c["have"] = c["isbn"] in owned or bool(alt and alt in owned)
    have = found
    return {"candidates": have}


# ------------------------------------------------------------ edit a book's details
def _marc_set(rec, tag, code, value, ind1=" ", ind2=" "):
    """Set (or clear, when value is empty) one subfield; never leaves an empty datafield behind."""
    ns = "{%s}" % NS["m"]
    df = rec.find("m:datafield[@tag='%s']" % tag, NS)
    if not value:
        if df is not None:
            for sf in df.findall("m:subfield[@code='%s']" % code, NS):
                df.remove(sf)
            if not df.findall("m:subfield", NS):
                rec.remove(df)
        return
    if df is None:
        df = ET.SubElement(rec, ns + "datafield", tag=tag, ind1=ind1, ind2=ind2)
    sf = df.find("m:subfield[@code='%s']" % code, NS)
    if sf is None:
        sf = ET.SubElement(df, ns + "subfield", code=code)
    sf.text = value


def op_book_edit(payload):
    bid = payload.get("biblio_id")
    if not isinstance(bid, int):
        return 400, {"status": "invalid"}

    def clean(k, n):
        return re.sub(r"\s+", " ", str(payload.get(k) or "")).strip()[:n]
    title = clean("title", 250)
    if not title:
        return 400, {"status": "invalid", "message": "A book needs a title."}
    isbn = clean("isbn", 20)
    if isbn and not clean_code(isbn):
        return 400, {"status": "invalid", "message": "That ISBN does not look right (10 or 13 digits)."}
    summary = re.sub(r"[ \t]+", " ", str(payload.get("summary") or "")).strip()[:2000]
    with LOCK:
        xml = koha("GET", "/biblios/%d" % bid, headers={"Accept": "application/marcxml+xml"}, raw=True)
        rec = parse_marc(xml.decode("utf-8"))
        _marc_set(rec, "245", "a", title, "1", "0")
        _marc_set(rec, "245", "b", clean("subtitle", 250))
        # author: keep whichever of 100/110 the record already uses
        atag = "110" if rec.find("m:datafield[@tag='110']", NS) is not None and rec.find("m:datafield[@tag='100']", NS) is None else "100"
        _marc_set(rec, atag, "a", clean("author", 150), "1" if atag == "100" else "2", " ")
        ptag = "264" if rec.find("m:datafield[@tag='264']", NS) is not None or rec.find("m:datafield[@tag='260']", NS) is None else "260"
        pind2 = "1" if ptag == "264" else " "
        _marc_set(rec, ptag, "b", clean("publisher", 100), " ", pind2)
        _marc_set(rec, ptag, "c", clean("year", 12), " ", pind2)
        _marc_set(rec, "300", "a", clean("pages", 40))
        _marc_set(rec, "520", "a", summary)
        if isbn:
            _marc_set(rec, "020", "a", clean_code(isbn))
        koha("PUT", "/biblios/%d" % bid, ET.tostring(rec, encoding="utf-8"), "application/marcxml+xml")
    return 200, {"status": "saved"}


# --------------------------------------------------------------------- holds
def _hold_rows(holds):
    names = {}
    out = []
    for h in sorted(holds, key=lambda x: (x.get("priority") or 99, x.get("hold_id") or 0)):
        pid = h["patron_id"]
        if pid not in names:
            try:
                names[pid] = _patron_name(koha("GET", "/patrons/%d" % pid))
            except KohaError:
                names[pid] = "?"
        out.append({"hold_id": h["hold_id"], "patron_id": pid, "who": names[pid], "date": (h.get("hold_date") or "")[:10],
                    "waiting": h.get("status") in ("W", "T"), "position": h.get("priority") or 0, "biblio_id": h["biblio_id"]})
    return out


def _hold_error(e):
    try:
        msg = json.loads(e.body).get("error") or ""
    except ValueError:
        msg = ""
    low = msg.lower()
    if "toomanyholds" in low.replace(" ", "").replace("_", "") and "record" in low:
        return "There is already a hold on this book for that person."
    if "already" in low or "exist" in low:
        return "There is already a hold on this book for that person."
    return msg or "Koha would not place that hold."


def _place_hold(patron_id, biblio_id):
    try:
        koha("POST", "/holds", {"patron_id": patron_id, "biblio_id": biblio_id, "pickup_library_id": LIBRARY})
    except KohaError as e:
        return 200, {"status": "refused", "message": _hold_error(e)}
    return 200, {"status": "placed"}


def op_hold_add(payload):
    pid, bid = payload.get("patron_id"), payload.get("biblio_id")
    if not isinstance(pid, int) or not isinstance(bid, int):
        return 400, {"status": "invalid"}
    return _place_hold(pid, bid)


def op_hold_cancel(payload, only_patron=None):
    hid = payload.get("hold_id")
    if not isinstance(hid, int):
        return 400, {"status": "invalid"}
    found = koha("GET", "/holds", query={"q": json.dumps({"hold_id": hid}), "_per_page": "1"}) or []
    if not found:
        return 404, {"status": "error", "message": "That hold no longer exists."}
    if only_patron is not None and found[0].get("patron_id") != only_patron:
        return 403, {"status": "error", "message": "That is not your hold."}
    koha("DELETE", "/holds/%d" % hid)
    return 200, {"status": "cancelled"}


def op_me_hold(pid, payload):
    bid = payload.get("biblio_id")
    if not isinstance(bid, int):
        return 400, {"status": "invalid"}
    return _place_hold(pid, bid)


def holds_of_patron(pid):
    rows = _hold_rows(koha("GET", "/holds", query={"q": json.dumps({"patron_id": pid}), "_per_page": "100"}) or [])
    for r in rows:
        try:
            b = koha("GET", "/biblios/%d" % r["biblio_id"])
            r["title"], r["author"] = (b.get("title") or "").rstrip(" /:"), b.get("author") or ""
        except KohaError:
            r["title"], r["author"] = "?", ""
    return rows


# ------------------------------------------------------------------- history
def _attach_items(cos):
    """Old (returned) loans cannot be embedded with their item by Koha reliably; look the items up ourselves."""
    ids = sorted({c["item_id"] for c in cos if c.get("item_id")})
    if not ids:
        return cos
    items = {i["item_id"]: i for i in (koha("GET", "/items", query={"q": json.dumps({"item_id": ids}), "_per_page": str(len(ids) + 1)}) or [])}
    for c in cos:
        c["item"] = items.get(c.get("item_id"))
    return [c for c in cos if c.get("item")]


def op_history(qs):
    """Past loans (returned) of one book or one person, newest first."""
    def one(k):
        return (qs.get(k) or [""])[0]
    query = {"_per_page": "60", "_order_by": "-checkout_date", "checked_in": "1"}
    if one("biblio").isdigit():
        items = koha("GET", "/biblios/%s/items" % one("biblio")) or []
        ids = [i["item_id"] for i in items]
        if not ids:
            return {"loans": []}
        query["q"] = json.dumps({"item_id": ids})
    elif one("patron").isdigit():
        query["q"] = json.dumps({"patron_id": int(one("patron"))})
    else:
        return {"loans": []}
    cos = _attach_items(koha("GET", "/checkouts", query=query) or [])
    rows = _loan_rows(cos)
    names = {}
    for r in rows:
        if r["patron_id"] not in names:
            try:
                names[r["patron_id"]] = _patron_name(koha("GET", "/patrons/%d" % r["patron_id"]))
            except KohaError:
                names[r["patron_id"]] = "?"
        r["who"] = names[r["patron_id"]]
    return {"loans": rows}


def op_me_history(pid):
    cos = koha("GET", "/checkouts", query={"q": json.dumps({"patron_id": pid}), "_per_page": "60", "_order_by": "-checkout_date",
                                           "checked_in": "1"}) or []
    return {"loans": _loan_rows(_attach_items(cos))}


# --------------------------------------------------------------- cover images
# Covers are fetched once, when a book is added (or the first time one is shown), and kept on disk, so the
# browser never contacts another site and covers still show offline.
COVER_DIR = os.path.join(DATA_DIR, "covers")
_COVER_MISS = {}                    # key -> time of the last failed fetch (not retried for a week)
COVER_MAX = 1_500_000


def cover_key(isbn_raw, biblio_id):
    """Covers are filed by ISBN-13; a book without an ISBN gets b<id> (it can only have an uploaded cover)."""
    return _isbn13(isbn_raw) or "b%d" % biblio_id


def norm_cover_key(raw):
    if re.fullmatch(r"b[0-9]{1,9}", raw or ""):
        return raw
    return _isbn13(raw)


def cover_path(key):
    return os.path.join(COVER_DIR, key + ".jpg")


def _no_cover_marker(key):
    return os.path.join(COVER_DIR, key + ".none")


def _is_jpeg(data):
    return 1500 < len(data) <= COVER_MAX and data[:3] == b"\xff\xd8\xff"       # a real JPEG, not a 1px placeholder


def _http_image(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "library-quickadd/1.0"}), timeout=10) as r:
            return r.read(COVER_MAX + 1)
    except (urllib.error.URLError, OSError):
        return b""


def _write_cover(key, data):
    os.makedirs(COVER_DIR, exist_ok=True)
    tmp = cover_path(key) + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, cover_path(key))
    try:
        os.remove(_no_cover_marker(key))
    except OSError:
        pass


def fetch_cover(key, save=True):
    """The cover's JPEG bytes (kept on disk when save) or None. Only ISBN keys are looked up online."""
    try:
        return open(cover_path(key), "rb").read()
    except OSError:
        pass
    if key.startswith("b") or os.path.exists(_no_cover_marker(key)):       # uploaded-only, or deliberately removed
        return None
    if time.time() - _COVER_MISS.get(key, 0) < 7 * 86400:
        return None
    data = _http_image("https://covers.openlibrary.org/b/isbn/%s-L.jpg?default=false" % key)
    if not _is_jpeg(data):
        _COVER_MISS[key] = time.time()
        return None
    if save:
        try:
            _write_cover(key, data)
        except OSError:
            pass
    return data


def cover_etag(key):
    try:
        st = os.stat(cover_path(key))
        return '"%x-%x"' % (int(st.st_mtime), st.st_size)
    except OSError:
        return None


def op_cover_upload(key_raw, data):
    key = norm_cover_key(key_raw)
    if not key:
        return 400, {"status": "invalid", "message": "Bad cover name."}
    if not _is_jpeg(data):
        return 415, {"status": "error", "message": "Please choose a picture (JPEG or PNG) under 1.5 MB."}
    with LOCK:
        _write_cover(key, data)
    return 200, {"status": "saved"}


def op_cover_delete(payload):
    key = norm_cover_key(payload.get("key"))
    if not key:
        return 400, {"status": "invalid"}
    with LOCK:
        try:
            os.remove(cover_path(key))
        except OSError:
            pass
        os.makedirs(COVER_DIR, exist_ok=True)
        open(_no_cover_marker(key), "w").close()          # do not fetch it again behind your back
    return 200, {"status": "deleted"}


def op_cover_refetch(payload):
    """Search again by ISBN: forget any removal and any earlier miss, and ask Open Library afresh."""
    key = norm_cover_key(payload.get("key"))
    if not key or key.startswith("b"):
        return 400, {"status": "invalid", "message": "This book has no ISBN to look up."}
    with LOCK:
        try:
            os.remove(_no_cover_marker(key))
        except OSError:
            pass
        _COVER_MISS.pop(key, None)
        try:
            os.remove(cover_path(key))
        except OSError:
            pass
    return 200, {"status": "found" if fetch_cover(key) else "none"}


def op_cover_candidates(biblio_id):
    """Other covers to choose from: Open Library editions matching the title and author."""
    b = koha("GET", "/biblios/%d" % biblio_id)
    term = ((b.get("title") or "").rstrip(" /:") + " " + (b.get("author") or "")).strip()
    url = "https://openlibrary.org/search.json?" + urllib.parse.urlencode(
        {"q": term, "limit": "24", "fields": "title,author_name,first_publish_year,cover_i"})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "library-quickadd/1.0"}), timeout=10) as r:
            docs = json.load(r).get("docs") or []
    except (urllib.error.URLError, OSError, ValueError):
        return {"covers": [], "message": "Open Library did not answer - try again, or upload a picture."}
    seen, out = set(), []
    for d in docs:
        cid = d.get("cover_i")
        if isinstance(cid, int) and cid not in seen:
            seen.add(cid)
            out.append({"id": cid, "title": d.get("title") or "", "author": ", ".join((d.get("author_name") or [])[:2]),
                        "year": str(d.get("first_publish_year") or "")})
    return {"covers": out[:16]}


def op_cover_pick(payload):
    key, cid = norm_cover_key(payload.get("key")), payload.get("cover_i")
    if not key or not isinstance(cid, int) or cid <= 0:
        return 400, {"status": "invalid"}
    data = _http_image("https://covers.openlibrary.org/b/id/%d-L.jpg" % cid)
    if not _is_jpeg(data):
        return 200, {"status": "error", "message": "Could not download that cover - try another."}
    with LOCK:
        _write_cover(key, data)
    return 200, {"status": "saved"}


def cover_preview(cid):
    return _http_image("https://covers.openlibrary.org/b/id/%d-M.jpg" % cid)


def prefetch_cover(code):
    isbn = _isbn13(code)
    if isbn:
        threading.Thread(target=fetch_cover, args=(isbn,), daemon=True).start()


# ------------------------------------------------------------ photo scanning
MAX_IMAGE = 12 * 1024 * 1024
ZBAR_TIMEOUT = 20


def image_kind(data):
    """Only JPEG and PNG are accepted: the decoder goes through ImageMagick, which
    has a long history of bugs in rarely used formats, so everything else is refused
    before it gets anywhere near it."""
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    return None


def decode_photo(data, kind):
    """Read barcodes from a photo with zbarimg. kind 'isbn' returns codes usable as an
    ISBN/UPC (ISBNs first); kind 'sticker' returns anything Koha could store as a barcode."""
    ext = image_kind(data)
    if not ext:
        raise ValueError("not a JPEG or PNG image")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "photo." + ext)
        with open(path, "wb") as f:
            f.write(data)
        try:
            out = subprocess.run(["zbarimg", "--raw", "-q", path], capture_output=True, text=True,
                                 timeout=ZBAR_TIMEOUT).stdout
        except (subprocess.TimeoutExpired, OSError):
            return []
    codes = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if kind == "sticker":
            ok = line if STICKER_RE.fullmatch(line) else None
        else:
            ok = clean_code(line)
            # zbar reports a UPC-A (12 digits) as a 13-digit EAN with a leading zero.
            # Use the 12 digits printed on the item, as a keyboard scanner would type
            # them, so lookups and duplicate checks match.
            if ok and len(ok) == 13 and ok[0] == "0":
                ok = ok[1:]
        if ok and ok not in codes:
            codes.append(ok)
    if kind != "sticker":                       # book ISBNs (978/979) before UPCs and short codes
        codes.sort(key=lambda c: 0 if (len(c) == 13 and c[:3] in ("978", "979")) else 1 if len(c) == 10 else 2)
    return codes


# ----------------------------------------------------------------------- HTTP
INDEX = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html"), "rb").read()


_SESSION_CACHE = {}


def koha_session_user(sid, ip):
    """Ask Koha whether this staff session may edit the catalogue. Returns the user name or None.
    Any problem (Koha starting, endpoint missing, odd reply) reads as 'not signed in', which just
    means Quick Add asks for its own login."""
    key, now = (sid, ip), time.time()
    hit = _SESSION_CACHE.get(key)
    if hit and hit[0] > now:
        return hit[1]
    user = None
    try:
        req = urllib.request.Request(KOHA_SESSION_URL + "?" + urllib.parse.urlencode({"sid": sid, "ip": ip}),
                                     headers={"X-Quickadd-Secret": SSO_SECRET})
        with urllib.request.urlopen(req, timeout=4) as r:
            data = json.load(r)
        if data.get("status") == "ok":
            user = data.get("user") or "staff"
    except Exception:
        user = None
    if len(_SESSION_CACHE) > 500:
        _SESSION_CACHE.clear()
    _SESSION_CACHE[key] = (now + (20 if user else 5), user)     # short: logging out takes effect quickly
    return user


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
        if "Cache-Control" not in (extra or {}):
            self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Permissions-Policy", "camera=(self), microphone=()")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; img-src 'self' https: data:; "
                         "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; frame-src https://www.arbookfind.com")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _role(self):
        """'admin', 'viewer' (read-only guest) or None. Sets self.via to 'koha' for a staff-site login."""
        self.via = None
        self.patron_id = None
        self.addr = self.client_address[0]
        if not PASSWORD:
            return None
        header = self.headers.get("Authorization", "")
        if header.startswith("Basic "):
            try:
                u, _, p = base64.b64decode(header[6:]).decode().partition(":")
            except (ValueError, UnicodeDecodeError):
                return None
            ub, pb = u.encode(), p.encode()
            # Both comparisons always run, so timing does not reveal which account exists.
            is_admin = hmac.compare_digest(ub, USER.encode()) & hmac.compare_digest(pb, PASSWORD.encode())
            is_viewer = bool(VIEWER_USER and VIEWER_PASSWORD) & hmac.compare_digest(ub, VIEWER_USER.encode()) \
                & hmac.compare_digest(pb, VIEWER_PASSWORD.encode())
            if is_admin:
                return "admin"
            if is_viewer:
                return "viewer"
            # Otherwise: a patron signing in with their card number (or userid) and password.
            addr = self.client_address[0]
            if SSO_SECRET and hmac.compare_digest(self.headers.get("X-Quickadd-Proxy", "").encode(), SSO_SECRET.encode()):
                # Behind Caddy the list reads "<visitor>, <Caddy>" (Caddy adds the visitor, the staff site's web server
                # adds Caddy), so the visitor is the one before the last. Used only to count failed sign-ins per
                # visitor, never to vouch for anyone.
                hops = [h.strip() for h in self.headers.get("X-Forwarded-For", "").split(",") if h.strip()]
                addr = (hops[-2] if len(hops) >= 2 else hops[-1]) if hops else addr
            self.addr = addr
            pid = patron_login(u, p, addr)
            if pid:
                self.patron_id = pid
                return "patron"
            return None
        # No Basic login: accept a staff-site login, but only for requests that came through the staff
        # site's web server (it overwrites X-Quickadd-Proxy with the shared secret on every request).
        if SSO_SECRET and hmac.compare_digest(self.headers.get("X-Quickadd-Proxy", "").encode(), SSO_SECRET.encode()):
            sid = ""
            for part in self.headers.get("Cookie", "").split(";"):
                k, _, v = part.strip().partition("=")
                if k == "CGISESSID":
                    sid = v
            # the browser's address as the web server saw it: the LAST entry (the one it appended)
            ip = self.headers.get("X-Forwarded-For", "").split(",")[-1].strip()
            if sid and ip and koha_session_user(sid, ip):
                self.via = "koha"
                return "admin"
        return None

    def _guard(self, need_admin=True):
        role = self._role()
        if role is None:
            self._send(401, b"Login required", "text/plain",
                       {"WWW-Authenticate": 'Basic realm="Library"'})
            return False
        if need_admin and role != "admin":
            self._send(403, {"status": "error", "message": "This login can search but not change anything."})
            return False
        if self.via == "koha" and self.command == "POST" and self.headers.get("X-Quickadd") != "1":
            self._send(403, {"status": "error", "message": "Missing request header."})
            return False
        self.role = role
        return True

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, b"ok", "text/plain")
        path = self.path.split("?")[0]
        if not self._guard(need_admin=path not in ("/", "/api/state", "/api/search", "/api/library", "/api/me", "/api/me/history") and not path.startswith(("/api/book/", "/api/more/", "/api/cover/"))):
            return
        if path == "/":
            return self._send(200, INDEX, "text/html; charset=utf-8")
        if path == "/api/state" and self.role in ("viewer", "patron"):
            return self._send(200, {"role": self.role, "library_name": library_name(), "library": LIBRARY, "recent": [], "types": {}, "locations": [],
                                    "settings": {}, "staff_port": STAFF_PORT, "staff_url": STAFF_URL,
                                    "opac_url": OPAC_URL, "opac_port": OPAC_PORT, "sources": []})
        if path == "/api/state":
            return self._send(200, {"role": "admin", "library_name": library_name(), "recent": load_recent()[:100], "types": get_item_types(),
                                    "library": LIBRARY, "locations": get_locations(), "settings": load_settings(), "staff_port": STAFF_PORT, "staff_url": STAFF_URL, "opac_url": OPAC_URL, "opac_port": OPAC_PORT,
                                    "sources": [s.split(":", 1)[0] if s.startswith("z3950") else s for s in SOURCES]})
        if path == "/api/settings":
            return self._send(200, settings_view())
        if path in ("/api/patrons", "/api/out") or path.startswith("/api/patron/"):
            try:
                if path == "/api/out":
                    return self._send(200, op_out())
                if path == "/api/patrons":
                    return self._send(200, op_patron_search((urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("q") or [""])[0]))
                m = re.match(r"^/api/patron/(\d{1,9})$", path)
                if not m:
                    return self._send(404, {"error": "not found"})
                return self._send(200, op_patron(int(m.group(1))))
            except KohaError as e:
                return self._send(404 if e.status == 404 else 502, {"status": "error", "message":
                                  "Koha is not answering yet - try again in a minute." if e.status == 503 else "Failed: %s" % e.body[:120]})
        if path == "/api/lookup":
            q = (urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("q") or [""])[0]
            try:
                return self._send(200, op_lookup(q))
            except KohaError:
                return self._send(502, {"status": "error", "message": "Koha is not answering yet - try again in a minute."})
        m = re.match(r"^/api/cover/(b[0-9]{1,9}|[0-9]{9}[0-9Xx]|[0-9]{13})$", path)
        if m:
            key = norm_cover_key(m.group(1).upper() if not m.group(1).startswith("b") else m.group(1))
            tmp = "tmp=1" in (urllib.parse.urlparse(self.path).query or "")          # search suggestions are not kept
            data = fetch_cover(key, save=not tmp) if key else None
            if not data:
                return self._send(404, b"no cover", "text/plain", {"Cache-Control": "private, max-age=600"})
            etag = cover_etag(key)
            if etag and self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", "private, no-cache")
                self.end_headers()
                return
            extra = {"Cache-Control": "private, no-cache"}
            if etag:
                extra["ETag"] = etag
            return self._send(200, data, "image/jpeg", extra)
        if path == "/api/cover-candidates":
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                return self._send(200, op_cover_candidates(int((qs.get("biblio") or ["0"])[0])))
            except (ValueError, KohaError):
                return self._send(502, {"covers": [], "message": "Koha is not answering yet - try again."})
        m = re.match(r"^/api/cover-preview/([0-9]{1,10})$", path)
        if m:
            data = cover_preview(int(m.group(1)))
            if not _is_jpeg(data):
                return self._send(404, b"no cover", "text/plain")
            return self._send(200, data, "image/jpeg", {"Cache-Control": "private, max-age=3600"})
        if path == "/api/history":
            try:
                return self._send(200, op_history(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)))
            except KohaError:
                return self._send(502, {"status": "error"})
        if path == "/api/me/history":
            if self.role != "patron":
                return self._send(403, {"status": "error"})
            try:
                return self._send(200, op_me_history(self.patron_id))
            except KohaError:
                return self._send(502, {"status": "error"})
        if path == "/api/me":
            if self.role != "patron":
                return self._send(403, {"status": "error", "message": "Sign in with a library card to see your books."})
            try:
                return self._send(200, op_me(self.patron_id))
            except KohaError:
                return self._send(502, {"status": "error", "message": "Koha is not answering yet - try again in a minute."})
        if path == "/api/export.csv":
            try:
                body = export_csv()
            except KohaError:
                return self._send(502, {"status": "error"})
            return self._send(200, body, "text/csv; charset=utf-8", {"Content-Disposition": 'attachment; filename="library.csv"'})
        if path == "/api/qr":
            try:
                svg = qr_svg((urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("t") or [""])[0])
            except (ValueError, OSError, subprocess.SubprocessError):
                return self._send(400, b"bad", "text/plain")
            return self._send(200, svg, "image/svg+xml")
        if path.startswith("/api/more/"):
            m = re.match(r"^/api/more/(\d{1,9})$", path)
            if not m:
                return self._send(404, {"error": "not found"})
            try:
                return self._send(200, op_more(int(m.group(1))))
            except KohaError:
                return self._send(502, {"status": "error"})
        if path == "/api/library" or path.startswith("/api/book/"):
            try:
                if path == "/api/library":
                    return self._send(200, dict(op_library(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)),
                                                shelves=get_locations(), collections=get_collections(), types=get_item_types(), tags=tag_counts()))
                m = re.match(r"^/api/book/(\d{1,9})$", path)
                if not m:
                    return self._send(404, {"error": "not found"})
                return self._send(200, op_book(int(m.group(1)), self.role == "admin", self.patron_id if self.role == "patron" else None))
            except KohaError as e:
                return self._send(404 if e.status == 404 else 502, {"status": "error", "message":
                                  "Koha is not answering yet - try again in a minute." if e.status == 503
                                  else "Not found." if e.status == 404 else "Failed: %s" % e.body[:120]})
        if path == "/api/search":
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                return self._send(200, op_search((qs.get("q") or [""])[0]))
            except KohaError as e:
                return self._send(502, {"status": "error", "message": "Koha is not answering yet - try again in a minute."
                                        if e.status == 503 else "Search failed: %s" % e.body[:120]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.startswith("/api/me/"):
            if not self._guard(need_admin=False):
                return
            if self.role != "patron":
                return self._send(403, {"status": "error", "message": "Sign in with a library card first."})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(min(length, 2000)) or b"{}")
                if self.path == "/api/me/renew":
                    code, body = op_me_renew(self.patron_id, payload)
                elif self.path == "/api/me/password":
                    code, body = op_me_password(self.patron_id, self.addr, payload)
                elif self.path == "/api/me/hold":
                    code, body = op_me_hold(self.patron_id, payload)
                elif self.path == "/api/me/hold/cancel":
                    code, body = op_hold_cancel(payload, only_patron=self.patron_id)
                else:
                    return self._send(404, {"error": "not found"})
                return self._send(code, body)
            except KohaError:
                return self._send(502, {"status": "error", "message": "Koha is not answering yet - try again in a minute."})
            except ValueError:
                return self._send(400, {"status": "invalid"})
        if not self._guard():
            return
        try:
            if self.path.split("?")[0] == "/api/cover/upload":
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= COVER_MAX:
                    return self._send(413, {"status": "error", "message": "That picture is too large (1.5 MB at most)."})
                qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                code, body = op_cover_upload((qs.get("key") or [""])[0], self.rfile.read(length))
                return self._send(code, body)
            if self.path.split("?")[0] == "/api/scan":
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_IMAGE:
                    return self._send(413, {"status": "error", "message": "That photo is too large."})
                kind = "sticker" if "kind=sticker" in self.path else "isbn"
                try:
                    codes = decode_photo(self.rfile.read(length), kind)
                except ValueError:
                    return self._send(415, {"status": "error", "message": "Please send a JPEG or PNG photo."})
                return self._send(200, {"status": "ok", "codes": codes})
            length = int(self.headers.get("Content-Length", "0"))
            if length > (2_200_000 if self.path == "/api/ar/import" else 20000):
                return self._send(413, {"error": "too large"})
            payload = json.loads(self.rfile.read(length) or b"{}")
            ops = {"/api/add": op_add, "/api/manual": op_manual, "/api/undo": op_undo,
                   "/api/finish": op_finish, "/api/cancel": op_cancel, "/api/settings": op_settings,
                   "/api/barcodes/reserve": op_reserve, "/api/barcodes/assign": op_assign,
                   "/api/item/update": op_item_update, "/api/item/delete": op_item_delete,
                   "/api/item/copy": op_item_copy, "/api/book/delete": op_book_delete,
                   "/api/value/add": op_value_add, "/api/cover/delete": op_cover_delete, "/api/cover/refetch": op_cover_refetch, "/api/cover/pick": op_cover_pick, "/api/book/edit": op_book_edit, "/api/hold/add": op_hold_add, "/api/hold/cancel": op_hold_cancel, "/api/tags/set": op_tags_set, "/api/patron/reset-login": op_reset_login, "/api/logins/all": op_logins_all, "/api/ar/set": op_ar_set, "/api/ar/import": op_ar_import, "/api/checkout": op_checkout, "/api/return": op_return, "/api/renew": op_renew, "/api/patron/add": op_patron_add}
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
