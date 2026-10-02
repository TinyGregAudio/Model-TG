# Model-TG

**Unofficial firmware additions for the Elektron Model:Cycles (OS 1.13):
a full Sampler machine, resampling, beat-repeat with master FX, and more.**

Model-TG is built on your computer from your own copy of the stock OS. It
patches new code into the firmware, so everything the Cycles already does
keeps working.

> **Unofficial.** Not made, supported or endorsed by Elektron. You install it
> at your own risk: back up first, and see [going back to stock](docs/BUILD.md#going-back-to-stock).
> No firmware images are distributed here or anywhere by this project.
> [Build your own](docs/BUILD.md).

## What it adds

- **A Sampler machine**, the seventh machine on any track. It plays samples
  from the Cycles' internal storage, a different sample per pattern, with
  p-lockable per-step sample locks.
- **Seven playback modes:** One shot, Loop, Slice, Granular, Stretch
  (time-stretch), Pluck (Karplus-Strong) and Wave (wavetable), each with its
  own options.
- **Slicing:** equal, by transients, or your own markers set in a
  full-screen slice editor. You can tap them in time, snap them to zero
  crossings, and set a pattern's trigs to walk the slices with one press.
- **Resampling** of a track, the whole output or the computer's USB audio,
  in mono or stereo, straight onto a track, then saved to internal storage.
- **Stereo samples** in every mode.
- **Retrig page:** beat-repeat on the tempo grid, plus 12 master FX (drive,
  crush, rate, pump, filter, ring mod, noise riser, gate, tape stop, vinyl,
  flanger).
- **Attack, Filter and Resonance** added to all the stock machines.
- **Slide trigs:** a trig that glides every differing parameter, p-locks
  included, from the trig before it, on any machine.
- **Scale Lock**, **sample upload through Elektron Transfer**, a **System**
  page with CPU and memory use, and lower CPU use overall.

The full, button-by-button guide is in **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**.

## Getting it

```sh
git clone https://github.com/TinyGregAudio/Model-TG
cd Model-TG
python3 build.py --stock path/to/model-cycles_OS1.13.syx
```

Then install `Model-TG.syx` like an official OS update. The tools you need,
and how to go back to stock, are in **[docs/BUILD.md](docs/BUILD.md)**.

No toolchain? See [Without a toolchain](docs/BUILD.md#without-a-toolchain).

## Contributing

Pull requests for new behaviour are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md) to get started, and
[docs/INTERNALS.md](docs/INTERNALS.md) for how the firmware is patched and
what is already known about it.

## Credits

- [elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool)
  unpacks and repacks the OS.
- [drumkilla/elektron-model-tweaks](https://github.com/drumkilla/elektron-model-tweaks)
  provides the latching mute, trig preview and browser scroll tweaks (MIT,
  vendored in `tweaks/`).

## License

[MIT](LICENSE) for the code and documentation here. Elektron's firmware is
not part of this project and is not covered by it. "Elektron" and
"Model:Cycles" are trademarks of Elektron Music Machines; they are used here
only to say what this works with.
