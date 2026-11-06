"""Regression check for photo scanning: generate phone-like photos of real barcodes and make
sure the running Quick Add reads them (at the size the page sends, 2400 px).

    python3 -m venv /tmp/qa-venv && /tmp/qa-venv/bin/pip install zxing-cpp pillow
    PHOTO_DIR=/tmp/qa-photos /tmp/qa-venv/bin/python tests/gen_photos.py
    PHOTO_DIR=/tmp/qa-photos /tmp/qa-venv/bin/python tests/check_scan.py http://127.0.0.1:8082 admin PASSWORD
"""
import base64, io, json, os, sys, urllib.request
from PIL import Image, ImageOps

url, user, pw = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
D = os.environ.get("PHOTO_DIR", "/tmp/quickadd-photos")
auth = "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()


def scan(data, kind):
    req = urllib.request.Request(f"{url}/api/scan?kind={kind}", data=data, method="POST",
                                 headers={"Content-Type": "image/jpeg", "Authorization": auth})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["codes"]


def shrunk(path, m=2400):                      # what the page does before uploading
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    k = min(1, m / max(im.size))
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "JPEG", quality=90); return b.getvalue()


bad = 0
for n in sorted(f for f in os.listdir(D) if f.endswith(".jpg")):
    base = n[:-4]
    exp_file = os.path.join(D, base + ".expect")
    exp = open(exp_file).read() if os.path.exists(exp_file) else None
    codes = scan(shrunk(os.path.join(D, n)), "sticker" if base.startswith("sticker") else "isbn")
    ok = (codes[:1] == [exp]) if exp else (codes == [])
    bad += not ok
    print(("ok   " if ok else "FAIL ") + f"{base:20s} expected {exp!s:14s} got {codes[:2]}")
sys.exit(1 if bad else 0)
