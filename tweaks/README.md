# Third-party tweaks

From **drumkilla/elektron-model-tweaks** (MIT, see
`LICENSE-elektron-model-tweaks`):
https://github.com/drumkilla/elektron-model-tweaks

Only the Model:Cycles OS 1.13 definitions are vendored here; the upstream repo
also covers Model:Samples and ships its own applier, which we do not use -
`build.py` applies these writes itself so the whole image
comes out of one build.

| tweak | what it does |
|---|---|
| `latching-mute` | hold TRACK, tap FUNC: mute mode latches until FUNC is tapped alone |
| `trig-preview` | sequencer stopped, hold a step and press PAGE: the step sounds with its own note, p-locks and sound-lock |
| `browser-scroll` | a selected name in the browser scrolls when it does not fit |

## Why they compose with our patches

All 19 writes were checked against stock and against every site this project
patches:

- each write's `old` bytes match stock section 3 exactly
- no write overlaps any of our 37 patch sites
- their code lives in 0xff-filled space at 0x40147f22..0x40148b82, far below our
  blob at 0x401aba40, and below stock's end so the BSS-clear hole punch does not
  apply to it

The build asserts every `old` before writing, so if a future change of ours ever
lands on one of these, the build fails rather than producing a broken image.
