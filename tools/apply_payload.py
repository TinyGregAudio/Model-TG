#!/usr/bin/env python3
"""Apply a Model-TG payload to your own stock OS - no assembler needed.

    python3 tools/apply_payload.py --stock model-cycles_OS1.13.syx \\
        --payload Model-TG-<version>.payload.json --out Model-TG.syx

The reference implementation of docs/PAYLOAD.md: it unpacks section 3 from
your stock .syx with elektron-firmware-tool, checks it is the stock OS, applies
the payload, checks the result, and packs it back.
"""
import argparse, hashlib, json, os, subprocess, sys, tempfile

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--stock", required=True, help="your unmodified model-cycles_OS1.13.syx")
ap.add_argument("--payload", required=True, help="a Model-TG .payload.json")
ap.add_argument("--out", default="Model-TG.syx", help="the firmware to write")
ap.add_argument("--tool", default=os.environ.get("ELEKTRON_FIRMWARE_TOOL",
                "elektron-firmware-tool"), help="path to elektron-firmware-tool")
args = ap.parse_args()

pl = json.load(open(args.payload))
if pl.get("format") != "model-tg-payload/1":
    sys.exit(f"unknown payload format {pl.get('format')!r}")

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([args.tool, "-i", args.stock, "-d", str(pl["section"]), "-o", tmp],
                   check=True, stdout=subprocess.DEVNULL)
    sec = [f for f in os.listdir(tmp) if f.startswith(f"section_{pl['section']}_")]
    if len(sec) != 1:
        sys.exit(f"section {pl['section']} not found in {args.stock}")
    stock = open(os.path.join(tmp, sec[0]), "rb").read()
    if len(stock) != pl["stock_len"] or hashlib.sha256(stock).hexdigest() != pl["stock_sha256"]:
        sys.exit("this is not the stock OS the payload was made for "
                 f"({pl['device']} OS {pl['os']}) - use the unmodified file from elektron.se")

    img = bytearray(stock)
    for w in pl["writes"]:
        new = bytes.fromhex(w["new"])
        img[w["off"]:w["off"] + len(new)] = new
    app = pl["append"]
    if app["off"] != len(img):
        sys.exit("payload appends at an unexpected offset")
    img += bytes.fromhex(app["data"])
    if len(img) != pl["result_len"] or hashlib.sha256(img).hexdigest() != pl["result_sha256"]:
        sys.exit("the result does not match the payload's result_sha256 - not writing it")

    patched = os.path.join(tmp, "patched.bin")
    open(patched, "wb").write(img)
    subprocess.run([args.tool, "-i", args.stock, "-c", str(pl["section"]), patched,
                    "-o", args.out], check=True, stdout=subprocess.DEVNULL)

print(f"wrote {args.out}: Model-TG {pl['version']}, main OS sha256 {pl['result_sha256']}")
