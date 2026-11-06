"""Generate phone-photo-like test images containing real barcodes."""
import random, io, os
import zxingcpp
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

OUT = os.environ.get("PHOTO_DIR", "/tmp/quickadd-photos")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


def barcode(fmt, text, scale=4, height=90):
    bc = zxingcpp.write_barcode(fmt, text, width=0, height=height, quiet_zone=10)
    img = Image.fromarray(bc.__array__() if hasattr(bc, "__array__") else bc).convert("RGB")
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def scene(code_img, w=3024, h=4032, tilt=0, blur=0.0, contrast=1.0, bright=1.0, noise=0, quality=72, exif=None, size_frac=0.45):
    """Paste the barcode (on a white label) onto a coloured, busy 'book cover'."""
    bg = Image.new("RGB", (w, h), (random.randint(20, 90), random.randint(30, 80), random.randint(60, 140)))
    d = ImageDraw.Draw(bg)
    for _ in range(60):                                   # clutter: stripes, blobs, text-ish bars
        x, y = random.randint(0, w), random.randint(0, h)
        d.rectangle([x, y, x + random.randint(40, 600), y + random.randint(8, 60)],
                    fill=tuple(random.randint(0, 255) for _ in range(3)))
    label = code_img.copy()
    k = (w * size_frac) / label.width
    label = label.resize((int(label.width * k), int(label.height * k)), Image.LANCZOS)
    pad = Image.new("RGB", (label.width + 60, label.height + 60), "white")
    pad.paste(label, (30, 30))
    if tilt:
        pad = pad.rotate(tilt, expand=True, resample=Image.BICUBIC, fillcolor="white")
    bg.paste(pad, ((w - pad.width) // 2 + random.randint(-80, 80), (h - pad.height) // 2 + random.randint(-300, 300)))
    if blur:
        bg = bg.filter(ImageFilter.GaussianBlur(blur))
    bg = ImageEnhance.Contrast(bg).enhance(contrast)
    bg = ImageEnhance.Brightness(bg).enhance(bright)
    if noise:
        px = bg.load()
        for _ in range(noise):
            x, y = random.randint(0, w - 1), random.randint(0, h - 1)
            v = random.randint(0, 255); px[x, y] = (v, v, v)
    buf = io.BytesIO()
    kw = {"quality": quality}
    if exif is not None:
        e = Image.Exif(); e[0x0112] = exif; kw["exif"] = e
    bg.save(buf, "JPEG", **kw)
    return buf.getvalue()


E13 = zxingcpp.BarcodeFormat.EAN13
UPCA = zxingcpp.BarcodeFormat.UPCA
C39 = zxingcpp.BarcodeFormat.Code39

cases = {
    # name: (expected, bytes)
    "isbn_clean":       ("9780345339683", scene(barcode(E13, "9780345339683"))),
    "isbn_tilt8":       ("9780345339683", scene(barcode(E13, "9780345339683"), tilt=8, blur=1.2)),
    "isbn_tilt_neg12":  ("9780441172719", scene(barcode(E13, "9780441172719"), tilt=-12, blur=1.5, contrast=0.8)),
    "isbn_dim_noisy":   ("9780345339683", scene(barcode(E13, "9780345339683"), blur=1.4, contrast=0.7, bright=0.7, noise=60000, quality=55)),
    "isbn_small":       ("9780441172719", scene(barcode(E13, "9780441172719"), size_frac=0.22, blur=1.0)),
    "isbn_exif_rot90":  ("9780345339683", scene(barcode(E13, "9780345339683").rotate(90, expand=True), exif=6)),
    "isbn_upside_down": ("9780345339683", scene(barcode(E13, "9780345339683").rotate(180, expand=True))),
    "upc_a":            ("036000291452",  scene(barcode(UPCA, "036000291452"), tilt=5, blur=1.0)),
}
for name, (exp, data) in cases.items():
    open(f"{OUT}/{name}.jpg", "wb").write(data)
    open(f"{OUT}/{name}.expect", "w").write(exp)

# sticker (Code 39, 7 digits) and a photo with no barcode at all
open(f"{OUT}/sticker_c39.jpg", "wb").write(scene(barcode(C39, "0000042", scale=3), tilt=4, blur=1.0, size_frac=0.5))
open(f"{OUT}/sticker_c39.expect", "w").write("0000042")
blank = Image.new("RGB", (3024, 4032), (90, 60, 40)); ImageDraw.Draw(blank).rectangle([400, 900, 2600, 1300], fill=(200, 180, 60))
b = io.BytesIO(); blank.save(b, "JPEG", quality=80); open(f"{OUT}/no_barcode.jpg", "wb").write(b.getvalue())
print("wrote", len(os.listdir(OUT)) // 2, "photos to", OUT)
for n in sorted(os.listdir(OUT)):
    if n.endswith(".jpg"):
        print(f"  {n:22s} {os.path.getsize(os.path.join(OUT, n)) / 1e6:5.1f} MB")
