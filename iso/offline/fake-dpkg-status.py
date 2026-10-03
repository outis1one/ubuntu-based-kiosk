#!/usr/bin/env python3
"""Write a dpkg status file claiming a set of packages is installed.

Usage: fake-dpkg-status.py MANIFEST LISTS_DIR > status

MANIFEST is an Ubuntu ISO's casper/*.manifest.full ("name[:arch]<TAB>version"
per line) - the packages a default Ubuntu Server install ends up with.
LISTS_DIR is an apt lists directory holding uncompressed *_Packages indexes.

iso/offline/build-bundle.sh resolves the kiosk's packages against this, so
apt only downloads what a freshly installed server is actually missing
(and makes the same alternative/virtual-package choices the real target
will), instead of the whole dependency closure down to libc6.
"""
import glob
import os
import sys

KEEP = ("Package", "Essential", "Priority", "Section", "Architecture",
        "Multi-Arch", "Source", "Version", "Replaces", "Provides", "Depends",
        "Pre-Depends", "Recommends", "Suggests", "Breaks", "Conflicts")


def stanzas(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        cur = []
        for line in f:
            if line.strip() == "":
                if cur:
                    yield cur
                    cur = []
            else:
                cur.append(line.rstrip("\n"))
        if cur:
            yield cur


def parse(lines):
    fields, order, key = {}, [], None
    for line in lines:
        if line[:1] in (" ", "\t") and key:
            fields[key] += "\n" + line
        else:
            key, _, val = line.partition(":")
            fields[key] = val.strip()
            order.append(key)
    return fields


def main():
    manifest, lists_dir = sys.argv[1], sys.argv[2]
    wanted = {}
    with open(manifest) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 2 or parts[0].startswith("snap:"):
                continue
            wanted[parts[0].split(":")[0]] = parts[1]

    exact, any_version = {}, {}
    for path in glob.glob(os.path.join(lists_dir, "*_Packages")):
        for st in stanzas(path):
            p = parse(st)
            name = p.get("Package")
            if name not in wanted:
                continue
            any_version.setdefault(name, p)
            if p.get("Version") == wanted[name]:
                exact[name] = p

    missing = 0
    for name, version in sorted(wanted.items()):
        p = exact.get(name) or any_version.get(name)
        if p is None:
            missing += 1
            continue
        out = [f"Package: {name}", "Status: install ok installed"]
        for k in KEEP[1:]:
            if k == "Version":
                out.append(f"Version: {version}")
            elif k in p:
                val = p[k]
                # The archive no longer carries this exact version (an
                # update superseded it), so these fields came from a
                # different one and its dependencies (version pins on
                # siblings, a newer kernel ABI...) don't describe what's
                # installed. Already-installed packages' own dependencies
                # are assumed satisfied anyway, so just leave them out.
                if name not in exact and k in ("Depends", "Pre-Depends", "Recommends"):
                    continue
                # Same for versioned Breaks/Conflicts - drop them outright
                # (unversioned ones still hold for any version).
                if name not in exact and k in ("Breaks", "Conflicts"):
                    val = ", ".join(c.strip() for c in val.split(",") if "(" not in c)
                    if not val:
                        continue
                out.append(f"{k}: {val}")
        print("\n".join(out) + "\n")
    print(f"fake-dpkg-status: {len(wanted) - missing} packages marked installed,"
          f" {missing} not in the archive indexes (skipped)", file=sys.stderr)


if __name__ == "__main__":
    main()
