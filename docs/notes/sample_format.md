# Model:Cycles on-device sample format

Established 2026-09-16 from a byte-exact copy of a real device file, not inferred.

## How the file was obtained

Elektron Transfer's download wraps the file in a `.mcpst` **ZIP archive**:

```
Bottle Tops - 1498.mcpst   (17,405 B, PK\x03\x04)
├── manifest.json          {"FormatVersion":"1.0","ProductType":["27"],
│                           "Payload":"Bottle Tops - 1498","FileType":"Sound"}
└── Bottle Tops - 1498     23,632 B  <- the raw device file, unmodified
```

The payload is **exactly** the 23,632 B recorded for that file in the device's
own directory listing, so Transfer
passes the stored bytes straight through. Nothing is resampled or converted in
either direction — the audio is 48 kHz 16-bit as stored.

## Layout

```
offset  size  meaning
------  ----  --------------------------------------------------
0x00       4  0
0x04       4  data length in BYTES            (23552 = 0x5C00)
0x08       4  sample rate in Hz               (48000 = 0xBB80)
0x0C       4  0
0x10       4  sample count - 1                (11775 = 0x2DFF)
0x14       4  0x7F000000                      (level / normalisation?)
0x18    0x28  0
0x40     ...  PCM: signed 16-bit BIG-ENDIAN, mono
    +datalen  16 bytes of 0x00 (trailer)
```

`file size = 64 + data length + 16 = data length + 80`

Self-consistent on the reference file:
- `64 + 23552 + 16 = 23632` = actual size
- `23552 / 2 - 1 = 11775` = the count-1 field
- decoded PCM: 11,776 samples, 0.245 s @ 48 kHz, min -6091 max 5952, mean -0.7

The `+80` rule explains the `…,080` sizes noticed in the captured inventory:

| file | size | data | samples | duration |
|---|---|---|---|---|
| Bottle Tops - 1499 | 16,596 | 16,516 | 8,258 | 0.172 s |
| Cymatics - Grandmother Keys | 264,080 | 264,000 | 132,000 | 2.750 s |
| Cymatics - Frozen Keys | 360,080 | 360,000 | 180,000 | 3.750 s |
| Cymatics - Vintage Pad | 2,343,742 | 2,343,662 | 1,171,831 | 24.413 s |

## What this means for the Sampler machine

- **Big-endian 16-bit is ideal for us.** The engine is m68k, so a sample is a
  plain `mvsw` load; `sampler_render` currently reads 32-bit longs from
  `sample_data`, so the only change is `mvsw` + `lsll #16` (or keep 16-bit
  internally and shift when feeding the oversample buffer).
- **48 kHz matches the engine rate**, so the existing pitch-step maths is
  unaffected.
- **Sample Start / Sample End become meaningful immediately**: `count-1` at
  `+0x10` gives the bound directly, no parsing needed.
- A 24-second sample is available on the device today, versus the 4,096-sample
  (85 ms) clip currently embedded in the firmware.

The file itself is factory content and is not included here.

## Second-file confirmation (2026-09-16)

`Egg boxes - 169`, downloaded independently, payload **27,228 B** — exactly the
size recorded in the capture:

```
data len  27,148    rate 48000    count-1 13,573    field5 0x7F000000
64 + 27148 + 16 = 27228   = actual size          MATCH
27148/2 - 1     = 13573   = count-1 field        MATCH
decoded: 13,574 samples, 0.283 s, min -31153 max 30869  (near full scale)
```

Two independent files, every field self-consistent. The format is settled.

## The directory "hash" is not a plain checksum

The 4-byte value preceding each entry in a ReadDir response does **not** match
any obvious content hash of the file we now hold locally:

| candidate (for `Egg boxes - 169`, directory value `0x18f8a6ad`) | result |
|---|---|
| `crc32` whole file | `0xfa0cf457` |
| `crc32` PCM only | `0x32e4206a` |
| `crc32` from 0x40 | `0xd8abf5d4` |
| `adler32` whole file | `0x4974e89e` |

So it is either a custom hash or a storage locator. Unresolved — and it is
exactly why the reader-factory descriptor (`fsprobe2`, tag `0x7B`) still matters:
that descriptor carries whatever value actually addresses the file on the eMMC.
