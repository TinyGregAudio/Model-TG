# Model-TG in the Modded-Cycles web flasher

The [Modded-Cycles](https://github.com/18nelli18/Modded-Cycles) web flasher
builds firmware in the browser from the user's own stock OS, with no
toolchain. Model-TG can be offered there as one of its tweaks. Model-TG
doesn't host that tweak file: whoever adds it to the flasher generates it
from a tagged Model-TG release and hosts it, linking back to this repository.

## Generating it

```sh
git checkout v<version>
python3 build.py --stock path/to/model-cycles_OS1.13.syx \
    --modded-cycles build/model-tg.json
```

The build prints the **MAIN OS sha256**. It must match the hash in that
release's notes on GitHub: that proves the tweak installs exactly the release.
If it doesn't match, don't ship it. Check the binutils version and that the
checkout is clean (the tweak's `version` must not end in `-dirty`).

The tweak file contains stock bytes (each write's `old`), so it is generated
locally from your own stock OS and never committed here or attached to a
release.

## What it contains

The format of the tweak files in Modded-Cycles' `tweaks/`:

| field | value |
|---|---|
| `id`, `name`, `version`, `source` | `model-tg`, the release, and a link to this repository |
| `device`, `os`, `section` | `Model:Cycles`, `1.13`, `3` (MAIN OS) |
| `writes` | `{off, old, new}` for every byte run that differs from stock |
| `append` | one part: everything after the stock section (the zero gap and Model-TG's code), at `0x401aa140`; no relocations |
| `conflicts` | drumkilla's `latching-mute`, `trig-preview` and `browser-scroll`, which Model-TG already includes |
| `result_sha256` | the MAIN OS hash the build must reproduce (pin it as the flasher's expected MAIN OS hash) |

Before it writes the file, the build replays it the way that builder does
(checks each `old`, writes each `new`, appends the part) and requires the
result to equal its own image byte for byte.

## Requirements for the flasher

- **Appending without a Syntakt OS.** Its append path currently requires a
  Syntakt OS file. Model-TG's append is plain data and needs none.
- **Exclusive.** Model-TG patches many sites, uses the filesystem cache
  blocks and appends after the OS, so it can't be combined with other tweaks
  beyond the conflicts listed.
- **Credit and license.** Show that it is Model-TG, link to this repository,
  and include its MIT copyright notice and license.
