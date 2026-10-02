# The web flasher

**https://tinygregaudio.github.io/Model-TG/** builds Model-TG in the browser,
with no toolchain: the user picks their own stock `model-cycles_OS1.13.syx`
and saves `Model-TG-<version>.syx`, which they install with Elektron Transfer
as usual ([BUILD.md](BUILD.md#install)).

Everything happens on the user's computer. Their OS file is never uploaded,
and nothing of Elektron's is published: the page only carries Model-TG's own
bytes.

## How it works

| file | what |
|---|---|
| `flasher/index.html` | the page |
| `flasher/worker.js` | runs the build off the page's thread |
| `flasher/patch.js` | checks the stock OS, applies the patch, checks the result |
| `flasher/elektron.js` | opens and repacks the `.syx`: a JavaScript port of the ELE3 path of [elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool) (MIT, its notice in the file) |
| `flasher/model-tg.json` | the release's patch, made by `build.py --flasher` |

1. The page decodes the SysEx and checks every packet and the container
   checksum, then unpacks the MAIN OS section. That section's sha256 must
   be stock OS 1.13's (`stock_sha256`).
2. It applies the patch: each `{off, hex}` write, then everything after the
   stock section (`append`, the zero gap and Model-TG's code). The result's
   sha256 must be the release's **MAIN OS sha256** (`result_sha256`).
3. It recompresses the section and repacks the `.syx` with every checksum and
   the container's HMAC trailer recomputed. The HMAC key is derived from the
   user's own OS, as the tool does.
4. It opens the new `.syx` again and checks it the same way before offering
   it.

The port is function for function, so the page's `.syx` is byte-identical to
`build.py`'s, which uses the native tool. Check it with:

```sh
python3 build.py --stock path/to/model-cycles_OS1.13.syx --flasher flasher/model-tg.json
node tools/test_flasher.js path/to/model-cycles_OS1.13.syx
```

It takes about 15 s in a browser, almost all of it compressing.

## What the patch file holds, and the checks on it

The patch file holds no stock bytes. Unlike the Modded-Cycles format
([PAYLOAD.md](PAYLOAD.md)), its writes carry no `old` bytes; hashes pin the
stock section instead. `build.py --flasher` also searches every run it writes
for runs of stock bytes, and fails if one of 128 bytes or more is not a plain
fill (zeros, `0xff`, repeated masks). Today the longest such run is
93 bytes: three small display routines (`value_invoker`, `value_invoker2`,
`gm_val`) cloned from stock on purpose, which are public as source anyway.

The **flasher** workflow (`.github/workflows/pages.yml`) publishes `flasher/`
on GitHub Pages on every push to `main` that touches it. Before deploying it
runs `build.py --assemble-only --check-flasher flasher/model-tg.json`, which
needs no stock firmware. That check proves the published code is exactly what
`src/` assembles to, and that the file was made from committed source (its
version does not end in `-dirty`).

## Publishing a release on it

After tagging (see [CONTRIBUTING.md](../CONTRIBUTING.md#making-a-release)),
from a clean checkout of the tag:

```sh
python3 build.py --stock path/to/model-cycles_OS1.13.syx --flasher flasher/model-tg.json
node tools/test_flasher.js path/to/model-cycles_OS1.13.syx
```

Check that the MAIN OS sha256 it prints is the one in the release notes. Then
commit `flasher/model-tg.json` to `main` and push. The workflow checks it and
deploys.

The first time only, set **Settings > Pages > Source** to **GitHub Actions**
on GitHub.
