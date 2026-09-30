# Building and installing Model-TG

Model-TG is built on your own computer from **your own copy** of the stock
Model:Cycles OS 1.13. No firmware image is distributed with this project, and
none should ever be shared: every image contains Elektron's firmware.

## What you need

- **The stock OS**: `model-cycles_OS1.13.syx`, from the Model:Cycles support
  page on elektron.se. It must be OS **1.13**, unmodified.
- **Python 3.**
- **ColdFire binutils** (`as`, `ld`, `objcopy`, `nm`, `objdump` for m68k):
  - macOS: `brew install m68k-elf-binutils`
  - Debian / Ubuntu: `sudo apt install binutils-m68k-linux-gnu`
  - others: any GNU binutils built for `m68k-elf`.

  `build.py` finds `m68k-elf-*` or `m68k-linux-gnu-*` on your PATH by itself;
  set `CROSS=<prefix>` to use another.
- **elektron-firmware-tool**, which unpacks and repacks the `.syx`:

  ```sh
  git clone https://github.com/mischa85/elektron-firmware-tool
  make -C elektron-firmware-tool
  ```

  Put it on your PATH, or pass `--tool path/to/elektron-firmware-tool`.

## Build

```sh
python3 build.py --stock path/to/model-cycles_OS1.13.syx
```

This writes `Model-TG.syx` (choose another name with `--out`) and prints its
SHA-256. Work files go in `build/`, which git ignores.

Options:

| option | what it does |
|---|---|
| `--out FILE` | where to write the firmware (default `Model-TG.syx`) |
| `--tool PATH` | the `elektron-firmware-tool` to use |
| `--no-tweaks` | leave out the third-party tweaks in `tweaks/` |
| `--assemble-only` | assemble, link and self-check `src/` without any stock firmware (what CI runs) |

The build refuses to produce an image if anything is off: every stock byte it
patches is checked first, so a different OS version fails instead of
producing a broken firmware. It also checks its own output: stack frames,
branch targets, the blob's placement and size, and more (see
[INTERNALS.md](INTERNALS.md)).

## Install

**Back up your projects and samples first.**

Install `Model-TG.syx` with **Elektron Transfer**, exactly as you would an
official OS update: connect the Cycles over USB and send the file to it with
Transfer.

Model-TG can make the Cycles present itself to Transfer as a Model:Samples,
so you can upload samples (**Device Config > Transfer**, **SMP**; see the
[user guide](USER_GUIDE.md#uploading-samples-with-elektron-transfer)). **Only
install an OS while it is set to CYC**, the stock identity. Every power-on
starts at CYC.

## Going back to stock

Install the unmodified `model-cycles_OS1.13.syx` the same way, with Transfer
and with the identity set to CYC. Projects that
use the Sampler machine rely on Model-TG and won't play those tracks on stock
firmware.

## Disclaimer

This is unofficial firmware, not made, supported or endorsed by Elektron.
You install it at your own risk. It may void your warranty, and bugs can crash
the device or lose unsaved work. If a build misbehaves, reinstall the stock OS
as above.
