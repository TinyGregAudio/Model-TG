# Model-TG user guide

Everything Model-TG adds to the Model:Cycles, and how to play it. To install,
see [BUILD.md](BUILD.md).

Button names are in **BOLD CAPS**; "hold A + B" means hold A and press B.

Model-TG's own pages open with **SETTINGS** held, so the stock **TRACK**
combinations keep working. Tapping **SETTINGS** on its own still opens the
Config Menu. Holding it no longer brings up the *Save pattern* prompt.
The twelve parameter knobs are numbered 1 to 12.

**Contents**

- [The Sampler machine](#the-sampler-machine)
- [Loading samples](#loading-samples)
- [The Sampler's parameters](#the-samplers-parameters)
- [Playback modes](#playback-modes)
- [Mode options](#mode-options)
- [Slice mode and the slice editor](#slice-mode-and-the-slice-editor)
- [Resampling](#resampling)
- [Stereo](#stereo)
- [Retrig and master FX](#retrig-and-master-fx)
- [Additions for every machine](#additions-for-every-machine)
- [Slide trigs](#slide-trigs)
- [Scale Lock](#scale-lock)
- [Uploading samples with Elektron Transfer](#uploading-samples-with-elektron-transfer)
- [The System page](#the-system-page)
- [Tweaks from elektron-model-tweaks](#tweaks-from-elektron-model-tweaks)
- [Files Model-TG writes](#files-model-tg-writes)
- [Button reference](#button-reference)

---

## The Sampler machine

Model-TG adds a seventh machine, **Sampler**, next to Kick, Snare, Metal,
Perc, Tone and Chord. Choose it for any track the way you choose any machine.

Samples are 48 kHz. Up to 64 samples can be in memory at once, shared between
tracks and patterns that use the same file.

## Loading samples

- **Assign a sample:** with a Sampler track selected, open the preset
  browser (**PRESET**) and pick a sample file. The popup says *Sample loaded
  to Sampler*. If the track isn't a Sampler, it says *Select sample machine
  first!*
-
- **Preloading.** Every sample the project uses loads in the background, so
  pattern changes don't wait for loading. If memory runs short, samples the
  current pattern doesn't need are dropped first (and reload when needed).
- **Sample locks:** hold a step, press **PRESET** and open a sample file. That
  step plays that sample. A lock keeps the Start, End and Filter it was locked
  with.
- **The sample's name** shows on the machine page in place of "Sample",
  scrolling when it is long.

## The Sampler's parameters

- **Start** and **End** set the part of the sample that plays. **Set Start
  above End to play it reversed.** Both can be p-locked, so reverse works per
  trig.
- **Fine Start/End:** a slow turn moves an eighth of a step; faster turns move
  in whole steps.
- **Waveform view:** turning Start or End shows the sample full screen, with
  the current Start and End as lines. With a step held, it shows the sample
  that step plays (including a sample lock).
- **Filter** and **Resonance:** a 4-pole ladder low-pass.
- All six parameters are LFO destinations.

## Playback modes

Hold **SETTINGS** + **PRESET** to open the mode menu, turn any knob to choose,
and press **SETTINGS**, **PRESET** or return to close it. The mode is saved per
track.

| mode | what it does | the four page knobs |
|---|---|---|
| **One shot** | plays Start → End once (the default) | Start, End, Filter, Res |
| **Loop** | loops Start → End | Start, End, Filter, Res |
| **Slice** | cuts the sample into slices; the note picks one ([details](#slice-mode-and-the-slice-editor)) | Start, End (inside the slice), Filter, Res |
| **Granular** | up to 6 grains at the note's pitch | Position, Grain Size (10 ms–1 s), Density, Spray |
| **Stretch** | granular with a moving playhead: time and pitch are independent | Speed (0 frozen, 96 original, 127 ≈3.8×), Grain Size, Density, Spray |
| **Pluck** | a plucked string (Karplus-Strong) struck by a burst of the sample | Strike Pos, Strike Len (1 ms–1 s), Tone, Feedback |
| **Wave** | the sample as a wavetable of single-cycle frames | Wave Pos, Frame Size (32–4096; 2048 for Serum/Vital tables), Smooth, Detune |

## Mode options

Hold **SETTINGS** + **PUNCH** for the current mode's settings. Turn **DATA**
to move between rows, press it to edit a row, turn to change it, and press
**SETTINGS** or return to close. Everything is saved with the project.
**EFX**, **CHN** and **STU** belong to the track, so they carry over when you
change mode.

| mode | options |
|---|---|
| One shot | **EFX** Filter / Lo-fi / Tape / Vinyl / None · **CHN** Mono / Stereo · **STU** stutter off, 1/4, 1/8, 1/16, 1/32, 8T, 16T |
| Loop | **TYP** Forward / Reverse / Ping-pong · **XFD** crossfade off, 10, 25, 50, 100, 250 ms · **SYN** off, 1, 2 or 4 bars (the loop lasts exactly that) · **EFX** · **CHN** |
| Slice | **MOD** EQL / TRN / MAN · **SLC** 8, 16, 32 · **EFX** · **CHN** · **EDT** · **SEQ** |
| Granular | **SHP** Hann / Triangle / Perc / Square · **DIR** Forward / Reverse / Random · **FRZ** freeze Position at the note's start · **CHN** |
| Stretch | **MOD** Forward, Reverse, once Forward/Reverse, Sync 1/2/4 bars (at Speed 96 the sample lasts exactly that) · **CHN** |
| Pluck | **MOD** Synth / Drum · **EXC** exciter Sample / Noise / Click · **CHN** |
| Wave | **CHN** |

With **EFX** set to Lo-fi, Tape or Vinyl, the Filter and Res knobs become
that effect's two controls: Lo-fi is Rate (48 kHz to ~1 kHz) and Crush (16
bits to 1); Tape is wow/flutter and saturation; Vinyl is crackle, hiss and
wow. **CHN** Stereo plays stereo samples in stereo and costs about twice the
CPU.

## Slice mode and the slice editor

In Slice mode the note chooses the slice. In keyboard mode the trig keys play
consecutive slices (the first key is slice 1), and each sequencer trig plays
the slice its note picks. Slices play at their original speed; Start and End
trim inside the slice, and Start above End reverses it.

**MOD** chooses how the sample is cut:

- **EQL:** equal slices (**SLC** 8, 16 or 32).
- **TRN:** at transients, the strongest hits, each moved back to its attack.
- **MAN:** your own markers, up to 32 (**SLC** then shows how many there are).
  Switching to MAN keeps the slices you had, ready to edit.

### The slice editor (EDT)

Press **EDT** in the Slice options. The track switches to MAN if it isn't
already, and a full-screen editor opens: the sample, every marker as a
dotted line, the selected slice's start as a solid line with a bar along the
slice, and *SLICE n/total* with its start time.

| control | what it does |
|---|---|
| trig keys 1–16 | play and select slices 1–16 (hold **FUNC** for 17–32) |
| **DATA** turn | select a slice |
| knob 1 | move the selected slice's start (coarse; faster turns go further) |
| knob 2 | move it fine |
| **FUNC** + knob 1 or 2 | move, then snap to the next zero crossing |
| knob 3 | zoom in and out around the selected start |
| **DATA** press | split the selected slice in two |
| **FUNC** + **DATA** press | remove the selected slice's marker (it joins the one before) |
| return, **SETTINGS** or **PRESET** | close |

Slice 1 always starts at the sample's start, and slices are at least 64
samples long.

### Tap slicing

In the editor, press **PUNCH** to arm tapping (the top right shows
*ARMED*). Nothing plays until you press a trig key: the first press plays the
whole sample from the start, at full level whatever the Amp Decay, and clears
the old markers. **Each press after that drops a marker** where the sample is
playing, and the playhead moves across the screen. Tapping stops at the end of
the sample, or when you press **PUNCH** again. Then fine-tune with the
knobs.

### Sequencing the slices (SEQ)

Put trigs on the track, then press **SEQ** in the Slice options. Each trig's
note is set so the pattern walks through the sample: the first trig plays
slice 1, the next slice 2, and so on, starting again after the last slice. It
works in all three MOD settings.

### Where markers are kept

Markers belong to the **sample**, not the project: every track and pattern
using that sample gets the same slices. They are saved in the Cycles' internal storage as
`/Slices/<the sample's id>` when you close the editor.

## Resampling

Hold **SETTINGS** + **RECORD** for the Resample menu. The take becomes the
sample of the track you opened the menu on.

| row | settings |
|---|---|
| **SRC** | a track (dry: after its envelope and filter, before its level, pan and sends), **MST** the whole output, or **USB** the computer's audio |
| **CHN** | **STE** stereo, **MON** mono |
| **LEN** | 1, 2, 4, 8 or 16 bars, **PTN** the pattern's length, or **MAN** until you stop |
| **STA** | **PAT** at step 1 of the pattern, **NOW**, or **SND** at the source's first sound |
| **MUT** | **ON** mutes the other tracks as the take lands |
| **TRM** | level trim, −6 to +6 dB |
| **CLR** | empty this track in this pattern |
| **REC** | arm, and stop or cancel |
| **SAV** | name the take and save it as `/Resampled/<name>` |

A bar-length take hands over seamlessly: it goes onto the track as the bar
ends. Takes play back at the level they were heard. An unsaved take lives in
memory only and belongs to the pattern it was recorded in. Saving runs while
the music plays.

## Stereo

Stereo takes and stereo WAVs (see [Transfer](#uploading-samples-with-elektron-transfer))
are kept as stereo. With **CHN** Stereo, every mode plays them in stereo,
effects included; with Mono (the default) they play mono. A stereo file whose
channels are the same is kept as mono. Note that stereo play is very CPU intensive so use it sparingly.

## Retrig and master FX

Hold **SETTINGS** + **RETRIG** for the retrig page.

- **Repeats:** hold a trig key to repeat the output: key 1 is 1/64 and key 16
  is a bar, with straight and triplet divisions between. Repeats lock to the
  tempo grid.
- **Pads** choose which tracks are repeated (all lit at first).
- **RETRIG** row: **Momentary** (while held; the newest held key wins) or
  **Latch** (a press starts or switches, the same key again stops).
- **FX RETURNS** row: whether the delay and reverb returns repeat too.
- Turn **DATA** to move between the rows and press it to change one.
- Return on this page **resets** the master FX and a latched repeat.
  **SETTINGS** or **RETRIG** closes the page; **PATTERN** closes it so you can
  choose a pattern.

### Master FX (the knobs on the retrig page)

Effects on the whole mix of the lit tracks, before the delay and reverb sends.
Each is off at 0, and the bottom line shows a knob's value as you turn it.

| knob | effect |
|---|---|
| 1 | **Drive:** soft clipping up to 8×, level-compensated |
| 2 | **Crush:** 16 bits down to 1 |
| 3 | **Rate:** sample-rate reduction, 48 kHz to 1 kHz |
| 4 | **Pump:** ducking, keyed by the tracks whose pads are **off**; with none off, on every quarter note |
| 5 | **Filter:** left of centre low-pass, right of centre high-pass |
| 6 | **Resonance** |
| 7 | **Ring mod:** 30 Hz to 4 kHz |
| 8 | **Noise riser:** white noise rising through a high-pass, on the output |
| 9 | **Gate:** off, 1/4, 1/8, 1/8T, 1/16, 1/16T, 1/32 on the tempo grid |
| 10 | **Tape stop** |
| 11 | **Vinyl:** hiss and crackle, on the output |
| 12 | **Flanger:** swept once a bar |

The master FX stay on after you close the page, and through pattern changes.
**SETTINGS** + return from anywhere turns them all off (*Master FX off*).

## Additions for every machine

- **Attack:** hold **PRESET** and turn **Decay**. From instant up to ~2 s.
- **Filter and Resonance** on the five stock machines: hold **PRESET** and
  turn **Sweep** (Filter) or **Contour** (Resonance). It's the Sampler's
  ladder filter; wide open it is bypassed.
- All three are real parameters: they can be p-locked, are LFO destinations,
  and are saved.
- **Mute** (**FUNC** + pad) on a Sampler track fades it out and ends its note.
- **Lower CPU:** silent tracks cost almost nothing, the Kick and Chord
  machines are cheaper, and delay and reverb switch off while nothing is
  sounding.

## Slide trigs

A slide trig glides into its values instead of jumping to them. Every
parameter that differs between the trig before it and the slide trig moves
smoothly from one to the other over the whole gap, and arrives as the slide
trig plays. A value is the step's p-lock, or the sound's own where the step
has none.

- Hold **SETTINGS** and press a trig key to make that step a slide trig, or to
  turn its slide off again (*Slide on* / *Slide off*). On an empty step it
  places a trig, already a slide trig.
- Slide trigs **double-blink** on the step keys.
- It works on every machine, and the trig before can be trigless: a trigless
  trig with locks followed by a slide trig glides between the two.
- What glides: the machine's parameters (Pitch, Color, Shape, Sweep, Contour
  and the rest), fine tune, Amp Decay, Volume, the delay and reverb sends,
  Pan, LFO speed, fade, start phase and depth, and Model-TG's Attack, Filter
  and Resonance. Switches and choices jump as usual: the machine, Gate, and
  the LFO's multiplier, destination, waveform and trig mode.
- The slide's speed follows the tempo and the track's speed. Across swung
  steps it can arrive a little early or late; it then holds until the slide
  trig plays.
- The mark is saved with the pattern and copied with its step. A step whose
  trig is removed loses it.

## Scale Lock

Two items in the **Scale menu** (**FUNC** + **PAGE**): **Scl** (the scale)
and **Key**. Notes you
play are moved onto the scale. Slice tracks are left alone, so consecutive
keys stay consecutive slices.

## Uploading samples with Elektron Transfer

Transfer normally treats the Cycles as a device without samples. In **Device
Config > Transfer**, switch the identity from **CYC** to **SMP**, no need to
reconnect Transfer: the Cycles now answers as a Model:Samples, and you can
upload samples, including stereo WAVs. Every power-on starts at CYC.

**In SMP, use Transfer for samples only, and never accept an OS update from
it.**

## The System page

**Device Config > System** shows the audio CPU load (now and at its worst)
and sample memory used and free. Turn **DATA** right for each track's share
of the CPU. Return, **PRESET** or **SETTINGS** closes it.

## Tweaks from elektron-model-tweaks

Three tweaks from
[drumkilla/elektron-model-tweaks](https://github.com/drumkilla/elektron-model-tweaks)
are included (build with `--no-tweaks` to leave them out):

- **Latching mute:** hold **TRACK** and tap **FUNC**; mute mode stays on until
  you tap **FUNC** alone. Pad presses are queued and all take effect when you
  leave mute mode.
- **Trig preview:** with the sequencer stopped, hold a step and press
  **PAGE** to hear it, with its note, p-locks and sound lock.
- **Browser scroll:** long names scroll in the browser.

## Files Model-TG writes

| where | what |
|---|---|
| `/Resampled/<name>` | takes saved with **SAV** |
| `/Slices/<id>` | manual slice markers, one small file per sample |

## Button reference

| where | buttons | does |
|---|---|---|
| anywhere | **SETTINGS** + **PRESET** | playback mode menu (Sampler track) |
| anywhere | **SETTINGS** + **PUNCH** | the mode's options |
| anywhere | **SETTINGS** + **RECORD** | Resample menu |
| anywhere | **SETTINGS** + **RETRIG** | retrig page and master FX |
| anywhere | **SETTINGS** + return | master FX off |
| anywhere | **PRESET** + Decay / Sweep / Contour | Attack / Filter / Resonance |
| grid | **SETTINGS** + trig key | slide trig on / off |
| browser | pick a sample file | load it onto the Sampler track |
| step held | **PRESET**, pick a sample | sample lock |
| slice editor | **PUNCH** | arm or stop tap slicing |
