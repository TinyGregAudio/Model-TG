# Model-TG internals

How Model-TG changes the Model:Cycles firmware, for anyone reading or extending
`src/`. For using the features, see [USER_GUIDE.md](USER_GUIDE.md); for building,
[BUILD.md](BUILD.md).

Addresses are for **OS 1.13** and are virtual (`0x40000400` is the start of
section 3, the main OS). The build asserts the stock bytes at every site it
touches, so a different OS version fails the build instead of producing a bad
image.

## How the image is put together

- `build.py` unpacks section 3 from your stock `.syx`, appends one linked blob
  of our code at `0x401ab750` (in filesystem cache blocks the firmware gives up
  to us), redirects stock code into it with small asserted patches, applies the
  vendored tweaks, and repacks.
- `src/model_tg.s` is the bulk: the Sampler machine, its modes, pages, effects,
  resampling, retrig, master FX and the stock-machine optimisations.
- `src/phase1.s` holds the boot hook (it clears BSS around our blob and sets up
  the caches), the machine catalogue lookups and the trampoline that
  `src/track_table.s` continues.
- Hooks follow one pattern: a `jmp`/`jsr` patched over a stock call or
  prologue, the replaced instructions replayed in our code, and control handed
  back. Every patch in `build.py` states the stock bytes it expects.

## Useful firmware facts

These were each verified on hardware; they save a lot of rediscovery.

- **Screen y runs from the bottom** for text (`0x40071a04`), rectangles
  (`0x40070dea`) and the framebuffer. Draw top-based layouts at `63 - y`
  (text: `55 - y`).
- **Keys:** the key-code accessor `0x4007240c` is what every consumer calls, so
  `key_hook` wraps it to see chords. Codes: FUNC 1, TRACK 2, PATTERN 3,
  RETRIG 4, PRESET 5, PUNCH 6, RECORD 9, RETURN 12, SETTINGS 13, PAGE 15,
  trig keys 16-31,
  DATA press 32. Event flags at +16: bit 0 down, bit 3 repeat, bit 4 click
  (a short press, on release), bit 5 long press. Model-TG's chords use
  SETTINGS as the modifier (`kh_mod`), leaving stock's TRACK chords alone.
- **Knobs** carry their index at event+12: DATA 1, and the twelve parameter
  knobs 2-13 - panel knob n is index n + 1. This file and the user guide use
  the panel numbers. Clicks with acceleration: `0x4006f73a(event, slow, fast)`.
- **Views:** closing a view is deferred (the close method only sets flags);
  unhandled keys are *not* passed down the view stack; popups are views on the
  root stack; never close a page that is not the top view.
- **Notes:** the core note-on is `0x4008171e(track, note, velocity, 0x40, 0,
  -1, -1)` and note-off `0x4008145e(track, note, 0x40)`; the track pad's wrapper
  `0x4001d05e` also records into the sequencer.
- **Pattern data:** a track's step data comes from
  `0x4000cfcc(0x4000f208(0x400cf866()), track)` (vtable +40 gives the 722-byte
  block). Flags word at +2 x step (bit 0 = trig); trig parameters are per-step
  signed bytes, -1 meaning the track default: Velocity +128, Length +192,
  **Trig Note +580** (setter `0x40016642`), sound lock +644. P-locks are a
  separate store: set `0x4001646a(track, step, slot, value)`, clear
  `0x400164b0`, get `0x4001591e`; slots come from the parameter table at
  `0x4010dce0` (56-byte entries, slot at +4).
- **Small files:** open `0x4007bc5e(path, "w"/"r", fh[16])`, read
  `0x4007baaa(buf, len, fh)`, write `0x4007bb0a(buf, len, fh)`, close
  `0x4007bc1c(fh)`. Task context only; write from a UI-task message (see
  `mk_post`), never on the LED clock, which outranks the audio.
- **Audio path:** channels at `0x80001858 + track x 128`, 32 samples a block;
  the main mix `0x40056610` sums them into the interleaved stereo bus at
  `0x8000b990`, which `0x400565c6` then scales x4 for the output.
- **Sample format** in internal storage: see [notes/sample_format.md](notes/sample_format.md).

## What each part does, and how

- Sampler machine (index 6), assignable to any track
- Samples per pattern: each pattern's Sampler tracks play the samples that
  pattern names (the "SMP" token in its sound name). On a pattern change a
  track takes its new sample at its next note, loading it first if it is not
  in RAM; if RAM is full, samples the new pattern does not use are dropped -
  first what nothing uses, then files only other patterns use (they reload),
  last unsaved takes only other patterns use. The pattern playing always
  plays. Up to 64 samples resident, shared when tracks or patterns name the
  same file. All 96 patterns' kits are read in RAM (kit n at 0x409C9C80 +
  n x 7094, track sounds at +28 + t x 100), checked once against the live
  sound objects (popup K1)
- Sample locks: hold a step, press Preset and open a sample file - the step
  plays that sample. The stock lock path stores a sound in the Sound Pool
  (vtable +80 of the pool at kit object +628, 0x40014f18); a sample is no
  preset, so pool_store_hook stores instead a copy of the track's sound whose
  token names the sample, and the stock lock follows - or, when that very
  sound is already pooled, the lock reuses its slot. At the note, sp_lock
  reads the trig's sound (0x800015a0 + (147 + t) * 4, stored by 0x40058a0a)
  and, for a pool sound naming a resident sample, plays it. A lock is a
  whole sound: Start/End/Filter as they were when locked; mode and options
  follow the track. Pool sounds' samples are preloaded and kept. Turning
  Start or End while holding a locked step shows the locked sample's
  waveform (the step's lock from 0x40015996, the pool sound it plays)
- Preloading: every sample the project's patterns name is loaded in the
  background, one per UI tick, into free space only, leaving 16 MiB for
  recording - so pattern changes do not wait on the disk
- The selected track's sample name on the machine page: with the Sampler
  highlighted, "Sample" becomes the file's name, 7 characters at a time,
  scrolling like the browser (0.17 s a character, 0.5 s at each end). Names
  come from the file system (0x4007afd4, the path of inode n = the file's
  position in the inode table), checked against the file's size first
- Sample choice persists per project, stored in the sound name, reloaded
  automatically at boot
- 4-pole Moog-style ladder filter with logarithmic cutoff and resonance makeup;
  at Resonance 0 a lighter loop, bit-exact with the full one, and both ladders
  (mid and side) start from rest when the gain returns after a trigger
- Reverse playback: set Sample Start above Sample End. No extra parameter, and
  it p-locks per trig because both dials already do
- Seven playback modes per track: One shot, Loop, Slice, Granular, Stretch,
  Pluck and Wave (wavetable). Hold **Settings** and press **Preset** to open the mode menu
  - laid out like the machine page, the current mode's name in a panel and a
  row of seven markers - turn any knob to choose, and Return, Preset or Settings
  to close. The mode is stored in the sound name; one shot is the default. A loop returns to
  Sample Start, and composes with reverse. In the last three the four page dials
  take on new jobs (and labels), but stay the same parameters - so they p-lock,
  take LFOs and persist exactly as before
- Per-mode options: hold **Settings** and press **Punch** (key code 6) to open
  the current mode's settings list, laid out like Scale Setup: LEVEL/DATA
  moves between rows, a press edits one, and LEVEL/DATA then changes it.
  Settings or Return closes it. Everything is saved with the project.
  **EFX**, **CHN** and **STU** belong to the track, not the mode, so they
  carry over when the mode changes.
  - One shot: **EFX** Filter, Lo-fi (Rate 48 kHz to ~1 kHz, Crush 16 bits
    to 1), Tape (wow/flutter and saturation), Vinyl (crackle, hiss and wow)
    or None; Lo-fi, Tape and Vinyl take over the Filter and Res dials as
    their two controls. **CHN** Mono or Stereo. **STU** stutter OFF, 1/4, 1/8,
    1/16, 1/32, 8T or 16T at the project tempo.
  - Loop: **TYP** Forward, Reverse or Ping-pong; **XFD** crossfade OFF, 10,
    25, 50, 100 or 250 ms (Forward and Reverse); **SYN** OFF or 1/2/4 bars
    (the loop window lasts exactly that); **EFX**; **CHN**.
  - Slice: **MOD** equal, at transients (the strongest rises in energy,
    each pulled back to its hit) or **MAN** (your own markers); **SLC** 8,
    16 or 32 (in MAN, how many the markers make); **EFX**; **CHN**; **EDT**
    opens the slice editor; **SEQ** sets the track's trigs, in step order, to
    walk the slices (the first trig slice 1, the next slice 2, round again
    after the last) - their Trig Note, through the stock setter.
  - Granular: **SHP** grain shape (Hann, Triangle, Perc, Square), **DIR**
    Forward, Reverse or Random, **FRZ** freeze (Position is taken once, when
    the note starts); **CHN**.
  - Stretch: **MOD** Forward, Reverse, Once forward/reverse, Sync 1/2/4 bars
    (at Speed 96 the whole sample takes exactly that); **CHN**.
  - Pluck: **MOD** Synth or Drum (Karplus-Strong's random sign flip); **EXC**
    exciter Sample, Noise or Click (the generated ones need no sample);
    **CHN**.
  - Wave: **CHN**.
  - Defaults: Filter, Mono, stutter OFF. Stereo costs about twice the CPU,
    so it is opt-in per track.
- Slice mode: the sample splits into slices and the note picks one, so
  the trig pads play slices live (pad 1 = slice 0) and sequenced steps select
  them per trig. Playback is forced to 1.0x, Start and End trim within the
  slice (Start > End reverses it), and Scale Lock is bypassed so consecutive
  pads stay consecutive slices
- Slice editor (EDT; MOD goes MAN, keeping the slices it had): the whole
  sample full screen, markers dotted and the selected slice's start solid,
  a bar along the selected slice, "SLICE n/total" and its start in seconds.
  Trig keys 1-16 play and select slices (FUNC: 17-32); DATA selects; knob 1
  moves the start a column a click, knob 2 a sixteenth of one, with FUNC
  held either snaps on to the next zero crossing; knob 3 zooms around it;
  DATA's press splits the selected slice, FUNC + press removes its marker.
  Up to 32 slices, 64 samples at least. Tap: PUNCH arms it, the
  first trig press plays the whole sample from its start - Amp Decay held
  at full and the track never idled - and each press after drops a marker
  where it plays; PUNCH again, or the sample's end, stops it.
  Markers belong to the sample (by its hash) and are kept on disk as
  /Slices/<hash> (136 bytes, "SLC1"), written through the stock small-file
  calls in a UI-task message when the editor closes, read the first time a
  MAN track wants them. The options' packed state has a new tag (0x7) for
  the wider slice range; older projects decode as before
- Granular: up to 6 Hann-windowed grains per track at the note's pitch.
  Position, Grain Size (10 ms - 1 s), Density (four lengths apart up to four
  overlapping) and Spray (random scatter around Position)
- Stretch: granular with a playhead moving through the sample at Speed
  (0 = frozen, 96 = original speed, 127 = ~3.8x), so time and pitch are
  independent. Speed, Grain Size, Density, Spray; the playhead loops
- Pluck: a Karplus-Strong string at the note's pitch (note 60 = 261.6 Hz),
  struck by a burst of the sample. Strike Pos, Strike Len (1 ms - 1 s; long
  strikes make it a resonator), Tone and Feedback. Tuned to within ~3 cents,
  compensating for the loop filter's own delay
- Wave: the sample cut into single-cycle frames and played as an
  oscillator at the note's pitch (note 60 = 261.6 Hz). Wave Pos morphs between
  adjacent frames, Frame Size steps 32..4096 samples (2048 for Serum/Vital
  tables), Smooth runs from hard PPG-style steps to a continuous morph, and
  Detune adds two unison voices up to +-50 cents at constant peak level.
  Rendered at 2x, so the stock decimator filters what would otherwise alias
- Fine Start/End on Sampler tracks, in every mode: a slow turn moves an eighth
  of a step, faster turns scale smoothly back to whole steps, and the value is
  drawn like Pitch - big whole number, small decimal
- Waveform: turning Start or End on a Sampler track shows the sample full
  screen, the name and value along the top. One shot and Loop: Start and End
  as lines (the one being turned solid), the part outside the window dotted.
  Slice: the slice last played, zoomed to the full width, with the same
  markers and its number (the whole sample and its boundaries until one has
  played). Granular and Pluck: Position / Strike as a line. Stretch and
  Wave keep the stock display. The columns are worked out once per
  sample and view and kept, so turning the dials only redraws them. The
  sample shown is the one the step plays: with a step held, its sample
  lock if it has one; otherwise the pattern's own sample
- Switching a track to the Sampler sets Start/End/Filter/Res to their defaults,
  applied where the firmware commits the machine change, so it works with the
  sequencer stopped and is never mistaken for a project load
- All six machine parameters are LFO destinations, in the same list positions
  the stock machines use
- Attack, on **all six machines**: hold **Preset** and turn **Decay**. A real
  parameter (`Attack`/`ATK`), 0 = instant up to about 2 s, default 0. The ramp
  is applied in the amp envelope stage every machine passes through. It is
  LFO-modulatable and persists with the project
- Filter and Resonance on **all five stock machines**: hold **Preset** and turn
  **Sweep** (Filter, `FLT`) or **Contour** (Resonance, `RES`). The Sampler's own
  4-pole ladder, run after the amp envelope; wide open with no resonance it is
  bypassed. It starts each note from rest (the stock chain fades the old note
  out after this stage, so carried-over state clicked on every note), and at
  Resonance 0 runs a lighter loop - no feedback, makeup or inner clamps -
  bit-exact with the full one (Chord: filter cost 2.5 -> 1.4 points). Real
  parameters: LFO destinations (not listed on Sampler tracks,
  which keep their own Filter/Res), saved with the project - Filter stored
  inverted so older projects load wide open
- LFO destinations Attack, Filter and Resonance survive a save: the stock save
  maps a destination through a 23-entry table they are past the end of, so
  they are carried in a spare record byte and put back on load
- Every mode's options are saved per sound, packed into two spare parameter
  words (k=26/27, record slots 28/29): all of them, not only the current
  mode's, and with or without a sample loaded - one mixed-radix number with
  a tag in the top four bits. A value without the tag (any older project)
  loads the defaults. A track newly switched to the Sampler starts from the
  defaults
- Resampling: hold **Settings** and press **Record** (key code 9) for the Resample menu. **SRC** one
  track dry (after its amp envelope, Attack and Filter; before pan, volume and
  the effect sends) or **MST**, the whole output, or **USB**, the computer's audio (USB mode A+M:
  UAC2 stereo 32-bit on iso endpoint 3, read each block by 0x40002ae0 into
  0x40fe4cf0, captured at full scale and played back as any sample); **CHN**
  **STE** records it in stereo (the
  whole output, or a track playing a stereo sample), **MON** summed to mono;
  **LEN** 1, 2, 4, 8 or 16 bars at the tempo, **PTN** the pattern's length,
  or **MAN** until stopped; **STA** **PAT** (step
  1 of the pattern - the top of the loop, or pressing play), **NOW**, or
  **SND** (the source's first sound above -40 dBFS); **CLR** empties the track in this pattern (written into its sound name, so it
  is saved);
  **REC** arms, shows the bar or seconds while capturing, and stops or
  cancels; **TRM** trims the level -6..+6 dB; **SAV** asks for a name in the stock
  name editor (ModelsNameView, as the pattern/preset renames; prefilled with
  Take-XXXXXX, up to 12 characters, backing out saves nothing), writes the
  take to disk as `/Resampled/<name>` and relinks the track to that file, so
  it survives a project save and reload. The take becomes the sample of
  the track the menu was opened on, playable in every mode. A bar-length take
  hands over seamlessly: PAT starts on the audio block where step 1 is heard
  (the sequencer schedules a tick ahead), the take goes on the track ~5 ms
  before the bar ends while its last blocks are still written in place, and
  MUT silences the other tracks on the exact block the bar ends. The whole
  output is captured from the master bus (before the output stage) at unity,
  and each take carries a playback gain - 1 / (0.382 x the destination's mixer
  gain), measured on hardware - so it replays at the level it was heard. An unsaved take lives in sample
  RAM only: reloading the project brings back the track's previous sample
  **MUT** ON mutes every other track (and unmutes the take's own) once a take
  lands, through the stock mute setter, so LEDs and the mute CC follow. A
  muted destination track is unmuted four ticks before the bar ends, because
  the sequencer drops trigs on muted tracks when it schedules them
- Stereo takes are stored as two planes - mid (L+R)/2, then side (L-R)/2 -
  and flagged in the header (bit 0 of +0x20, beside "RSG1"), so every mode and
  the waveform read the mid unchanged. With **CHN** Stereo every mode plays
  them in stereo, effects included; with Mono (the default) they play the
  mid only. The side is filled and run
  through the same filter, decimator, envelope, Attack and take gain, with the
  voice state saved and restored around it, and at the mixer the track's
  channel becomes mid+side for the left pass and mid-side for the right - the
  stock firmware swaps its FX returns the same way. The sends hear the mid;
  pan balances L against R. SAV writes both planes and loading brings them
  back in stereo. A manual take reserves half the free space for its side and
  gives back what it did not use. A stereo take or file whose side is
  silent (under -84 dBFS) is kept as mono
- Saving runs while the music plays: the save goes through the stock
  FileWriter a piece per UI-task message, with the stock "mute audio while a
  file is open" hook switched off for our writer only (stock saves keep it)
- Sample upload with Elektron Transfer: **Device Config > Transfer** switches
  the identity between **CYC** (stock) and **SMP** (answers as a Model:Samples:
  product 25, its command list, "Model Samples"). Reconnect Transfer after
  switching; every boot starts at CYC. The two firmwares route every command
  number to the same place, but the Cycles only answers the raw file-system
  family, so in SMP the Samples' sample-family commands are relabelled to their
  raw twins on the way in and the replies back on the way out. In SMP use
  Transfer for samples only, and never accept an OS update from it. In SMP
  the machine also answers Transfer's stereo query (message 9, "sample_file.
  interleaved_stereo_support") with yes, so stereo WAVs upload in stereo and
  load as mid/side
- Idle tracks cost nothing: a track renders only while its note can still be
  heard. After a trig, its output is measured every block; once it has
  stayed under 2 LSB of 16-bit for 0.25 s (stock machines) or 3 s (the
  Sampler, so a take's silent gap is not taken for its end), the track is
  skipped until its next trig - the stock firmware renders all six tracks
  all the time. Vinyl adds crackle and hiss only while there is sound under
  it, so a finished note can go idle. All Sound Off (a stop while stopped,
  CC 120) leaves idle tracks idle and ends the rest after ~5 ms of silence
- Mute (FUNC + pad) on a Sampler track fades it out in 64 samples and ends
  its note: silent and free while muted, and silent after the unmute until
  its next trig. Stock machines keep the stock mute - no new trigs, the note
  rings out - and go idle once it has
- **Device Config > System**: a full-screen page with the audio load (CPU,
  now and as a bar), the worst block since it opened (PEAK), and sample
  memory - used of the region with a bar (RAM) and what is left (FREE).
  Refreshed twice a second; Return, Preset or Settings closes it. Turn DATA
  right for a second page: each track's share of the block (T1-T6, tenths of
  a percent, from sampler_dispatch's per-track timer), TRACKS their sum,
  OTHER the rest (mixer, send effects, output, per-block hooks) and TOTAL.
  Built on the machine-page page the mode menu uses (kind MM_SYS), drawn by
  sys_render
- Output retrig (beat repeat): hold **Settings** and press **Retrig** for a
  full-screen page. The track pads choose which tracks it repeats (all lit
  at first); trig keys 1-16 repeat their output - 1/64 at step 1 up to a bar
  at step 16, straight and triplet divisions between. A repeat is locked to
  the tempo grid (from step 1's time), its length and its start: the slice
  runs from the last grid line of its length before the press. **RETRIG**
  Momentary (held; the newest held step wins, releasing falls back to one
  still held) or Latch (a press starts or switches, the same step stops);
  **FX RETURNS** OFF or ON (the delay and reverb returns repeated too). DATA
  moves between the rows, a press edits one. Settings, Retrig or Pattern closes
  it and the repeat fades out. Each track (and a stereo track's side) keeps
  a 2.7 s 16-bit history, 4 MiB at the top of the sample region; repeats
  cross over live in 64 samples and each cycle is faded at its ends. A track
  whose pad is off, and the FX returns while OFF, are not recorded; their
  history is cleared when they come back on
- Master FX on the retrig page: its knobs are effects on the tracks the pads
  light, after the repeats and before the mixer and the delay/reverb sends
  (so the sends hear them): knob 1 Drive (soft clip to 8x, level
  compensated), 2 Crush (16 bits to 1), 3 Rate (48 kHz to 1 kHz), 5 Filter
  (a 2-pole topology-preserving state-variable filter on the EMAC: left of
  centre low-pass 20 kHz -> 30 Hz, right high-pass 20 Hz -> 10 kHz, centre
  off), 6 Resonance (Q 0.5 -> 10), 9 Gate (off, 1/4, 1/8, 1/8T, 1/16,
  1/16T, 1/32 on the tempo grid), 10 Tape stop (a brake: the track read back
  from its retrig history at a slowing speed, the level following it), 4 Pump
  (the lit tracks ducked by the tracks the pads have turned off - their peak,
  instant attack, ~170 ms release - or, with none off, on every quarter
  note), 7 Ring mod (a sine, 30 Hz to 4 kHz, before the filter), 12
  Flanger (a 0.3 - 6 ms delay from the retrig history, swept once a bar).
  Two more are added to the mixed output instead, after the tracks are
  summed, whatever the pads, levels or mutes (not sent to the delay/reverb):
  8 Noise riser (white noise through a high-pass climbing 200 Hz -> 8 kHz
  with the level) and 11 Vinyl (the Sampler's hiss and clicks, by Wear). Each
  is bypassed at 0; the bottom line shows a knob's value for a second. The
  effects outlive the page (and a pattern change); Return on the page, or
  Settings + Return anywhere ("Master FX off"), turns them all off. The pads'
  track selection is kept too
- On the retrig page Return resets (the FX and a latched repeat) rather
  than closing; Pattern closes it so the pattern can be chosen as usual
- Takes belong to the pattern they were recorded into: a take plays only
  there (until SAV names it in the sound), and comes back on returning
- Scale Lock: notes snapped to a scale, with Scl/Key items in the Scale menu
  (FUNC + PAGE), added by `install_scale_menu_item`
- 64 MiB sample region, less 112 KiB at the top for Pluck's delay lines (mid
  and side), 2.25 KiB below them for the slots' file names, 4 MiB below that
  for the retrig histories and 2 KiB for the waveform popup's columns and the
  slice tables
- The upper 40 MiB of the sample region (0x4C000000 up) is in the data cache:
  ACR1, write-through, set at boot before the firmware enables its caches
  (stock caches only 0x40000000-0x47FFFFFF). Files are placed there first; a
  take records there when 16 MiB is free, else in the larger free area. The
  lowest 16 MiB block also holds the audio output and the eMMC bounce buffer,
  so it stays uncached. Granular tracks measured ~18% cheaper
- Cheaper stock machines (measured: Kick 10.4% -> 9.0% of a block, Snare
  ~6.8% -> 5-6%). The 2-input mixer Kick, Snare, Metal and Perc share
  (0x400a9884) ran a first loop whose output its second loop overwrites -
  replaced by its only lasting effect, the gains' 32 steps (kick_mix,
  bit-exact). The Kick's click (0x400a9daa) runs its ramp in registers and,
  once the ramp is over, outputs zeros and skips its two filters when they
  have rung out below the idle-silence level (kick_click; the truncating MAC
  otherwise leaves them stuck just off zero for the whole note). Its final
  sum is a tighter loop (kick_sum, bit-exact). The Chord's oscillator
  (0x400a8722) runs our own loop from its setup on (chord_osc): no
  phase-modulation work (Chord never sets it), state in registers, and one
  wavetable when the waveform control sits on a table (Chord 11.2% -> 10.2%)
- The send effects cost less: their per-block setup (0x4005802e) runs
  before the voice loop, so the delay's DMA read (eDMA channel 30) happens
  while the voices render instead of being spun on in the output stage; and
  after 10.9 s (one turn of the delay's ring) with no track sounding and
  both effects silent, delay and reverb are skipped entirely - frozen, their
  outputs silence - until the next sound, from which they carry on as if
  paused. Idle: the output stage fell from ~24% to ~13% of the CPU
- Silent tracks cost less: a stock track with no note sounding and no
  pulse this block skips its parameter function (it runs on the trigger
  block), and an idle Sampler track skips its per-voice update and render
  outright (Kick 1.5%, Snare 1.1% of every block while silent)
- Lo-fi, Tape and Vinyl run once per 48 kHz sample pair of the 2x buffer
  (Tone's pole, Vinyl's click rate/decay and hiss level adjusted to match)
- Pages we draw ourselves (System, retrig, the Start/End waveform) account
  for the screen's y running from the bottom

It also folds in three tweaks from
[drumkilla/elektron-model-tweaks](https://github.com/drumkilla/elektron-model-tweaks)
(MIT): latching track mute, trig preview, and scrolling long names in the
browser. The latching mute is changed here: pad presses in mute mode are only
queued (shown on the LEDs), and the mutes all take effect together when FUNC
closes the mode. See `tweaks/README.md`.

Along the way it also fixes a long-standing stock bug: a random exception while
browsing, caused by the filesystem block cache.

## Self-checks the build performs

It refuses to produce an image if any of these fail:

- every Phase 1 entry point lands at the address the stock-area patches expect
- every stock patch site still contain the exact stock bytes
- every base->blob reference resolve against the ELF
- stack frames balance; the render step fraction survives the fill loop
- the fill loop and the filter address the same `sampler_buf` window
- the six machine-page parameter ids map to distinct, non-dial-bound slots
- `reserved_end` is 16-byte aligned and the blob fits the reserved cache block

## Constraints that are not obvious

- **Nothing of ours may live below `0x401ab750`.** Everything from `0x4019b590`
  up to there is the firmware's own: load-time data copied to SRAM at boot and
  then reused as scratch - including a 16 KiB buffer at `0x401a7750..0x401ab750`
  that the filesystem copies to disk to blank every newly allocated chunk,
  relying on it being zero. Our code lives only in retired filesystem cache
  blocks, from `0x401aba40`, as one linked blob.
  (This used to read "blob B must stay at 0x401aba40". That was the symptom,
  not the rule: samplerCO moved blob B down into that region and lost its
  state, and the original blob A sat inside the zero buffer in every build up
  to samplerEF.)
- **The boot clear must cover `0x4019b590..0x423380b0`, skipping only our own
  code** - which is what stock does at `0x400004b2`. A former "holepunch" patch
  started it after our blob instead, leaving everything below it uncleared. The
  build now checks the *built* hook for the right bounds, and that the zero
  buffer holds none of our bytes.
- **`src/track_table.s` must be linked in**: `log_trampoline`
  jumps into it and it continues to `0x4001407a`. The table it writes is
  write-only - nothing in the image reads it - despite what this file used to
  say about the sequencer ISR.
