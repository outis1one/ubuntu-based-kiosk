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
DEFAULT_SETTINGS = {"barcode_mode": "auto", "width": MIN_WIDTH, "location": ""}
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
    return {"collections": collections, "id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"), "author": b.get("author") or "",
            "year": b.get("copyright_date") or "", "isbn": b.get("isbn") or "", "type": b.get("item_type") or "",
            "copies": len(mine), "out": out, "shelves": shelves,
            "callnumber": next((i.get("callnumber") for i in mine if i.get("callnumber")), "") or ""}


def op_library(qs):
    """The Library grid: filter by shelf / format / status, search, sort, page."""
    def one(k):
        return (qs.get(k) or [""])[0]
    term = re.sub(r"[%_\\]", "", one("q")).strip()[:80]
    shelf, itype, status, coll = one("shelf"), one("type"), one("status"), one("collection")
    sort = one("sort") or "title"
    try:
        page = max(1, int(one("page") or 1))
    except ValueError:
        page = 1
    conds = []
    if term:
        like = {"-like": "%" + term + "%"}
        conds.append({"-or": [{"title": like}, {"author": like}, {"isbn": like}, {"ean": like}]})
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


def op_book(biblio_id, staff):
    b = koha("GET", "/biblios/%d" % biblio_id)
    items = koha("GET", "/biblios/%d/items" % biblio_id) or []
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
    return {"id": b["biblio_id"], "title": (b.get("title") or "").rstrip(" /:"), "subtitle": b.get("subtitle") or "",
            "author": b.get("author") or "", "year": b.get("copyright_date") or b.get("publication_year") or "",
            "isbn": b.get("isbn") or "", "publisher": b.get("publisher") or "", "pages": b.get("pages") or "",
            "edition": b.get("edition_statement") or "", "summary": b.get("abstract") or b.get("notes") or "",
            "series": b.get("series_title") or "", "type": b.get("item_type") or "", "copies": copies,
            "shelves": get_locations(), "collections": get_collections()}


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
                     "overdue": bool(due) and due < today, "renewals": c.get("renewals_count") or 0})
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
    names = {}
    for pid in sorted({r["patron_id"] for r in rows}):
        try:
            names[pid] = _patron_name(koha("GET", "/patrons/%d" % pid))
        except KohaError:
            names[pid] = "?"
    for r in rows:
        r["who"] = names.get(r["patron_id"], "?")
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
    return 200, dict(_shape_patron(p), status="added")


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
    out = {"links": [], "description": "", "subjects": [], "first_published": ""}
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
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; img-src 'self' https: data:; "
                         "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _role(self):
        """'admin', 'viewer' (read-only guest) or None. Sets self.via to 'koha' for a staff-site login."""
        self.via = None
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
            return "admin" if is_admin else "viewer" if is_viewer else None
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
        if not self._guard(need_admin=path not in ("/", "/api/state", "/api/search", "/api/library") and not path.startswith("/api/book/")):
            return
        if path == "/":
            return self._send(200, INDEX, "text/html; charset=utf-8")
        if path == "/api/state" and self.role == "viewer":
            return self._send(200, {"role": "viewer", "library": LIBRARY, "recent": [], "types": {}, "locations": [],
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
                                                shelves=get_locations(), collections=get_collections(), types=get_item_types()))
                m = re.match(r"^/api/book/(\d{1,9})$", path)
                if not m:
                    return self._send(404, {"error": "not found"})
                return self._send(200, op_book(int(m.group(1)), self.role == "admin"))
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
        if not self._guard():
            return
        try:
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
            if length > 20000:
                return self._send(413, {"error": "too large"})
            payload = json.loads(self.rfile.read(length) or b"{}")
            ops = {"/api/add": op_add, "/api/manual": op_manual, "/api/undo": op_undo,
                   "/api/finish": op_finish, "/api/cancel": op_cancel, "/api/settings": op_settings,
                   "/api/barcodes/reserve": op_reserve, "/api/barcodes/assign": op_assign,
                   "/api/item/update": op_item_update, "/api/item/delete": op_item_delete,
                   "/api/item/copy": op_item_copy, "/api/book/delete": op_book_delete,
                   "/api/value/add": op_value_add, "/api/checkout": op_checkout, "/api/return": op_return, "/api/renew": op_renew, "/api/patron/add": op_patron_add}
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
