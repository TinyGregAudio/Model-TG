# The Model-TG payload

Each Model-TG release has a **payload** attached: Model-TG expressed as changes
to the stock OS. A flasher, or `tools/apply_payload.py`, applies it to the
user's own copy of the stock OS. That way people can install Model-TG without
an assembler, and no Elektron firmware is ever distributed.

It contains only Model-TG's own bytes. There is no stock code in it: instead of
checking individual stock bytes, the whole stock section is checked against a
hash.

## Format (`model-tg-payload/1`)

A JSON file, `Model-TG-<version>.payload.json`:

| field | meaning |
|---|---|
| `format` | `"model-tg-payload/1"` |
| `name`, `version` | `"Model-TG"`, and the release it was built from |
| `device`, `os` | `"Model:Cycles"`, `"1.13"` |
| `section` | the OS container section it applies to: `3` (MAIN OS) |
| `stock_len`, `stock_sha256` | length and SHA-256 of that section, decompressed, from the unmodified `model-cycles_OS1.13.syx` |
| `result_len`, `result_sha256` | length and SHA-256 of the patched section |
| `writes` | list of `{"off": <int>, "new": "<hex>"}`: bytes to write over the stock section at byte offset `off` |
| `append` | `{"off": <int>, "data": "<hex>"}`: bytes appended after the stock section; `off` equals `stock_len` |

## Applying it

1. Decompress `section` from the user's stock `.syx`.
2. Check its length and SHA-256 against `stock_len` and `stock_sha256`.
   **Stop if they differ:** it isn't the stock OS 1.13.
3. Apply every write in `writes`.
4. Append `append.data`.
5. Check the result against `result_len` and `result_sha256`. **Stop if they
   differ.**
6. Put the result back as `section`, recompute the container's checksums, and
   write the `.syx`.

Pin `result_sha256`, not the `.syx` hash: different compressors produce
different `.syx` files from the same content.

`tools/apply_payload.py` does all of this using
[elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool)
for steps 1 and 6.

## Where it comes from

`python3 build.py --stock … --payload FILE` writes it during a normal build. It
diffs the finished image against the stock section, re-applies the result to
stock, and only writes the payload if that reproduces the image exactly.
