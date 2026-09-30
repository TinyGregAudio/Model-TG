| Model-TG - src/model_tg.s
| The bulk of Model-TG for the Elektron Model:Cycles, OS 1.13: the Sampler
| machine and its seven playback modes, the slice editor, resampling, the
| retrig page and master FX, the extra parameters on the stock machines,
| Scale Lock, the Transfer identity, the System page and the CPU savings.
| Linked by build.py into one blob at 0x401ab750, ahead of phase1.s and
| track_table.s. MIT licensed - see LICENSE. docs/INTERNALS.md explains the
| layout; docs/USER_GUIDE.md what each part does for a player.
|
| The notes below the line are the development history, kept because they
| record what was verified on hardware and why things are the way they are.
| ----------------------------------------------------------------------------
| sampler_voice62.s - descriptor source corrected, Resonance on a numeric param.
| MY BUG: the Sampler descriptor was copied from slot 5 (0x40a716bc), which is
| machine 4 = TONE, while the parameter objects resolve to machine 5 = CHORD
| (0x400097f0 clamps machine 6 -> 5). Descriptor and object described different
| machines. Now copied from slot 6 (0x40a71708) = Chord, matching the object.
| Resonance moved off Pan (0x1c), which formats as L/R, onto Reverb Send
| (0x47, Chord Color): a machine-page slot, not bound to any fixed dial.
|
| sampler_voice61 - Resonance restored, and the base's SysEx loggers disabled.
| The track-4 recording bug survives with NO parameter page, so it is not ours.
| diaglog62 is a DIAGNOSTIC base: 0x4000ba7a and 0x400a21a4 are spliced to pure
| SysEx loggers, and 0x400a21a4 sits in the AUDIO region - it transmits on every
| call (capture logs run to 4-6 MB). That traffic is the likely cause of the
| recording misbehaviour. Each hook replays its overwritten prologue, so the
| stock bytes are recoverable from the hook itself and the splices are restored.
| Resonance now uses Pan's id (0x1c, slot 0x16 - not pitch-related), renamed for
| the Sampler page only, so other machines still show Pan.
|
| sampler_voice60 - Resonance placeholder removed (it was FINE TUNE).
| 0x2b is named 'Pitch' / 'FTUN' in the table - a fine-tune PITCH parameter.
| Using it as a placeholder pinned the pitch directly, which is why the lock
| survived the slot-0xb fix. Replaced with Delay Send (0x1a), which touches
| nothing pitch-related.
| The page therefore carries three Sampler controls for now: Start/End/Filter.
|
| sampler_voice59 - conventional order, and slot 0xb avoided.
| Two fixes:
|  1. ORDER: stock machines are Pitch, Amp Decay, then the four machine params.
|     Restored; Track Level dropped (every track already has a level).
|  2. PITCH LOCK: 0x400aa812 reads a3@(22) (slot 0xb) through 0x400a9ca8 into
|     voice+80, an oscillator pitch field that the voice reset seeds with
|     0x04000000. A page that writes +22 therefore pins the pitch when a
|     machine change applies defaults - which is exactly why the lock appeared
|     only once the Sampler had a page, and why pitchheal was clean.
|     So NO Sampler parameter uses slot 0xb. Start/End/Filter take slots
|     0xc/0xd/0xe -> track struct +24/+26/+28.
|
| sampler_voice58 - custom names, and NO Pitch parameter on the page.
| The common Pitch id 0x2a pins the pitch and disables note tracking (observed
| on hardware early on). Having it on the Sampler page meant that building the
| page re-applied it, so switching away and back locked the pitch again.
| The page now carries only the four Sampler controls plus Amp Decay and Track
| Level; chromatic pitch comes from note tracking via voice+232, untouched.
|
| sampler_voice57 - custom names WITHOUT renaming other machines.
| The name lives in param_table[id] and is global to the id, so a static
| rename also relabels Chord and Perc. Instead we swap the name/category/short
| pointers at RUNTIME in descr_hook, which receives the descriptor index and
| therefore knows which machine's page is being built (the page passes
| machine+1, so 7 == Sampler - verified in the caller log).
|   index 7  -> install Sampler labels
|   anything else -> restore the stock labels
| The page is rebuilt on machine change, so the labels follow the selection.
|
| sampler_voice55.s - custom parameter NAMES via Chord's parameter object.
| Verified: 0x400097f0 clamps the machine index to 5, so a Sampler track
| (machine 6) already resolves to CHORD's parameter object, which is real and
| fully constructed. Chord's ids therefore work on the Sampler page, and the
| label comes from param_table[id] - so renaming them gives custom names with
| working values, with no structural change.
| Avoids relocating array B (this+96, 6 x 68) which cannot grow in place:
| a 7th entry (+504..+572) would overlap live fields at this+552.
| COST: Chord's page shows the same labels.
|
| sampler_voice45.s - Sampler page built from STOCK parameter ids only.
| Repurposed ids never worked: a param is not just a table entry plus a
| 100-byte record - it is constructed AND registered at boot. A byte copy
| (even with self-pointers rebased) yields an object that renders but is not
| registered, so the write path cannot find it and the value never moves.
| Stock ids work immediately (Pitch 0x2a and Decay 0x18 both did), so the page
| now uses Tone's six ids. They are fully functional and write to the track
| struct fields sampler_render already reads.
| COST: the names are Tone's. Custom labels need either real construction or a
| display-time substitution - a separate job, and not a blocker for the audio.
|   0x2a Pitch        -> NOTE: pins pitch, disables note tracking when moved
|   0x18 Amp Decay
|   0x42 Tone Color   -> intended Sample Start  (track struct +22)
|   0x43 Tone Shape   -> intended Sample End    (+24)
|   0x44 Tone Sweep   -> intended Filter        (+26)
|   0x45 Tone Contour -> intended Resonance     (+28)
|
| sampler_voice38.s = working build + Sampler ADDED TO THE PARAMETER PAGE LIST.
| Static trace, end to end:
|   0x4001bc18 constructs ParameterPageView (name string at 0x401266fc)
|   ctor 0x4001ecd6 sets vptr 0x4010052c and copies a vector into this+104
|   that vector is built at 0x4001bbd0..0x4001bbf4:
|       pea 0x18            allocate 24 bytes
|       pea 0x18 / pea 0x400ffc7c / jsr 0x4008f1f0   memcpy 24 bytes
|       addil #24,%d6       end pointer
|   and 0x400ffc7c holds { 1, 2, 3, 4, 5, 6 } - SIX longs.
| Those are machine+1 (same convention as `pea %a4@(1)` at 0x400140c4), so
| Kick->1 .. Chord->6. **Sampler (machine 6) would be 7, which is not in the
| list.** The page therefore has no entry for it: the lookup returns 0, and
| nothing is drawn. That is the root cause - every earlier fix was downstream
| of a machine that was never in the list to begin with.
| Fix: point the copy at our own 7-entry list { 1..7 } and widen the three
| sizes. All four are small immediates, patchable in place.
| Also retains the descriptor slot-6 copy, so index 7 -> descriptor slot 6
| resolves to real parameter data.
|
| sampler_voice34.s = working build + POPULATE descriptor slot 6.
| User confirms: on a Sampler track a dial turn shows NO parameter name or
| value on screen at all - the encoder input is discarded entirely. So there
| is no page, and the three previous index fixes were correcting lookups that
| are never consulted.
| The alias's own bound check is `moveq #6,%d1; cmpl %d0,%d1; bccs`, i.e. it
| permits 0..6 - the descriptor table at 0x40a71540 has SEVEN 76-byte slots.
| Phase 1 made machine 6 selectable but never populated slot 6, so it reads
| as an empty descriptor: zero parameters, encoders ignored.
| Fix: copy Tone's descriptor (slot 4) into slot 6, once. This is
| index-source-agnostic - every lookup path resolves to a real descriptor, so
| it does not matter which of them the encoder handler uses.
|   src = 0x40a71540 + 4*76 = 0x40a71670
|   dst = 0x40a71540 + 6*76 = 0x40a71708
| Guarded: skipped while the source still reads zero (table not yet built at
| boot), and done only once.
|
| sampler_voice29.s = working build + Sampler PARAMETER PAGE.
| Measured: on a Tone track each of the 6 dials writes exactly one offset
| (+21, +36, +22, +24, +26, +28); on a Sampler track all 6 dials write
| NOTHING. Machine 6 has no parameter page, which is why no memory hunt found
| the values - the encoders were never writing.
| Phase 1's aliases map machine 6 -> 0 (Kick) for the per-machine descriptor
| lookups (0x401aa544 for 0x401091b4, 0x401aa520 for 0x40a71540 + idx*76).
| Retarget both to Tone (4/5): Tone's page writes +22/+24/+26/+28/+36, which
| is exactly what 0x400aa7b8 - the param fn our render already calls - reads.
| So the dials become live for the Sampler with no new UI code.
| Also carries the stale-machine-index heal (see pitchheal).
|
| sampler_voice23.s - PITCH FROM voice+232 + robust Sampler detection.
| a2@(18) alone is not enough: the audio-side struct is only refreshed on
| assign, and it has been observed holding 5 (renderprobe) as well as 6 (the
| all-track snapshot). When it goes stale after a machine switch the render
| takes the non-Sampler path, the previous machine renders, and the blend
| returns. sampler_track_table is the complement: accurate after any assign
| (diaglog62's assign hook still maintains it) but empty at boot. Accept a
| Sampler track if EITHER says so - a2@(18) covers cold boot, the table covers
| machine switching. The table is rewritten on every assign (1 only when the
| machine is 6, 0 otherwise), so it cannot go stale in the false-positive
| direction.
| Tone-track voice diff across two p-locked steps (C5 vs F#4):
|   voice+232: 0x0000B28E (45710) vs 0x00007E47 (32327)
|   ratio 1.41400 vs a true tritone 1.414214 -> 0.01%. That is the pitch,
|   as a frequency-proportional value.
| (voice+112..123 is a 64-bit timestamp - it always differs; ignore it.)
| Read AFTER 0x400aa7b8 runs, so the value is current for this block, and
| converted to a Q16.16 resample step:
|   step = ((v>>4) * 93957) >> 12       (v == 45710 -> 65512, 0.6 cents flat)
| 45710 is the reference for the note it was captured at, so if the result is
| transposed it will be by a whole octave and the constant is the only thing
| that needs moving. Falls back to 1.0 if the field reads 0.
|
| sampler_voice19.s - two findings from the all-track snapshot:
|  1. a2@(18) reads 6 for a Sampler track (Tone reads 4). The track struct
|     carries the real machine index, so the render can identify a Sampler
|     track natively. This REMOVES the need for sampler_track_table,
|     refresh_flags, 0x400cf866 and every vtable dispatch - i.e. the cause of
|     the cold-boot bug AND both exception builds. Trigger hooks deleted.
|  2. a2@(38) reads 0x3c = 60 on both tracks - a MIDI note number living in
|     the track struct. Used as the pitch source, latched at the trigger edge.
| Now only THREE patches, none of them on the allocator or UI threads.
|
| sampler_voice2.s - fixes the three symptoms reported on samplervoice:
|   (1) sound still varies with the previously played machine
|   (2) sample fires on note OFF instead of note ON
|   (3) after power-on with Sampler already selected there is no sound
|       until you scroll off the machine and back
|
| ROOT CAUSE OF (1) AND (2) - the a3@ gate: at 0x400a7dac the stock code
| tests a3@ and, when it is clear, branches past both the machine-index read
| and the voice reset; at 0x400a7dee d4 is then reloaded from voice@(0)
| regardless. a3@ holds the PREVIOUS block's trigger flag (copied from a5@
| at 0x400a7e24).
| On the block where a note actually starts a3@ is still 0, so the routing
| was skipped and d4 fell back to voice@(0) = the previous machine. The first
| block of every Sampler note was rendered by whatever machine was played
| before, and the voice reset landed one block late -> the residual blend.
| Note that d4 is reloaded from voice@(0) at 0x400a7dee regardless, so the
| value that actually matters is voice@(0), not d4.
|
| Fix: decide BEFORE the gate, every block, and write voice@(0) = 6 directly.
| Splice 0x400a7da8 (movel %d1,%fp@(60) + tstl %a3@ + beqs = 8 B).
|
| (2) also had a second cause: the phase reset was hooked at 0x4008145e,
| which is evidently the note-OFF leg of the live-pad path. The render loop
| already carries the authoritative per-track trigger flag in %a5@
| (0x400a7da2: movel %d1,%a5@, from the d5 bitmask argument), so the one-shot
| now restarts on the a5@ edge (a5@ != 0 && a3@ == 0). That signal is the
| render loop's own, so it works for live pads, sequencer and MIDI alike.
|
| (3) sampler_track_table is only written on machine-assign, so after a cold
| boot it is all zeros and a Sampler track routes as Chord. Both live-trigger
| entries now refresh the whole table from the authoritative source used by
| the existing assign hook: trackObj = 0x400cf866() + 212 + trackIdx*68, then
| a virtual call through vtable+40, machine index at +38 of the result.
| 0x400cf866 is a lazy singleton getter, so this is done on the trigger path
| (a normal thread), never from the audio render.
|
| PATCHES (on diaglog62; 0x400a7dc2 is left STOCK this time - the old route
| hook there is obsolete because Sampler tracks now bypass the remap):
|  1. 0x400a7da8 (8 B)  -> jmp sampler_pre + nop
|  2. 0x400a7df4 7005   -> 7006            (widen dispatch guard to d4<=6)
|  3. 0x400a7e02 (30 B) -> jmp sampler_dispatch + 12 nops

    .text

| The stock parameter table lives at 0x4010dce0, inside the image and well
| clear of the filesystem cache. An earlier generation carried a 4,256-byte
| copy here and re-pointed ~30 base sites at it - to change ONE byte (entry 41,
| offset 14, 0x05 -> 0x06). The build script now reverts those sites and patches
| that byte in place, so the copy is gone and only our labels remain.
    param_table = 0x4010dce0
    .include "sampler_strings.inc"
    .include "name_swap.inc"
    .include "note_ratio.inc"

| private 2x oversample buffer: [0..7] history (written by 0x400a9f58),
| [8..71] our 64 input samples. 288 B used; 320 reserved. Private so no
| other machine can leave data in the window - 0x8000c05c is Tone's.

| Per track: {integer sample index, Q0.32 fraction}.
| A single Q16.16 accumulator could only address 65,536 samples - it wrapped and
| replayed the sample from the start, which is exactly what was heard with a
| long decay. Splitting it gives a full 32-bit index while KEEPING 32 bits of
| fractional precision (better than the 16 bits it had before).
    .balign 4
phase_table:
    .long 0,0, 0,0, 0,0, 0,0, 0,0, 0,0, 0,0

descr_done:
    .byte 0
    .align 2

sampler_descr:
    .space 76
    .align 2
sampler_descr_atk:
    .space 76
    .align 2
other_descr:                      | a stock machine's descriptor, with
    .space 76                     | Attack swapped in while Track is held
    .align 2



| machine+1 list for ParameterPageView, now including the Sampler (7)
page_machine_list:
    .long 1,2,3,4,5,6,7

    .align 2
| Geometric midpoints between adjacent semitones around 45710 (1.0x),
| covering -24..+23 semitones. Counting entries <= the pitch yields the
| semitone offset, with no logarithm and no division.
pitch_thr:
    .long 11762, 12462, 13203, 13988, 14820, 15701
    .long 16634, 17624, 18672, 19782, 20958, 22204
    .long 23525, 24924, 26406, 27976, 29639, 31402
    .long 33269, 35247, 37343, 39564, 41916, 44409
    .long 47049, 49847, 52811, 55951, 59279, 62803
    .long 66538, 70494, 74686, 79127, 83833, 88817
    .long 94099, 99694, 105622, 111903, 118557, 125607
    .long 133076, 140989, 149373, 158255, 167665, 177635

slice_pending:                    | a trigger the render has yet to serve
    .byte 0,0,0,0,0,0,0,0
live_note:                        | last note played, per track; 52 = pad 1
    .byte 52,52,52,52,52,52,52,52

| ============ patch 1: pre-gate routing + trigger edge ============
| live: d1 (to be stored), d2=trackIdx, a2=trackData, a3/a5 per-track flags,
| fp=voice. a0 is dead here (reloaded at 0x400a7df0).
sampler_pre:
    movel   %d1,%fp@(60)          | replay overwritten instruction
    | ---- one-time: build the Sampler's OWN descriptor ----
    | Slot index is machine+1, so slot 5 = Tone (machine 4) and slot 6 = CHORD.
    | The earlier build copied into slot 6 and corrupted Chord's page. Instead we
    | build a private descriptor and hand it out for index 7 (see descr_hook).
    lea.l   descr_done,%a0
    tstb    %a0@
    bnes    dsc_skip
    movel   0x40a71708,%d1        | Chord's descriptor (slot 6) - matches the
                                  | object the params resolve to
    beqs    dsc_skip              | table not built yet - retry next block
    moveb   #1,%a0@
    lea.l   0x40a71708,%a0        | src: slot 6 = Chord
    lea.l   sampler_descr,%a1
    moveq   #18,%d1               | 19 longs = 76 bytes
dsc_cp:
    movel   %a0@+,%a1@+
    subql   #1,%d1
    bpls    dsc_cp
    | replace the six machine-page parameter IDs (descriptor+8 + n*4)
    lea.l   sampler_descr,%a0
    moveq   #0x2a,%d1
    movel   %d1,%a0@(8)           | Pitch      (stock, conventional slot 1)
    moveq   #0x4b,%d1
    movel   %d1,%a0@(12)          | Amp Decay  (stock, conventional slot 2)
                                  | Chord's per-machine Amp Decay, NOT the
                                  | common 0x18. The two entries are identical
                                  | except for long[10], and long[10] is what
                                  | the LFO destination list sorts on: 30 for
                                  | every machine's own duplicate, 70 for the
                                  | common one. With 0x18 here, Decay sorted
                                  | after the four machine params and appeared
                                  | 7th instead of 3rd. The id must match what
                                  | sampler_amp_gate hands back, because the
                                  | LED painter searches THIS array for it.
    moveq   #0x2e,%d1
    movel   %d1,%a0@(16)          | Sample Start (slot 0x10 -> +22)
    moveq   #0x3e,%d1
    movel   %d1,%a0@(20)          | Sample End   (slot 0x11 -> +24)
    moveq   #0x49,%d1
    movel   %d1,%a0@(24)          | Filter       (slot 0x12 -> +26)
    moveq   #0x4a,%d1
    movel   %d1,%a0@(28)          | Resonance (Kick Color id, slot 0x10)
    | A second copy with Attack where Amp Decay sits, handed out while the
    | modifier is
    | held. Two descriptors rather than editing one in place: the page, the LED
    | painter and the dial mapping all read it, and a descriptor that changes
    | under them mid-frame is the kind of thing that is painful to debug.
    lea.l   sampler_descr,%a0
    lea.l   sampler_descr_atk,%a1
    moveq   #18,%d1
dsc_cp2:
    movel   %a0@+,%a1@+
    subql   #1,%d1
    bpls    dsc_cp2
    lea.l   sampler_descr_atk,%a0
    moveq   #0x0d,%d1
    movel   %d1,%a0@(12)          | position 1: Attack, not Amp Decay
                                  | Third id tried here. param_table long[0] is
                                  | the MACHINE group and long[10] the position
                                  | on the page (40=Color 50=Shape 60=Sweep
                                  | 70=Contour), so the value renderer is chosen
                                  | per machine AND position - which is why
                                  | Chord Color drew chord names and Tone Color
                                  | was odd too. Contour cannot be used: every
                                  | Contour id is slot 0x13, which Filter holds,
                                  | and sharing a slot makes two dials move
                                  | together (the old Resonance/Reverb bug).
                                  | Slot 0x10 is the only free full-range slot,
                                  | so this is Kick's Color - a plain continuous
                                  | control on that machine.
                                  | Was Chord Color (0x47), which the UI renders
                                  | as chord names ("rootpos") rather than a
                                  | number. Tone Color is the same slot 0x10 and
                                  | the same trackData+22, so this is a drop-in
                                  | swap - only the display changes.
                                  | This was 0x1b (Reverb Send), which has
                                  | idx7 = 0x9d in param_table - i.e. it is bound
                                  | to a real dial (the 8th), so the two moved
                                  | together. The machine-page family is
                                  | slots 0x10..0x13 (Color/Shape/Sweep/Contour),
                                  | all with idx7 = ffffffff; Start/End/Filter
                                  | already use 0x11/0x12/0x13, so Resonance
                                  | takes 0x10. Its value lands at trackData+22.
    | NOTE: the common Pitch id 0x2a is deliberately NOT on this page - it pins
    | the pitch and disables note tracking.
dsc_skip:
    | sampler_track_table (0x401ab6f4) was a second opinion on whether this
    | track is a Sampler, used to "heal" a stale machine index. Nothing ever
    | writes it - it reads as zero in every build checked - so the heal never
    | fired and the track struct was always the only source. Gone.
    mvsb    %a2@(18),%d1          | machine index from the track struct
    lea.l   trk_mach,%a0          | published: amp_hook keys the take gain on it
    movel   %d1,%a0@(0,%d2:l:4)

    | Machine-change defaults are not handled here: this thread only sees a
    | track's machine when the track is TRIGGERED (the sound is copied into the
    | audio arrays at trig time, 0x400590ae). They are applied where the
    | firmware commits the change - see mc_commit_hook.
    | ---- attack state, maintained for every machine --------------------
    | The ramp itself is applied in amp_hook, which wraps 0x400a967a - the amp
    | envelope stage that all six machines call - so attack is not a Sampler
    | feature any more. All that is needed here is per-track state: which voice
    | belongs to which track, the ramp step, and a restart on the trigger edge.
    | d1 holds the machine index and must survive; d0/d4/a0 are free.
    lea.l   voice_ptr,%a0
    movel   %fp,%a0@(0,%d2:l:4)
    | Attack comes from trackData+46 (k=23), not from a private copy. The mirror
    | that fills this array is memcpy(audio + 66*track, soundObject + 20, 66) at
    | 0x40058a48 - 66 bytes is k=0..32, so k=23 was always carried. The k<=22
    | limit belongs to the SAVE format alone, which is why persistence needed
    | its own hooks. Reading the mirrored word also means an LFO aimed at ATK,
    | which writes this very word, actually modulates.
    mvzw    %a2@(46),%d0
    lea.l   atk_key,%a0           | the step only changes with the dial: the
    cmpl    %a0@(0,%d2:l:4),%d0   | divide runs then, not every block
    beqs    ap_trig
    movel   %d0,%a0@(0,%d2:l:4)
    tstl    %d0
    beqs    ap_none
    movel   %d0,%d4
    addl    %d0,%d0
    addl    %d4,%d0               | v*3 output samples: 2.03 s at full dial
    movel   #16777216,%d4
    divul   %d0,%d4               | Q24 step
    bnes    ap_set
    moveq   #1,%d4
ap_set:
    lea.l   atk_step,%a0
    movel   %d4,%a0@(0,%d2:l:4)
    bras    ap_trig
ap_none:
    lea.l   atk_step,%a0
    clrl    %a0@(0,%d2:l:4)
ap_trig:
    tstl    %a5@                  | triggered this block?
    beqs    ap_done
    tstl    %a3@                  | ...and not already triggered last block?
    bnes    ap_done
    lea.l   atk_gain,%a0
    clrl    %a0@(0,%d2:l:4)       | a new note restarts the attack
ap_done:
    jsr     gflt_coef             | Filter/Res for the stock machines (jsr:
                                  | a bsr.w wrapped once the blob passed 32 KiB
                                  | between the two - samplerGI's boot crash)
    cmpil   #6,%d1
    bnew    sp_not_sampler
sp_is_sampler:
    | ---- a take waiting for this track (rs_handoff): it lands on the next
    | trig, or as soon as the voice is silent - never under a sounding note,
    | whose sample would change beneath it. It starts from silence: the gain
    | ramp in amp_hook fades it in (gv_gain = 0), crossfading with MUT's fade.
    lea.l   track_pend,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmis    sp_np
    tstl    %a5@                  | triggered this block, and not last block
    beqs    sp_pidle
    tstl    %a3@
    beqs    sp_pgo
sp_pidle:
    lea.l   sv_idle,%a0           | the render found it silent
    tstb    %a0@(0,%d2:l)
    bnes    sp_pgo
    moveq   #5,%d4                | the amp envelope has finished
    cmpl    %fp@(0x298),%d4
    bnes    sp_np
    movel   %fp@(0x294),%d4
    cmpil   #SV_IDLE_ENV,%d4
    bgts    sp_np
sp_pgo:
    movel   %d0,%d4               | the slot is the low word (-1: silence);
    extl    %d0                   | PEND_NOFADE - a pattern's own sample, not
    lea.l   track_slot,%a0        | a take - lands without the fade-in
    movel   %d0,%a0@(0,%d2:l:4)
    moveq   #-1,%d0
    lea.l   track_pend,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    btst    #16,%d4
    bnes    sp_np
    lea.l   gv_gain,%a0
    clrl    %a0@(0,%d2:l:4)
sp_np:
    tstl    %a5@                  | a new note: a sound-locked step plays the
    beqs    sp_nlk                | sample its pool sound names (sp_lock)
    tstl    %a3@
    bnes    sp_nlk
    bsr     sp_lock
sp_nlk:
    | ---- an idle track (the render found it silent last block) with no new
    | note: nothing below can change what it plays, so none of it runs. A trig
    | runs it all, in this very block, before the render sees the note.
    lea.l   sv_idle,%a0
    tstb    %a0@(0,%d2:l)
    beqs    sp_full
    tstl    %a5@
    bnew    sp_full
    braw    sp_nt_x
sp_full:

    | ---- SAMPLE WINDOW: lo, length and direction, every block ------------
    | Start (trackData+22) and End (+24) scale to sample indices without a
    | divide:  idx = ((count >> 6) * value) >> 9,  value 0..32512 -> 0..99.2%.
    | (count>>6) keeps the product inside 32 bits for the longest sample we
    | allow (4 MiB / 2 = 2,097,152 samples -> 32767 * 32512 fits).
    |
    | REVERSE is simply Start > End. No mode flag and no extra parameter, and
    | it p-locks per trig for free because both dials already do. The render is
    | handed a window [lo, lo+span) plus a direction and tests membership with
    | ONE unsigned compare, (idx - lo) >= span, which reduces to the old test
    | when lo is 0 - so the forward path behaves exactly as it did.
    | Free here: d0, d1, d4, a0, a1. d3 is outBuf and d5-d7 are trigger masks.
    | Start and End are published FIRST, before the slice-mode skip below.
    | They used to be published further down, past that skip, so in slice mode
    | they were never written: on a project load they were still zero, the end
    | offset came out zero, the window collapsed to a single sample and the
    | slice was silent. Toggling the mode away and back ran this section and
    | filled them in, which is why that worked around it.
    mvsw    %a2@(22),%d0
    bges    sw_pub_s
    moveq   #0,%d0
sw_pub_s:
    mvsw    %a2@(24),%d1
    bges    sw_pub_e
    moveq   #0,%d1
sw_pub_e:
    lea.l   dial_start,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    lea.l   dial_end,%a1
    movel   %d1,%a1@(0,%d2:l:4)

    | Mode first: only LOOP wraps in the render, and SLICE owns its own window
    | (set at the trigger edge from the note), so this section must not touch it.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d2:l:4),%d0
    moveq   #0,%d1
    cmpil   #1,%d0
    bnes    sw_nowrap
    moveq   #1,%d1                | loop: 1 wraps, 2 ping-pongs, 3 crossfades
    lea.l   lp_type,%a1           | (3 is set below, once the window is known)
    movel   %a1@(0,%d2:l:4),%d4
    cmpil   #2,%d4
    bnes    sw_nowrap
    moveq   #2,%d1
sw_nowrap:
    lea.l   win_wrap,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    cmpil   #3,%d0
    beqw    sw_gran               | granular: grain parameters, no window
    cmpil   #4,%d0
    beqw    sw_gran               | stretch: the same, with Speed for Position
    cmpil   #5,%d0
    beqw    sw_pluck              | pluck: strike and string parameters
    cmpil   #6,%d0
    beqw    sw_wave               | wavetable: frames, morph and unison
    cmpil   #2,%d0
    beqw    sw_done               | slice mode owns its window; sampler_render
                                  | sets it, because only there is the pitch
                                  | current for this block
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    sw_none
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4   | d4 = sample length, in samples
    beqw    sw_none               | a zero-length sample would drive the reverse
                                  | branch's `hi = index + 1` to 0, leave hi == lo
                                  | and take the one-sample fallback below - i.e.
                                  | read PCM index 0 of a sample that has none
    mvsw    %a2@(22),%d0          | Start dial
    bges    sw_s_ok
    moveq   #0,%d0
sw_s_ok:
    mvsw    %a2@(24),%d1          | End dial
    bges    sw_e_ok
    moveq   #0,%d1
sw_e_ok:
    cmpl    %d1,%d0
    bhiw    sw_reverse            | Start > End -> play backwards

    | ---- forward: the window is [Start, End) -------------------------
    | lo was 0 here until loop mode existed, which made a loop wrap to the top
    | of the sample instead of back to Sample Start. One-shot is unaffected
    | either way: the phase is seeded at Start and only ever rises, so
    | (idx - Start) >= (End - Start) is the same test as idx >= End.
    movel   %d0,%sp@-             | park the Start dial
    tstl    %d1
    beqs    sw_f_full             | at or below minimum -> to the end
    cmpil   #32512,%d1
    bges    sw_f_full             | at maximum -> the lot. The scaling below
                                  | would otherwise stop at 99.2% of the sample.
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    cmpl    %d4,%d0
    bcss    sw_f_end              | beyond the sample -> full length
sw_f_full:
    movel   %d4,%d0
sw_f_end:
    movel   %sp@+,%d1             | Start dial back
    movel   %d0,%sp@-             | park the End index
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0                | d0 = Start index = lo
    lea.l   win_lo,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    movel   %sp@+,%d1             | End index
    subl    %d0,%d1               | span = End - Start
    bhis    sw_f_span
    moveq   #0,%d1                | Start at or past End -> silent, as before
sw_f_span:
    lea.l   win_span,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    lea.l   win_rev,%a1
    clrl    %a1@(0,%d2:l:4)
    braw    sw_done

    | ---- reverse: lo = End index, span = Start index + 1 - lo --------
sw_reverse:
    movel   %d1,%sp@-             | park the End dial
    movel   %d0,%d1               | Start dial
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0                | d0 = Start index
    cmpl    %d4,%d0
    bcss    sw_r_scap
    movel   %d4,%d0
    subql   #1,%d0                | never past the last sample
sw_r_scap:
    addql   #1,%d0                | one past it, so the seeded index is inside
    movel   %sp@+,%d1             | End dial back
    movel   %d0,%sp@-             | park the upper bound
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0                | d0 = End index = lo
    lea.l   win_lo,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    movel   %sp@+,%d1             | upper bound back
    subl    %d0,%d1               | span = hi - lo
    bhis    sw_r_span
    moveq   #1,%d1                | degenerate window -> one sample
sw_r_span:
    lea.l   win_span,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    moveq   #1,%d0
    lea.l   win_rev,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    braw    sw_done

    | ---- granular: the four dials are grain parameters ------------------
    | Start = Position, End = Size, Filter = Density, Res = Spray - the same
    | trackData words, so they persist, p-lock and take LFOs exactly as before.
    | Position and Spray use the window's divide-free scaling across the whole
    | sample; Size and Density go through tables (granular_tables.inc).
sw_gran:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    sw_g_none
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4   | d4 = sample length, in samples
    beqw    sw_g_none
    mvsw    %a2@(22),%d1          | Position (granular) / Speed (stretch)
    bges    sw_g_pos
    moveq   #0,%d1
sw_g_pos:
    lea.l   loop_mode,%a0
    moveq   #4,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    beqs    sw_g_speed
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    lea.l   gr_pos,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    bras    sw_g_spr0
sw_g_speed:
    | Stretch: the dial is the playhead's speed. gran_fill moves the playhead
    | and writes gr_pos from it, so gr_pos is not touched here.
    asrl    #8,%d1
    cmpil   #127,%d1
    bles    sw_g_sp1
    moveq   #127,%d1
sw_g_sp1:
    lea.l   gspeed_tab,%a0
    movel   %a0@(0,%d1:l:4),%d0   | Q16, 0 = frozen
    | Sync (options 4..6): at Speed 96 (1x) the playhead crosses the whole
    | sample in exactly 1/2/4 bars of the project tempo, so the dial scales
    | that: speed *= count / bars. Tempo is 0x40149310, in 1/120 BPM (what
    | 0x40058bf4 returns and the tap-tempo popup divides by 120); a bar at 48
    | kHz is 1,382,400,000 / that. (speed>>2)*(count>>6)/(bars>>8) keeps it in
    | 32 bits.
    lea.l   st_opt,%a1
    movel   %a1@(0,%d2:l:4),%d1
    subql   #4,%d1
    bmis    sw_g_sst
    movel   %d0,%sp@-
    movel   %d1,%sp@-
    movel   %d4,%sp@-             | sp: count, n, speed
    movel   0x40149310,%d1
    beqs    sw_g_sx
    movel   #1382400000,%d0
    divul   %d1,%d0               | one bar
    movel   %sp@(4),%d1
    lsll    %d1,%d0               | n bars
    lsrl    #8,%d0
    beqs    sw_g_sx
    movel   %sp@(8),%d1
    lsrl    #2,%d1
    lsrl    #6,%d4
    mulul   %d1,%d4
    divul   %d0,%d4
    movel   %d4,%sp@(8)
sw_g_sx:
    movel   %sp@+,%d4
    addql   #4,%sp
    movel   %sp@+,%d0
sw_g_sst:
    lea.l   gr_speed,%a1
    movel   %d0,%a1@(0,%d2:l:4)
sw_g_spr0:
    mvsw    %a2@(28),%d1          | Spray: a range, also across the whole sample
    bges    sw_g_spr
    moveq   #0,%d1
sw_g_spr:
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    lea.l   gr_spray,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(24),%d1          | Size
    bges    sw_g_sz0
    moveq   #0,%d1
sw_g_sz0:
    asrl    #8,%d1
    cmpil   #127,%d1
    bles    sw_g_sz1
    moveq   #127,%d1
sw_g_sz1:
    lea.l   gsize_tab,%a0
    movel   %a0@(0,%d1:l:4),%d0   | grain length, output samples
    lea.l   gr_len,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(26),%d1          | Density
    bges    sw_g_dn0
    moveq   #0,%d1
sw_g_dn0:
    asrl    #8,%d1
    cmpil   #127,%d1
    bles    sw_g_dn1
    moveq   #127,%d1
sw_g_dn1:
    lea.l   gdens_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d1   | spacing, Q8 multiple of the length
    mulul   %d1,%d0               | 48000 * 1024 at most: fits
    lsrl    #8,%d0
    bnes    sw_g_int
    moveq   #1,%d0                | never a zero spacing: the spawn loop steps by it
sw_g_int:
    lea.l   gr_int,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    braw    sw_done
sw_g_none:
    lea.l   gr_len,%a1            | no sample: a zero length spawns nothing
    clrl    %a1@(0,%d2:l:4)
    braw    sw_done

    | ---- pluck: Start = strike position, End = strike length, Filter = Tone,
    | Res = Feedback. Tables in granular_tables.inc.
sw_pluck:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    moveq   #0,%d4                | no sample: the other exciters still play
    tstl    %d0
    bmis    sw_p_nos
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4
sw_p_nos:
    mvsw    %a2@(22),%d1          | strike position
    bges    sw_p_pos
    moveq   #0,%d1
sw_p_pos:
    movel   %d4,%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    lea.l   pk_epos,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(24),%d1          | strike length
    bsr     sw_p_dial
    lea.l   pexc_tab,%a0
    movel   %a0@(0,%d1:l:4),%d0
    lea.l   pk_elen,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(26),%d1          | Tone
    bsr     sw_p_dial
    lea.l   pdamp_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   pk_damp,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    lea.l   pcomp_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   pk_comp,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(28),%d1          | Feedback
    bsr     sw_p_dial
    lea.l   pfb_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   pk_fb,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    braw    sw_done
    | ---- wavetable: Start = Position, End = Frame Size, Filter = Smooth,
    | Res = Detune. The sample is cut into frames of 2^shift samples; Position
    | picks a point between two adjacent frames, which the render morphs.
sw_wave:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    sw_w_off
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4   | d4 = sample length
    mvsw    %a2@(24),%d1          | Frame Size: eight steps, 32 .. 4096
    bges    sw_w_sz
    moveq   #0,%d1
sw_w_sz:
    asrl    #8,%d1
    asrl    #4,%d1                | 0..32512 -> 0..7
    addql   #5,%d1                | shift 5..12
sw_w_fit:
    moveq   #1,%d0
    lsll    %d1,%d0
    cmpl    %d4,%d0
    blss    sw_w_fits             | a frame fits in the sample
    subql   #1,%d1                | a short sample: smaller frames
    cmpil   #5,%d1
    bges    sw_w_fit
sw_w_off:
    lea.l   wv_shift,%a1          | under 32 samples: silent
    clrl    %a1@(0,%d2:l:4)
    braw    sw_done
sw_w_fits:
    lea.l   wv_shift,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    lsrl    %d1,%d4
    subql   #1,%d4                | d4 = last frame index
    mvsw    %a2@(22),%d1          | Position -> Q16 of the whole table
    bges    sw_w_ps
    moveq   #0,%d1
sw_w_ps:
    movel   %d1,%d0
    asrl    #6,%d0
    addl    %d1,%d1
    addl    %d0,%d1               | dial * 2.0156: 32512 -> 65532
    lsrl    #8,%d1                | Q8, so (frames-1) * it fits 32 bits
    movel   %d4,%d0
    mulul   %d1,%d0               | frame position, Q8
    movel   %d0,%d1
    lsrl    #8,%d1                | frame A
    lea.l   wv_fa,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    addql   #1,%d1
    cmpl    %d4,%d1
    blss    sw_w_fb
    movel   %d4,%d1               | the last frame morphs with itself
sw_w_fb:
    lea.l   wv_fb,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    andil   #0xff,%d0             | morph amount, Q8
    mvsw    %a2@(26),%d1          | Smooth: sharpen the morph around its middle,
    bsr     sw_p_dial             | from a hard step (0) to linear (127)
    subil   #128,%d0
    asll    #7,%d0
    addql   #1,%d1
    divsl   %d1,%d0
    addil   #128,%d0
    bges    sw_w_m0
    moveq   #0,%d0
sw_w_m0:
    cmpil   #255,%d0
    bles    sw_w_m1
    movel   #255,%d0
sw_w_m1:
    lea.l   wv_m8,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(28),%d1          | Detune
    bsr     sw_p_dial
    lea.l   wdet_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   wv_det,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    braw    sw_done

| d1 = raw dial word -> 0..127. Clobbers nothing else.
sw_p_dial:
    tstl    %d1
    bges    sw_pd0
    moveq   #0,%d1
sw_pd0:
    asrl    #8,%d1
    cmpil   #127,%d1
    bles    sw_pd1
    moveq   #127,%d1
sw_pd1:
    rts

sw_none:
    lea.l   win_lo,%a1
    clrl    %a1@(0,%d2:l:4)
    lea.l   win_span,%a1
    clrl    %a1@(0,%d2:l:4)
    lea.l   win_rev,%a1
    clrl    %a1@(0,%d2:l:4)
sw_done:
    | ---- Loop options that shape the window ----
    | Type: Forward, Reverse (the window played top to bottom - on top of
    | Start > End, which reverses it too) or Ping-pong (the render turns round
    | at each end and records it in pp_dir; here that becomes this block's
    | direction). Crossfade (Forward and Reverse): the last X samples - the
    | amount, at most half the loop - blend into its start; the render's fast
    | test runs on span - X, so only that tail takes the slow path (sv_xfade),
    | and a wrap resumes X in - the start already heard inside the blend. A
    | reversed loop's tail is at the bottom, so its window starts X higher.
    lea.l   loop_mode,%a0
    moveq   #1,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnew    sw_lo_x
    lea.l   lp_type,%a0
    movel   %a0@(0,%d2:l:4),%d1
    cmpil   #2,%d1
    bnes    sw_lo_nr
    lea.l   pp_dir,%a0            | Ping-pong
    tstl    %a0@(0,%d2:l:4)
    beqw    sw_lo_x
    lea.l   win_rev,%a0
    movel   %a0@(0,%d2:l:4),%d0
    eoril   #1,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    braw    sw_lo_x
sw_lo_nr:
    tstl    %d1
    beqs    sw_lo_xf
    lea.l   win_rev,%a0           | Reverse
    movel   %a0@(0,%d2:l:4),%d0
    eoril   #1,%d0
    movel   %d0,%a0@(0,%d2:l:4)
sw_lo_xf:
    lea.l   lp_xfd,%a0
    movel   %a0@(0,%d2:l:4),%d1
    beqw    sw_lo_x               | no crossfade
    lea.l   xfd_len,%a0
    movel   %a0@(0,%d1:l:4),%d1   | X, in samples
    lea.l   win_span,%a0
    movel   %a0@(0,%d2:l:4),%d0   | span
    movel   %d0,%d4               | at most half the loop LESS a margin: the
    lsrl    #1,%d4                | wrap lands at lo + X + the overshoot, which
    subil   #XF_MARGIN,%d4        | must stay under span - X - with X at exactly
    bpls    sw_xf_m               | half it never did, and a short sample at a
    moveq   #0,%d4                | long crossfade went silent at its first wrap
sw_xf_m:
    cmpl    %d4,%d1
    blss    sw_xf_x
    movel   %d4,%d1
sw_xf_x:
    cmpil   #16,%d1
    bcsw    sw_lo_x               | too short to blend: a plain loop
    lea.l   xf_span,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    lea.l   xf_x,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    subl    %d1,%d0
    movel   %d0,%a0@(0,%d2:l:4)   | win_span = span - X
    lea.l   win_rev,%a1
    tstl    %a1@(0,%d2:l:4)
    beqs    sw_xf_f
    lea.l   win_lo,%a1            | reversed: the window starts X higher
    addl    %d1,%a1@(0,%d2:l:4)
sw_xf_f:
    movel   #65536,%d4
    divul   %d1,%d4
    lea.l   xf_rcp,%a1
    movel   %d4,%a1@(0,%d2:l:4)
    lea.l   win_wrap,%a1
    moveq   #3,%d0
    movel   %d0,%a1@(0,%d2:l:4)
sw_lo_x:

    | ---- The Effect (One shot, Loop, Slice): Filter runs the ladder from
    | Filter and Res; Lo-fi, Tape and Vinyl take the two dials over (Rate and
    | Crush; Tone and Wear) with the ladder off; None leaves both idle. The
    | other modes use the dials for their own parameters (the ladder, if on,
    | is the render's business there, as before).
    lea.l   loop_mode,%a0
    moveq   #2,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bcsw    sp_flt_go             | Granular .. Wavetable
    lea.l   fx_sel,%a0
    movel   %a0@(0,%d2:l:4),%d0
    beqw    sp_flt_go             | Filter
    lea.l   filt_f,%a0
    clrl    %a0@(0,%d2:l:4)       | everything else: no ladder
    subql   #1,%d0
    cmpil   #2,%d0
    bhiw    sp_flt_done           | None
    tstl    %d0
    beqs    sp_lofi
    mvsw    %a2@(26),%d1          | Tone
    bsr     sw_p_dial
    lea.l   tvtone_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   tv_tone,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(28),%d1          | Wear, 0..127
    bsr     sw_p_dial
    lea.l   tv_wear,%a1
    movel   %d1,%a1@(0,%d2:l:4)
    braw    sp_flt_done
sp_lofi:
    mvsw    %a2@(26),%d1
    bsr     sw_p_dial
    lea.l   lrate_tab,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   lf_inc,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    mvsw    %a2@(28),%d1
    bsr     sw_p_dial
    lea.l   lcrush_tab,%a0
    movel   %a0@(0,%d1:l:4),%d0
    lea.l   lf_mask,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    braw    sp_flt_done
sp_flt_go:
    | ---- FILTER / RESONANCE coefficients, per track --------------------
    | trackData+28 = Filter (0..32512, max = wide open), +22 = Resonance.
    | filt_f is the Chamberlin coefficient in Q16 and doubles as the "engaged"
    | flag: 0 means the render skips the filter entirely, so a wide-open filter
    | with no resonance costs nothing at all.
    | Free here: d0, d1, d4, a0, a1 - d3 is outBuf and d5-d7 are trigger masks.
    mvsw    %a2@(26),%d1
    bges    sp_flt_fok
    moveq   #0,%d1
sp_flt_fok:
    mvsw    %a2@(28),%d4
    bges    sp_flt_rok
    moveq   #0,%d4
sp_flt_rok:
    movel   %d1,%d0               | keep the raw value for the bypass test
    asrl    #8,%d1                | dial 0..127, computed BEFORE the branch so
    cmpil   #127,%d1              | it is always a valid table index on both
    bles    sp_flt_idx            | paths
    moveq   #127,%d1
sp_flt_idx:
    cmpil   #32512,%d0
    blts    sp_flt_on
    tstl    %d4
    bnes    sp_flt_on
    moveq   #0,%d0                | wide open, no resonance -> bypass
    bras    sp_flt_store
sp_flt_on:
    lea.l   filt_coef,%a0         | exponentially spaced: 30 Hz .. 16 kHz, so
    mvzw    %a0@(0,%d1:l:2),%d0   | equal dial steps are equal musical steps
sp_flt_store:
    lea.l   filt_f,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d4,%d0               | ladder feedback from Resonance
    asrl    #1,%d0
    asrl    #5,%d4
    subl    %d4,%d0
    lea.l   filt_fbmax,%a0        | A ladder's stable feedback limit FALLS as
    mvzw    %a0@(0,%d1:l:2),%d4   | cutoff rises. A flat cap of 15000 exceeds it
    cmpl    %d4,%d0               | from dial 125 up, where an impulse rang
    bles    sp_flt_qok            | instead of decaying - exactly the "above 124
    movel   %d4,%d0               | sounds wrong" the user reported. Each entry
                                  | is the measured limit less 12.5%, capped at
                                  | 15000, and every dial was re-verified stable
sp_flt_qok:
    lea.l   filt_q,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d0,%d4               | resonance makeup: the ladder's passband
    asrl    #7,%d4                | drops to 0.23x at full feedback, which is
    lea.l   filt_mkt,%a0          | why resonance sounds thin. Half-compensate
    mvzw    %a0@(0,%d4:l:2),%d4   | (to ~0.48x) - full compensation needs 4.4x
    lea.l   filt_mk,%a0           | and drives the resonant peak into the
    movel   %d4,%a0@(0,%d2:l:4)   | clamps.

sp_flt_done:
    | ---- Sampler track: restart one-shot on the trigger edge ----
    tstl    %a5@                  | triggered this block?
    beqw    sp_no_trig
    tstl    %a3@                  | ...and not already triggered last block?
    bnew    sp_no_trig

    | ---- SAMPLE START: seed the phase instead of always starting at 0 ----
    | The per-step note is read FIRST now, because in slice mode it is what
    | chooses the window. Reading it here rather than in the per-block section
    | keeps the slice in step with the trigger: the section above runs before
    | the sequencer has presented this step's note.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #3,%d0
    beqs    sp_gran_trig
    cmpil   #4,%d0
    beqs    sp_gran_trig
    cmpil   #5,%d0
    beqs    sp_pluck_trig
    cmpil   #6,%d0
    beqs    sp_wave_trig
    cmpil   #2,%d0
    bnes    sp_start_dial
    | Slice mode: which slice this is depends on THIS block's pitch, and the
    | pitch only becomes current inside sampler_render, after its call to
    | 0x400a9120. Deciding here read the previous step's pitch, which is what
    | made sequenced slices lag by a step. So only record that a trigger
    | happened - the render seeds the phase later in the very same block, so
    | the slice still starts exactly on time.
    lea.l   slice_pending,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    braw    sp_no_trig
sp_gran_trig:
    | Granular: the render starts a grain on this very block (gran_fill)
    lea.l   gr_trig,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    braw    sp_no_trig
sp_pluck_trig:
    | Pluck: the render strikes the string on this very block (pluck_fill)
    lea.l   pk_trig,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    braw    sp_no_trig
sp_wave_trig:
    | Wavetable: the render restarts the oscillator phases (wave_fill)
    lea.l   wv_trig,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    braw    sp_no_trig

sp_start_dial:
    bsr     seed_start
    lea.l   pp_dir,%a0            | ping-pong starts out going the dial's way
    clrl    %a0@(0,%d2:l:4)
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #1,%d0
    bnes    sp_nlseed
    lea.l   lp_type,%a0           | Forward and Reverse loops start at the
    moveq   #2,%d0                | window's own start: its bottom, or its top
    cmpl    %a0@(0,%d2:l:4),%d0   | when played in reverse (the crossfade
    beqs    sp_nlseed             | moves the window, not the dials)
    lea.l   win_lo,%a0
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   win_rev,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sp_lseed
    lea.l   win_span,%a0
    addl    %a0@(0,%d2:l:4),%d0
    subql   #1,%d0
sp_lseed:
    movel   %d2,%d1
    lsll    #3,%d1
    lea.l   phase_table,%a0
    movel   %d0,%a0@(0,%d1:l)
    clrl    %a0@(4,%d1:l)
sp_nlseed:
    lea.l   loop_mode,%a0         | stutter counts from this note
    tstl    %a0@(0,%d2:l:4)
    bnes    sp_no_trig
    lea.l   stu_sel,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sp_no_trig
    bsr     stut_period
    lea.l   st_cnt,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   st_on,%a0
    moveq   #1,%d0
    movel   %d0,%a0@(0,%d2:l:4)
sp_no_trig:
    | ---- One shot's Stutter: back to Start every 1/8, 1/16 or 1/32 ----
    | Every block once a note has started it; the amp envelope ends it.
    | d0/d1/d4/a0/a1 are free here; d3, d5-d7, a3-a5 and fp belong to the
    | caller.
    lea.l   loop_mode,%a0
    tstl    %a0@(0,%d2:l:4)
    bnes    sp_nt_x
    lea.l   stu_sel,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sp_nt_x
    lea.l   st_on,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sp_nt_x
    lea.l   st_cnt,%a0
    movel   %a0@(0,%d2:l:4),%d0
    subil   #32,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    bgts    sp_nt_x
    bsr     stut_period
    tstl    %d0
    beqs    sp_nt_x
    lea.l   st_cnt,%a0
    addl    %d0,%a0@(0,%d2:l:4)
    bsr     seed_start
sp_nt_x:
    moveq   #6,%d4
    movel   %d4,%fp@              | voice@(0) = 6  <- what 0x400a7dee reloads
    jmp     0x400a7dcc            | reset check: fires while a4@ != 6

| ---- d2 = track, a2 = trackData: the phase back to Sample Start ----
| trackData+22 is Sample Start, same scaling, then into the phase index.
| Clobbers d0/d1/a0.
seed_start:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmis    ss_zero
    mvsw    %a2@(22),%d1
    bles    ss_zero
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d0
    lsrl    #6,%d0
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0                | -> sample index
    bras    ss_set
ss_zero:
    clrl    %d0
ss_set:
    movel   %d2,%d1
    lsll    #3,%d1                | 8 bytes per track (ColdFire has no :8 scale)
    lea.l   phase_table,%a0
    movel   %d0,%a0@(0,%d1:l)     | integer index
    clrl    %a0@(4,%d1:l)         | fraction
    rts

| ---- d2 = track -> d0 = samples between stutters, 0 without a tempo ----
| A bar is 1,382,400,000 / tempo (tempo at 0x40149310, 1/120 BPM), divided by
| stu_div: 1/4 1/8 1/16 1/32, and triplet 1/8 and 1/16 (12 and 24 a bar).
| Clobbers d1/a0.
stut_period:
    movel   0x40149310,%d1
    beqs    stp_z
    movel   #1382400000,%d0
    divul   %d1,%d0
    lea.l   stu_sel,%a0
    movel   %a0@(0,%d2:l:4),%d1
    lea.l   stu_div,%a0
    movel   %a0@(0,%d1:l:4),%d1
    beqs    stp_z
    divul   %d1,%d0
    rts
stp_z:
    moveq   #0,%d0
    rts
    .align 4
stu_div:  .long 0, 4, 8, 16, 32, 12, 24
xfd_len:  .long 0, 480, 1200, 2400, 4800, 12000 | 10 25 50 100 250 ms
XF_MARGIN = 64                    | more than one step's overshoot at any pitch

sp_not_sampler:
    | ---- original gate, byte-identical behaviour ----
    tstl    %a3@
    beqs    sp_skip
    jmp     0x400a7db0
sp_skip:
    jmp     0x400a7de0

| ================= patch 3: dispatch =================
| live: d1=param arg, d2=trackIdx, d3=outBuf, d4=machine, d6=0x40118628,
|       fp=voice, a2=trackData. d0 dead.
sampler_dispatch:
    movel   0xfc07800c,%d0        | profile: this track's render starts
    movel   %d0,prof_ta
    moveq   #6,%d0
    cmpl    %d4,%d0
    bnes    sd_normal
    | A Sampler track that went idle last block (sampler_render's idle path
    | has run: sv_idle set, both ladders and grains cleared) and is still
    | silent with no pulse: neither the plumbing nor the render can change
    | anything, so both are skipped - silence, and not stereo. Pluck's lines
    | must be fully cleared first (sv_pk_clear, a little each idle block).
    lea.l   sv_idle,%a0
    tstb    %a0@(0,%d2:l)
    beqs    sd_srun
    lea.l   pk_clr,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #2048,%d0
    bcss    sd_srun
    tstl    %fp@(0x34)
    bnes    sd_srun
    tstl    %fp@(0x38)
    bnes    sd_srun
    tstl    %fp@(0x3c)
    bnes    sd_srun
    movea.l %fp,%a0
    movel   %d1,%sp@-
    movel   %d2,%d1
    bsr     voice_quiet
    movel   %sp@+,%d1
    tstl    %d0
    beqs    sd_srun
    lea.l   sx_on,%a0
    clrl    %a0@(0,%d2:l:4)
    braw    sd_qz                 | silence
sd_srun:
    movel   %a2,%sp@-
    movel   %fp,%sp@-
    movel   %d1,%sp@-
    jsr     0x400aa7b8            | generic per-voice param plumbing
    lea.l   %sp@(12),%sp
    movel   %d2,%sp@-             | arg3 = trackIdx
    movel   %fp,%sp@-             | arg2 = voice
    movel   %d3,%sp@-             | arg1 = outBuf
    jsr     sampler_render
    lea.l   %sp@(12),%sp
    braw    sd_prof
sd_normal:
    | A stock machine whose note has finished (voice_quiet) is not rendered:
    | its parameter call still runs, its output is silence. The stock render
    | has no idle path of its own - Kick, Snare and Metal were ~28% of every
    | block with nothing playing.
    movea.l %fp,%a0
    movel   %d1,%sp@-
    movel   %d2,%d1
    bsr     voice_quiet
    movel   %sp@+,%d1
    tstl    %d0
    beqs    sd_live
    | Silent with no pulse this block (a trig now or last block, All Sound
    | Off): nothing will render, so its parameter call is skipped too - it
    | runs again on the trigger block, before the render. It only derives
    | the voice's targets from trackData (the render ramps toward them), so
    | nothing is lost; Kick 1.5% and Snare 1.1% of every block while silent.
    tstl    %fp@(0x34)
    bnes    sd_qpar
    tstl    %fp@(0x38)
    bnes    sd_qpar
    tstl    %fp@(0x3c)
    beqs    sd_qz
sd_qpar:
    moveal  %d6,%a0
    moveal  %a0@(0,%d4:l:4),%a1
    movel   %a2,%sp@-
    movel   %fp,%sp@-
    movel   %d1,%sp@-
    jsr     %a1@                  | its parameters
    lea.l   %sp@(12),%sp
sd_qz:
    movea.l %d3,%a0
    moveq   #31,%d0
sd_z:
    clrl    %a0@+
    subql   #1,%d0
    bpls    sd_z
    braw    sd_prof
sd_live:
    moveal  %d6,%a0
    moveal  %a0@(0,%d4:l:4),%a1
    movel   %a2,%sp@-
    movel   %fp,%sp@-
    movel   %d1,%sp@-
    jsr     %a1@
    movel   %fp,%sp@-
    movel   %d3,%sp@-
    lea.l   0x40118610,%a0
    moveal  %a0@(0,%d4:l:4),%a1
    jsr     %a1@
    lea.l   %sp@(20),%sp
    movea.l %d3,%a0               | how loud the note still is
    movel   %d2,%d0
    bsr     sil_note
sd_prof:                          | ...and ends: d0 and a0 are dead at 0x400a7e24
    movel   0xfc07800c,%d0
    subl    prof_ta,%d0
    bmis    sd_pz
    lea.l   prof_trk,%a0
    addl    %d0,%a0@(0,%d2:l:4)
sd_pz:
    jmp     0x400a7e24

| ================= our render =================
| sampler_render(outBuf, voice, trackIdx)
| ---- semitone offset of the voice pitch -> slice 0..15 ------------------
| a1 = voice; voice+232 is the pitch the note was converted into. The render's
| own constant fixes the scale (93957 = 65536/45710 * 65536, so 45710 is 1.0x)
| and pitch_thr holds the geometric midpoints between adjacent semitones, so
| counting entries at or below the pitch gives the offset with no logarithm and
| no division. Clobbers d0/a0; returns d1.
slice_from_pitch:
    movel   %a1@(232),%d1
    beqs    sfp_default
    lea.l   pitch_thr,%a0
    moveq   #0,%d0
sfp_scan:
    cmpl    %a0@+,%d1
    bcss    sfp_found
    addql   #1,%d0
    cmpil   #48,%d0
    bcss    sfp_scan
sfp_found:
    addil   #36,%d0               | index -24 semitones, then +60 -> the note
    subil   #52,%d0               | trig pad 1 is note 52 = slice 0
    movel   %d0,%d1               | unmasked: the caller wraps it to its count
    rts
sfp_default:
    moveq   #8,%d1                | no pitch yet: note 60, which is pad 9
    rts

sampler_render:
    lea.l   %sp@(-48),%sp         | 32 for the registers, then step_int, frac
    moveml  %d2-%d7/%a2-%a3,%sp@  | and a slot to park outBuf during the fill
    movel   %sp@(52),%d3          | outBuf
    movel   %sp@(56),%d2          | voice
    movel   %sp@(60),%d4          | trackIdx
    clrl    sx_ok                 | mono unless sv_notgran finds a side plane

    movel   %d2,%sp@-
    jsr     0x400a9120            | envelope / per-block param update
    addql   #4,%sp

    | ---- idle: a finished note renders nothing ---------------------------
    | Every Sampler track used to run its whole chain every block, playing or
    | not. The stock amp envelope 0x400a967a scales the output by voice+0x294
    | and sets stage +0x298 = 5 once it has fallen to its floor; with no trig
    | this block or the last (+0x34 now, +0x38 last block, +0x3c the other
    | pulse), stage 5 and a level under -90 dB, nothing the source does can be
    | heard. So everything is skipped - fill, filter, effects, grains,
    | decimator and the gain stages, mid and side - and outBuf is silence
    | (voice_quiet also takes a track MUT has faded out, and never the source
    | of a recording in progress, whose capture must keep time).
    movea.l %d2,%a0
    movel   %d4,%d1
    bsr     voice_quiet
    tstl    %d0
    beqs    sv_live
    bsr     sv_idle_enter
    bsr     sv_pk_clear
    movea.l %d3,%a0               | silence
    moveq   #31,%d0
    moveq   #0,%d1
sv_idz:
    movel   %d1,%a0@+
    subql   #1,%d0
    bpls    sv_idz
    clrl    sx_ok
    braw    sv_tail
sv_live:
    lea.l   sv_idle,%a0
    clrb    %a0@(0,%d4:l)
    lea.l   pk_clr,%a0            | Pluck's lines not yet fully cleared while
    movel   %a0@(0,%d4:l:4),%d0   | idle: pluck_fill clears them itself, whole
    cmpil   #2048,%d0             | (the rare case of a note within 8 blocks)
    bccs    sv_lv
    movel   #2048,%d0
    movel   %d0,%a0@(0,%d4:l:4)
    lea.l   pk_init,%a0
    clrb    %a0@(0,%d4:l)
    lea.l   sx_pkinit,%a0
    clrb    %a0@(0,%d4:l)
sv_lv:

    | ---- slice mode: the window, decided HERE ---------------------------
    | 0x400a9120 is what makes this block's pitch current, so this is the
    | earliest point the played note is knowable - and it is still before the
    | phase is read below, so a trigger recorded by sampler_pre a few
    | instructions ago is served in the same block, on time.
    | d2 = voice, d4 = trackIdx; d5 and a0/a1 are not live yet.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d4:l:4),%d0
    cmpil   #2,%d0
    bnew    sv_noslice
    lea.l   track_slot,%a0
    movel   %a0@(0,%d4:l:4),%d0
    bmiw    sv_noslice
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d5
    lsrl    #4,%d5                | slice length
    beqw    sv_noslice            | fewer than 16 samples: nothing to slice
    movea.l %d2,%a1
    bsr     slice_from_pitch      | -> d1 = note - 52
    tstl    sle_run               | the slice editor tapping this track: the
    beqs    sv_sl_nt              | whole sample, from its start
    cmpl    sle_trk,%d4
    bnes    sv_sl_nt
    lea.l   track_slot,%a0
    movel   %a0@(0,%d4:l:4),%d0
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d5
    moveq   #0,%d0
    moveq   #0,%d1
    braw    sv_sl_base
sv_sl_nt:
    | The slice table (slice_watch, UI side) gives each slice's first sample,
    | with the sample's end after the last. Until it is ready - sl_S is 0 while
    | it is being rebuilt - play 16 equal slices, as this always did.
    lea.l   sl_S,%a0
    movel   %a0@(0,%d4:l:4),%d0
    beqs    sv_sl_eq16
    lea.l   sl_N,%a0
    movel   %a0@(0,%d4:l:4),%d5
    subql   #1,%d5
    andl    %d5,%d1               | note -> 0..N-1, pads wrapping by octave
sv_sl_wrap:
    cmpl    %d0,%d1
    bcss    sv_sl_in
    subl    %d0,%d1               | transient mode can find fewer than N
    bras    sv_sl_wrap
sv_sl_in:
    movel   %d4,%d5               | this track's row: 33 longs
    lsll    #5,%d5
    addl    %d4,%d5
    lsll    #2,%d5
    lea.l   sl_tbl,%a0
    addal   %d5,%a0
    lea.l   %a0@(0,%d1:l:4),%a0
    movel   %a0@,%d0              | first sample
    movel   %a0@(4),%d5
    subl    %d0,%d5               | length
    bhis    sv_sl_base
    braw    sv_noslice
sv_sl_eq16:
    andil   #15,%d1
    movel   %d5,%d0
    mulul   %d1,%d0               | the slice's first sample
sv_sl_base:
    lea.l   wf_slb,%a0            | the slice being played, for the waveform
    movel   %d0,%a0@(0,%d4:l:4)
    lea.l   wf_sli,%a0
    movel   %d1,%a0@(0,%d4:l:4)
    lea.l   wf_sll,%a0            | length last: the UI reads it as "ready"
    movel   %d5,%a0@(0,%d4:l:4)
    | ---- Start and End trim WITHIN the slice --------------------------
    | Both dials scale across the slice rather than the whole sample, so they
    | stay useful in slice mode - and Start > End reverses the slice, exactly
    | as it reverses a one-shot.
    lea.l   dial_start,%a0
    movel   %a0@(0,%d4:l:4),%d6
    lea.l   dial_end,%a0
    movel   %a0@(0,%d4:l:4),%d7
    movel   %d0,%sp@-             | park the slice base
    movel   %d5,%d1
    lsrl    #6,%d1                | the same divide-free scaling as elsewhere
    beqs    sv_sl_nofit           | slice under 64 samples: no room to trim
    movel   %d1,%d0
    mulul   %d6,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    movel   %d0,%sp@-             | start offset
    cmpil   #32512,%d7
    bges    sv_sl_emax
    movel   %d1,%d0
    mulul   %d7,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0                | end offset
    bras    sv_sl_have
sv_sl_emax:
    movel   %d5,%d0               | End at maximum means the whole slice
sv_sl_have:
    movel   %sp@+,%d1
    bras    sv_sl_dir
sv_sl_nofit:
    moveq   #0,%d1
    movel   %d5,%d0
sv_sl_dir:
    cmpl    %d7,%d6
    bhis    sv_sl_rev
    subl    %d1,%d0               | forward: span = end - start
    bhis    sv_sl_fok
    moveq   #1,%d0                | degenerate window -> one sample
sv_sl_fok:
    movel   %d0,%d5
    movel   %sp@+,%d0
    addl    %d1,%d0               | lo = base + start
    moveq   #0,%d1
    bras    sv_sl_set
sv_sl_rev:
    movel   %d1,%d5
    subl    %d0,%d5
    addql   #1,%d5                | reverse: span = start - end + 1
    movel   %sp@+,%d1
    addl    %d0,%d1               | lo = base + end
    movel   %d1,%d0
    moveq   #1,%d1
sv_sl_set:
    lea.l   win_span,%a0
    movel   %d5,%a0@(0,%d4:l:4)
    lea.l   win_rev,%a0
    movel   %d1,%a0@(0,%d4:l:4)
    lea.l   win_lo,%a0
    cmpl    %a0@(0,%d4:l:4),%d0
    bnes    sv_slseed             | a different slice: restart inside it
    lea.l   slice_pending,%a0
    tstb    %a0@(0,%d4:l)
    beqs    sv_noslice            | same slice and no fresh trigger: leave the
                                  | phase alone, or a held note would restart
                                  | every single block
sv_slseed:
    lea.l   win_lo,%a0
    movel   %d0,%a0@(0,%d4:l:4)
    lea.l   slice_pending,%a0
    clrb    %a0@(0,%d4:l)
    lea.l   win_rev,%a0           | a reversed slice starts at its far end
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_slfwd
    addl    %d5,%d0
    subql   #1,%d0
sv_slfwd:
    movel   %d4,%d1
    lsll    #3,%d1                | 8 bytes per track
    lea.l   phase_table,%a0
    movel   %d0,%a0@(0,%d1:l)     | first sample of the window
    clrl    %a0@(4,%d1:l)
sv_noslice:

    | fill the 2x oversample buffer from PCM (zero-order hold)
    lea.l   phase_table,%a3
    movel   %d4,%d0
    lsll    #3,%d0
    lea.l   %a3@(0,%d0:l),%a3     | a3 = &phase[track]
    movel   %a3@,%d5              | d5 = integer sample index
    | ---- step from the engine's own pitch value at voice+232 ----
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d4:l:4),%d0
    cmpil   #2,%d0
    beqs    sv_defstep            | slice mode: the note chooses the slice, so
                                  | it must not transpose as well
    movea.l %d2,%a0               | d2 = voice
    movel   %a0@(232),%d1
    beqs    sv_defstep            | not set -> play at 1.0
    lsrl    #4,%d1                | ColdFire: no divul.l, no shift > 8
    movel   #93957,%d0            | 65536/45710 * 65536
    mulul   %d0,%d1
    lsrl    #8,%d1
    lsrl    #4,%d1                | (v>>4)*93957>>12 -> Q16.16
    tstl    %d1
    bnes    sv_havestep
sv_defstep:
    movel   #0x10000,%d1
sv_havestep:
    bsr     step_mod              | tape/vinyl wobble, loop tempo sync
    | split the Q16.16 step into whole samples + a Q0.32 fraction.
    | sp@(32)/sp@(36) are spare: the frame reserves 40 bytes and the moveml
    | prologue only uses 32.
    movel   %d1,%d0
    lsrl    #8,%d0
    lsrl    #8,%d0                | whole samples per output sample
    movel   %d0,%sp@(32)
    lsll    #8,%d1
    lsll    #8,%d1                | fractional part, Q0.32
    movel   %a3@(4),%d0
    movel   %d0,%sp@(36)          | running fraction
    lea.l   sampler_buf+32,%a1     | input window starts at +32, NOT +0
    moveq   #31,%d7
    | Park outBuf UNCONDITIONALLY. It used to be parked only on the loaded path
    | and restored only if pcm_ready was still set at the bottom - two separate
    | reads of a flag the UI thread clears in load_by_hash. Selecting anything
    | in the browser could land between them, leaving d3 holding a byte offset
    | (0..0xFFFFF) that was then passed to the DSP calls as the output buffer:
    | a write into the vector page, i.e. the random browsing exception.
    movel   %d3,%sp@(40)
    lea.l   track_slot,%a0         | a0 is dead here (voice was reloaded into d2)
    movel   %a0@(0,%d4:l:4),%d0
    bpls    sv_loaded
    | Pluck with a noise, click or drum exciter needs no sample at all
    lea.l   loop_mode,%a0
    moveq   #5,%d6
    cmpl    %a0@(0,%d4:l:4),%d6
    bnes    sv_nos
    lea.l   pk_exc,%a0            | Noise or Click needs no sample
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_nos
    clrl    %sp@-                 | count
    clrl    %sp@-                 | PCM base
    movel   %sp@(40),%d6          | whole step: sp@(32) before these two pushes
    swap    %d6
    clrw    %d6
    movel   %d1,%d0
    clrw    %d0
    swap    %d0
    orl     %d0,%d6
    movel   %d6,%sp@-
    movel   %d4,%sp@-
    jsr     pluck_fill
    lea.l   %sp@(16),%sp
    movel   %sp@(40),%d3
    braw    sv_nofilt
sv_nos:

    | ---- nothing loaded yet -> silence ----
    | This used to play a 16 KiB clip embedded in the blob - 61% of its size,
    | for a fallback that pad_load_hook makes redundant by loading a real
    | sample off the eMMC at boot. The phase is deliberately left alone.
    clrl    %d0
sv_fill:
    movel   %d0,%a1@+
    movel   %d0,%a1@+
    subql   #1,%d7
    bpls    sv_fill
    braw    sv_filled

    | ---- a sample read off the eMMC: big-endian 16-bit mono at 48 kHz ----
sv_loaded:
    | The sample lives in 1 MiB segments, because the firmware's allocator is a
    | buddy allocator with a fixed maximum order - it will hand out several
    | medium blocks happily but never one 9 MB block. Map the sample index to a
    | segment and an offset inside it:
    |     byteoff = 64 + idx*2        (64 skips the file header)
    |     seg     = byteoff >> 20
    |     within  = byteoff & 0xFFFFF
    | byteoff is always even and segments are 1 MiB, so a 16-bit sample can
    | never straddle a boundary.
    | d0 = this track's slot. Use d3, NOT d1: d1 holds the Q0.32 step fraction
    | for the entire fill loop, and clobbering it pinned every note to the same
    | pitch because the accumulator then carried on almost every sample.
    lea.l   slot_base,%a0
    movel   %a0@(0,%d0:l:4),%d3
    addil   #64,%d3                | past the file header
    movel   %d3,%sp@(44)
    | Granular: the grains fill the buffer instead, and the filter is skipped -
    | its two dials are Density and Spray in this mode. d1/sp@(32) hold the
    | note's step as the fill loop would use it; d6 is not live yet.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d4:l:4),%d6
    cmpil   #5,%d6
    beqw    sv_pluck
    cmpil   #6,%d6
    beqw    sv_wave
    subql   #3,%d6
    cmpil   #1,%d6
    bhiw    sv_notgran            | granular (3) and stretch (4) only
    lea.l   chn_sel,%a0           | Channels: Stereo renders the side too
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_gmono
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d0:l:4),%d6
    beqs    sv_gmono
    addl    %d3,%d6
    movel   %d6,sx_gpcm
    moveq   #1,%d6
    movel   %d6,sx_ok
sv_gmono:
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%sp@- | count
    movel   %d3,%sp@-             | PCM base
    movel   %d1,%sp@-             | step fraction, Q0.32
    movel   %sp@(44),%sp@-        | whole step: sp@(32) before these three pushes
    movel   %d4,%sp@-             | track
    jsr     gran_fill
    lea.l   %sp@(20),%sp
    movel   %sp@(40),%d3          | outBuf back
    braw    sv_nofilt
sv_pluck:
    | Pluck: pluck_fill wants the note's step as one Q16 value, rebuilt from
    | the whole part at sp@(32) and the Q0.32 fraction in d1. In stereo, with
    | the Sample exciter, pluck_st strikes a second string with the side.
    clrl    sx_side_off
    lea.l   chn_sel,%a0
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_pk1
    lea.l   pk_exc,%a0
    tstl    %a0@(0,%d4:l:4)
    bnes    sv_pk1
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d0:l:4),%d6
    beqs    sv_pk1
    movel   %d6,sx_side_off
    moveq   #1,%d6
    movel   %d6,sx_ok
sv_pk1:
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%sp@- | count
    movel   %d3,%sp@-             | PCM base
    movel   %sp@(40),%d6          | whole step: sp@(32) before these two pushes
    swap    %d6
    clrw    %d6
    movel   %d1,%d0
    clrw    %d0
    swap    %d0
    orl     %d0,%d6
    movel   %d6,%sp@-             | step, Q16
    movel   %d4,%sp@-             | track
    jsr     pluck_st
    lea.l   %sp@(16),%sp
    movel   %sp@(40),%d3          | outBuf back
    braw    sv_nofilt
sv_wave:
    | Wavetable: same arguments as pluck_fill, built the same way; in stereo
    | wave_st renders the side's frames too
    clrl    sx_side_off
    lea.l   chn_sel,%a0
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_wv1
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d0:l:4),%d6
    beqs    sv_wv1
    movel   %d6,sx_side_off
    moveq   #1,%d6
    movel   %d6,sx_ok
sv_wv1:
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%sp@- | count
    movel   %d3,%sp@-             | PCM base
    movel   %sp@(40),%d6          | whole step: sp@(32) before these two pushes
    swap    %d6
    clrw    %d6
    movel   %d1,%d0
    clrw    %d0
    swap    %d0
    orl     %d0,%d6
    movel   %d6,%sp@-             | step, Q16
    movel   %d4,%sp@-             | track
    jsr     wave_st
    lea.l   %sp@(16),%sp
    movel   %sp@(40),%d3          | outBuf back
    braw    sv_nofilt
sv_notgran:
    | ---- stereo: the side plane goes through this same fill first --------
    | A stereo slot holds two planes, mid (L+R)/2 then side (L-R)/2, slot_soff
    | bytes apart. Everything that reads one plane reads the mid, so only here
    | (One shot, Loop, Slice) is the side filled too: the loop below runs once
    | on it into sx_buf, with every piece of state it moves - index, fraction,
    | the step and its sign, pp_dir, win_rev - saved first and put back at
    | sv_filled, and then runs again, for real, on the mid. Lo-fi, Tape and
    | Vinyl then run on true left and right (sx_fx_r / sx_fx_back).
    | d0 = the slot; d6, a0 and a2 are free here, a1 is the fill pointer.
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d0:l:4),%d0
    beqw    sv_ng_body
    lea.l   chn_sel,%a0           | Channels: Stereo, or the mid alone
    tstl    %a0@(0,%d4:l:4)
    beqw    sv_ng_body
sv_ng_st:
    lea.l   sx_sv,%a2
    movel   %d5,%a2@              | index
    movel   %sp@(36),%d6
    movel   %d6,%a2@(4)           | fraction
    movel   %sp@(32),%d6
    movel   %d6,%a2@(8)           | whole step
    movel   %d1,%a2@(12)          | step fraction
    lea.l   pp_dir,%a0
    movel   %a0@(0,%d4:l:4),%d6
    movel   %d6,%a2@(16)
    lea.l   win_rev,%a0
    movel   %a0@(0,%d4:l:4),%d6
    movel   %d6,%a2@(20)
    lea.l   sx_soff,%a0
    movel   %d0,%a0@
    addl    %d0,%sp@(44)          | the PCM base, on the side plane
    lea.l   sx_buf+32,%a1         | into the side's own 2x buffer
    moveq   #1,%d6
    movel   %d6,sx_ok
    movel   %d6,sx_pass
sv_ng_body:
    lea.l   win_lo,%a0             | d3 is free again: outBuf went to sp@(40)
    movel   %a0@(0,%d4:l:4),%d3    | and the PCM base to sp@(44)
    lea.l   win_span,%a0
    movel   %a0@(0,%d4:l:4),%d6
    lea.l   win_rev,%a0
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_fill16
    | Reverse: negate the 64-bit step (whole:frac) ONCE here, so the
    | accumulator arithmetic at the bottom of the loop is untouched and simply
    | counts down. negl sets X from the fraction and negxl propagates that
    | borrow into the whole part. This is the one deliberate write to d1
    | between sv_havestep and sv_filled - everything else in that span still
    | has to leave the step fraction alone.
    movel   %sp@(32),%d0
    negl    %d1
    negxl   %d0
    movel   %d0,%sp@(32)
sv_fill16:
    movel   %d5,%d0                | inside the window? one unsigned compare
    subl    %d3,%d0                | covers both ends and both directions, and
    cmpl    %d6,%d0                | underflow past lo wraps high, so it fails
    bccs    sv_oow                 | the same test
sv_fetch:
    movel   %d5,%d0
    addl    %d0,%d0               | byte offset into the PCM data
    movea.l %sp@(44),%a0
    mvsw    %a0@(0,%d0:l),%d0     | sign-extending 16-bit fetch
    lsll    #8,%d0
    lsll    #7,%d0                | <<15: peak ~0x3FFF8000
    braw    sv_st16

    | Off the end of the window. One-shot goes quiet; loop wraps. d0 still holds
    | (idx - lo), so the wrap is one add or subtract in 32-bit arithmetic:
    | overshooting the top gives span+j, and -span leaves j; underflowing the
    | bottom by k gives 2^32-k, and +span leaves span-k. a0 is free here, the
    | fetch above reloads it.
sv_oow:
    lea.l   win_wrap,%a0          | set from loop_mode each block, so the hot
    lea.l   %a0@(0,%d4:l:4),%a0   | loop needs no spare register to test a mode
    tstl    %a0@
    beqw    sv_sil16
    btst    #1,%a0@(3)            | 2 ping-pong, 3 crossfade
    bnew    sv_oow_ext
    lea.l   win_rev,%a0
    tstl    %a0@(0,%d4:l:4)
    beqs    sv_wrapf
    addl    %d6,%d0
    bras    sv_wrapc
sv_wrapf:
    subl    %d6,%d0
sv_wrapc:
    cmpl    %d6,%d0
    bccw    sv_sil16               | still outside: one step longer than the
                                   | whole window, so there is nothing to loop
    movel   %d0,%d5
    addl    %d3,%d5
    bras    sv_fetch
    | ---- ping-pong: reflect off the end and turn round ----
    | d0 = idx - lo. Past the top (d0 >= span) the reflection is
    | 2*span - 1 - d0; below the bottom (d0 wrapped negative) it is -d0 - 1.
    | Then the step is negated - the one other mid-loop write to d1, like the
    | reverse at the top of the block - and pp_dir and win_rev are flipped so
    | the rest of this block and the next agree on the direction.
sv_oow_ext:
    btst    #0,%a0@(3)
    bnew    sv_xfade
    tstl    %d0
    bmis    sv_pp_lo
    negl    %d0
    addl    %d6,%d0
    addl    %d6,%d0
    subql   #1,%d0
    bras    sv_pp_chk
sv_pp_lo:
    notl    %d0
sv_pp_chk:
    cmpl    %d6,%d0
    bccw    sv_sil16
    movel   %d0,%d5
    addl    %d3,%d5
    movel   %sp@(32),%d0
    negl    %d1
    negxl   %d0
    movel   %d0,%sp@(32)
    lea.l   pp_dir,%a0
    movel   %a0@(0,%d4:l:4),%d0
    eoril   #1,%d0
    movel   %d0,%a0@(0,%d4:l:4)
    lea.l   win_rev,%a0
    movel   %a0@(0,%d4:l:4),%d0
    eoril   #1,%d0
    movel   %d0,%a0@(0,%d4:l:4)
    braw    sv_fetch

    | ---- crossfade: the loop's last X samples blend into its first X ----
    | d6 is span - X here, so d0 = idx - lo is at or past the blend's start.
    | Inside the true span: mix x[idx] toward x[lo + j], j = d0 - d6, by j/X.
    | Past it: carry on from lo + X + the overshoot. Only d0/a0 are free, so
    | d6/d7 go on the stack for the blend - nothing reads sp@() meanwhile.
sv_xfade:
    lea.l   win_rev,%a0           | a reversed loop's tail is at the bottom
    tstl    %a0@(0,%d4:l:4)
    bnew    sv_xfr
    tstl    %d0
    bmiw    sv_sil16
    lea.l   xf_span,%a0
    cmpl    %a0@(0,%d4:l:4),%d0
    bccs    sv_xf_wrap
    movea.l %sp@(44),%a0          | PCM base, before the pushes move sp
    movel   %d7,%sp@-
    movel   %d6,%sp@-
    subl    %d6,%d0               | j
    movel   %d0,%d6
    movel   %d3,%d7
    addl    %d0,%d7
    addl    %d7,%d7
    mvsw    %a0@(0,%d7:l),%d7     | x[lo + j]
    movel   %d5,%d0
    addl    %d0,%d0
    mvsw    %a0@(0,%d0:l),%d0     | x[idx]
    subl    %d0,%d7
    lea.l   xf_rcp,%a0
    lea.l   %a0@(0,%d4:l:4),%a0
    mulsl   %a0@,%d6              | j/X, Q16 (at most 65536)
    lsrl    #2,%d6                | Q14, so the product fits
    mulsl   %d6,%d7
    asrl    #8,%d7
    asrl    #6,%d7
    addl    %d7,%d0
    movel   %sp@+,%d6
    movel   %sp@+,%d7
    lsll    #8,%d0
    lsll    #7,%d0
    braw    sv_st16
sv_xf_wrap:
    subl    %a0@(0,%d4:l:4),%d0   | the overshoot
    lea.l   xf_x,%a0
    addl    %a0@(0,%d4:l:4),%d0
    cmpl    %d6,%d0
    bccs    sv_sil16
    movel   %d0,%d5
    addl    %d3,%d5
    braw    sv_fetch
    | ---- reversed: the window starts X above the loop's bottom (lo'), so
    | d0 = idx - lo' runs -1..-X through the tail, blending x[idx] toward the
    | loop's top end (lo' + span' - 1 - j, j = -1 - d0) by j/X; past the bottom
    | by k it carries on at top - X - k = lo' + span' + d0, heard in the blend.
    | a2 is free in the fill; d6/d7 go on the stack as the forward case does.
sv_xfr:
    tstl    %d0
    bplw    sv_sil16              | above the window's top: nothing there
    movea.l %sp@(44),%a0          | PCM base, before the pushes
    movel   %d7,%sp@-
    movel   %d6,%sp@-             | span'
    lea.l   xf_x,%a2
    movel   %a2@(0,%d4:l:4),%d7   | X
    movel   %d0,%d6
    addl    %d7,%d6
    bmis    sv_xfr_wrap           | below the bottom
    notl    %d0                   | j
    movel   %d0,%d6
    movel   %sp@,%d7
    addl    %d3,%d7
    subl    %d0,%d7
    subql   #1,%d7                | lo' + span' - 1 - j
    addl    %d7,%d7
    mvsw    %a0@(0,%d7:l),%d7     | the partner, from the top
    movel   %d5,%d0
    addl    %d0,%d0
    mvsw    %a0@(0,%d0:l),%d0     | x[idx]
    subl    %d0,%d7
    lea.l   xf_rcp,%a2
    lea.l   %a2@(0,%d4:l:4),%a2
    mulsl   %a2@,%d6              | j/X, Q16
    lsrl    #2,%d6
    mulsl   %d6,%d7
    asrl    #8,%d7
    asrl    #6,%d7
    addl    %d7,%d0
    movel   %sp@+,%d6
    movel   %sp@+,%d7
    lsll    #8,%d0
    lsll    #7,%d0
    bras    sv_st16
sv_xfr_wrap:
    movel   %sp@+,%d6             | span'
    movel   %sp@+,%d7
    addl    %d6,%d0               | lo' + span' + d0, less lo'
    bmis    sv_sil16
    cmpl    %d6,%d0
    bccs    sv_sil16
    movel   %d0,%d5
    addl    %d3,%d5
    braw    sv_fetch
sv_sil16:
    clrl    %d0
sv_st16:
    movel   %d0,%a1@+
    movel   %d0,%a1@+
    movel   %sp@(36),%d0
    addl    %d1,%d0
    movel   %d0,%sp@(36)
    movel   %sp@(32),%d0
    addxl   %d0,%d5
    subql   #1,%d7
    bplw    sv_fill16
sv_filled:
    tstl    sx_pass               | the side's pass: put the state back and
    beqs    sv_fl_mid             | fill again from the mid plane
    clrl    sx_pass
    lea.l   sx_sv,%a2
    movel   %a2@,%d5
    movel   %a2@(4),%d0
    movel   %d0,%sp@(36)
    movel   %a2@(8),%d0
    movel   %d0,%sp@(32)
    movel   %a2@(12),%d1
    lea.l   pp_dir,%a0
    movel   %a2@(16),%d0
    movel   %d0,%a0@(0,%d4:l:4)
    lea.l   win_rev,%a0
    movel   %a2@(20),%d0
    movel   %d0,%a0@(0,%d4:l:4)
    movel   sx_soff,%d0
    subl    %d0,%sp@(44)
    lea.l   sampler_buf+32,%a1
    moveq   #31,%d7
    braw    sv_ng_body
sv_fl_mid:
    movel   %d5,%a3@              | index back to phase[track]
    movel   %sp@(36),%d0
    movel   %d0,%a3@(4)           | fraction back
    movel   %sp@(40),%d3          | outBuf back, on both paths

    | ---- filter the oversampled buffer in place ------------------------
    | Chamberlin state variable filter, lowpass output. Deliberately NOT inside
    | the fill loop: that loop holds the Q0.32 step fraction in d1 for its whole
    | length, and every register bug in this file has come from disturbing it.
    | The integrator state is held in Q12 (filt_low/filt_band are LOW and BAND,
    | 4096x the real value). With plain integer state, (band*f)>>12 truncates to
    | ZERO whenever f is small: at the bottom of the dial a quiet signal froze on
    | a DC offset and a loud one stepped 1 bit at a time - the "bit crushing"
    | with no low end. Accumulating in Q12 lets those small increments add up.
    | Bounds, all verified in simulation: |b|<=131072 so b*f<=5.0e8 and
    | LOW+b*f<=1.6e9; high is clamped to +-262143 so high*f<=1.0e9 and
    | BAND+high*f<=1.5e9 - all inside 2^31.
    lea.l   loop_mode,%a0         | Lo-fi, Tape, Vinyl: One shot, Loop, Slice
    moveq   #2,%d0
    cmpl    %a0@(0,%d4:l:4),%d0
    bcsw    sv_nolofi
    lea.l   fx_sel,%a0
    movel   %a0@(0,%d4:l:4),%d0
    movel   %d0,%d1
    subql   #1,%d1
    cmpil   #2,%d1
    bhiw    sv_nolofi             | not Lo-fi, Tape or Vinyl
    tstl    sx_ok
    beqs    sv_nl1
    bsr     sx_fx_r               | stereo: to L/R, and R processed first
sv_nl1:
    cmpil   #1,%d0
    bnes    sv_nl2
    movel   %d4,%d0
    bsr     lofi_apply
    bsr     sx_fx_back
    braw    sv_nofilt
sv_nl2:
    cmpil   #2,%d0
    bnes    sv_nl3
    movel   %d4,%d0
    bsr     tape_apply
    bsr     sx_fx_back
    bras    sv_nolofi
sv_nl3:
    movel   %d4,%d0
    bsr     vinyl_apply
    bsr     sx_fx_back
sv_nolofi:
    lea.l   filt_f,%a0
    movel   %a0@(0,%d4:l:4),%d0
    beqw    sv_nofilt
    | The gain comes back in full the block after a trigger (voice+56), the
    | stock fade (0x400a9252/0x400a9430, after this) having taken the block
    | before to zero: the ladders start from rest there, so that return rises
    | from silence instead of stepping into whatever they held (as gflt_run
    | does for the stock machines since samplerHV). Mid and side.
    movea.l %d2,%a0
    tstl    %a0@(56)
    beqs    sv_fnt
    movel   %d4,%d5               | d5 is free: the phase went back at sv_fl_mid
    lsll    #2,%d5
    lea.l   filt_y1,%a0
    adda.l  %d5,%a0
    clrl    %a0@
    clrl    %a0@(24)
    clrl    %a0@(48)
    clrl    %a0@(72)
    lea.l   sx_y1,%a0
    adda.l  %d5,%a0
    clrl    %a0@
    clrl    %a0@(24)
    clrl    %a0@(48)
    clrl    %a0@(72)
    lea.l   filt_f,%a0
    movel   %a0@(0,%d4:l:4),%d0
sv_fnt:
    lea.l   filt_q,%a0
    movel   %a0@(0,%d4:l:4),%d1   | ladder feedback
    tstl    sx_ok
    beqs    sv_flt_mid
    bsr     sx_swapf              | the side through the same ladder, with
    lea.l   sx_buf+32,%a1         | state of its own
    bsr     ladder_run
    bsr     sx_swapf
sv_flt_mid:
    lea.l   sampler_buf+32,%a1
    bsr     ladder_run
    braw    sv_nofilt

| ladder_run(a1 = a 2x buffer at +32; d0 = f, d1 = feedback, d4 = track): the
| 4-pole ladder over its 32 pairs, with the track's state in filt_y1..4. Keeps
| d0-d4 and a2-a3; clobbers d5-d7, a0, a1.
ladder_run:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d4/%a2-%a3,%sp@(4)
    movel   %d4,%d7               | track index, until d7 becomes the shift
    movel   %d7,%sp@
    lea.l   filt_y1,%a0
    movel   %a0@(0,%d7:l:4),%d2
    lea.l   filt_y2,%a0
    movel   %a0@(0,%d7:l:4),%d3
    lea.l   filt_y3,%a0
    movel   %a0@(0,%d7:l:4),%d4
    lea.l   filt_y4,%a0
    movel   %a0@(0,%d7:l:4),%d5
    lea.l   filt_mk,%a0
    lea.l   %a0@(0,%d7:l:4),%a0   | a0 = &makeup for this track, used in-loop
    lea.l   %a1@(256),%a3         | the end: 32 PAIRS. The buffer is a 2x
                                  | zero-order hold, so both halves of a pair
                                  | hold the same sample. Filtering once per
                                  | pair halves the cost; the decimator removes
                                  | the images either way.
    moveq   #12,%d7               | every >> 12 in one instruction; a2 carries
                                  | the cascade value (it was the stack)
    tstl    %d1                   | no resonance: the fast loop
    bnes    sv_flt
    movel   %a0@,%d6
    cmpil   #4096,%d6
    beqw    lr_fast
sv_flt:
    movel   %a1@,%d6              | x = buf >> 13, then resonance makeup
    asrl    #8,%d6
    asrl    #5,%d6
    mulsl   %a0@,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d5,%d6               | (fb * y4) >> 12
    asrl    %d7,%d6
    mulsl   %d1,%d6
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6               | ladder input = x - fb * y4
    cmpil   #262143,%d6           | bound the input: with makeup applied the
    bles    sv_in_hi              | worst-case (prev - y) * f would otherwise
    movel   #262143,%d6           | reach 2.7e9. Clamped it peaks at 1.24e9.
sv_in_hi:
    cmpil   #-262143,%d6
    bges    sv_in_lo
    movel   #-262143,%d6
sv_in_lo:
    movea.l %d6,%a2
    movel   %d2,%d6              | pole 1
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6               | prev - (Y >> 12)
    mulsl   %d0,%d6
    addl    %d6,%d2              | Y += f * (prev - y), accumulated in Q12
    cmpil   #536870912,%d2
    bles    sv_f1h
    movel   #536870912,%d2
sv_f1h:
    cmpil   #-536870912,%d2
    bges    sv_f1l
    movel   #-536870912,%d2
sv_f1l:
    movel   %d2,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d3,%d6              | pole 2
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6               | prev - (Y >> 12)
    mulsl   %d0,%d6
    addl    %d6,%d3              | Y += f * (prev - y), accumulated in Q12
    cmpil   #536870912,%d3
    bles    sv_f2h
    movel   #536870912,%d3
sv_f2h:
    cmpil   #-536870912,%d3
    bges    sv_f2l
    movel   #-536870912,%d3
sv_f2l:
    movel   %d3,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d4,%d6              | pole 3
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6               | prev - (Y >> 12)
    mulsl   %d0,%d6
    addl    %d6,%d4              | Y += f * (prev - y), accumulated in Q12
    cmpil   #536870912,%d4
    bles    sv_f3h
    movel   #536870912,%d4
sv_f3h:
    cmpil   #-536870912,%d4
    bges    sv_f3l
    movel   #-536870912,%d4
sv_f3l:
    movel   %d4,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d5,%d6              | pole 4
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6               | prev - (Y >> 12)
    mulsl   %d0,%d6
    addl    %d6,%d5              | Y += f * (prev - y), accumulated in Q12
    cmpil   #536870912,%d5
    bles    sv_f4h
    movel   #536870912,%d5
sv_f4h:
    cmpil   #-536870912,%d5
    bges    sv_f4l
    movel   #-536870912,%d5
sv_f4l:
    movel   %d5,%d6               | output = y4, at the buffer's full scale
    asrl    %d7,%d6
    cmpil   #131068,%d6
    bles    sv_flt_oh
    movel   #131068,%d6
sv_flt_oh:
    cmpil   #-131068,%d6
    bges    sv_flt_ol
    movel   #-131068,%d6
sv_flt_ol:
    asll    #8,%d6
    asll    #5,%d6
    movel   %d6,%a1@+
    movel   %d6,%a1@+
    cmpal   %a3,%a1
    bnew    sv_flt
lr_st:
    movel   %sp@,%d7
    lea.l   filt_y1,%a0
    movel   %d2,%a0@(0,%d7:l:4)
    lea.l   filt_y2,%a0
    movel   %d3,%a0@(0,%d7:l:4)
    lea.l   filt_y3,%a0
    movel   %d4,%a0@(0,%d7:l:4)
    lea.l   filt_y4,%a0
    movel   %d5,%a0@(0,%d7:l:4)
    moveml  %sp@(4),%d2-%d4/%a2-%a3
    lea.l   %sp@(24),%sp
    rts
| Resonance 0 (feedback 0, makeup exactly 4096): x = s >> 13 and nothing
| inside can reach a clamp - the buffer never passes half scale - so only
| the output clamp is kept. Bit-exact with sv_flt (modelled over every
| cutoff, full-scale squares included), as gflt_run's gr2_fast.
lr_fast:
    movel   %a1@,%d6
    asrl    #8,%d6
    asrl    #5,%d6
    movea.l %d6,%a2               | x
    movel   %d2,%d6               | pole 1
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6
    mulsl   %d0,%d6
    addl    %d6,%d2
    movel   %d2,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d3,%d6               | pole 2
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6
    mulsl   %d0,%d6
    addl    %d6,%d3
    movel   %d3,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d4,%d6               | pole 3
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6
    mulsl   %d0,%d6
    addl    %d6,%d4
    movel   %d4,%d6
    asrl    %d7,%d6
    movea.l %d6,%a2
    movel   %d5,%d6               | pole 4
    asrl    %d7,%d6
    negl    %d6
    addl    %a2,%d6
    mulsl   %d0,%d6
    addl    %d6,%d5
    movel   %d5,%d6               | output = y4, clamped as sv_flt does
    asrl    %d7,%d6
    cmpil   #131068,%d6
    bles    lrf_oh
    movel   #131068,%d6
lrf_oh:
    cmpil   #-131068,%d6
    bges    lrf_ol
    movel   #-131068,%d6
lrf_ol:
    asll    #8,%d6
    asll    #5,%d6
    movel   %d6,%a1@+
    movel   %d6,%a1@+
    cmpal   %a3,%a1
    bnew    lr_fast
    braw    lr_st

| ---- One shot's Lo-fi, Tape and Vinyl in stereo ----
| They are not linear - bits, a held value, saturation - so they run on real
| left and right, not on mid and side: sx_fx_r turns the two 2x buffers into
| L (sampler_buf) and R (sx_buf) and runs the effect on R with the right
| channel's own state (sx_lfh, sx_tpl, sx_vnl) in place of the track's;
| the caller then runs it on L as always, and sx_fx_back turns L/R back to
| mid/side. Lo-fi's hold phase is shared, so both channels hold on the same
| samples; Vinyl's crackle, its decay and its noise generator are replayed
| from the same start, so both channels get identical noise - centred, as
| from a mono pickup. d0 = the option (1..3), d4 = track. Keeps d0-d7.
sx_fx_r:
    lea.l   %sp@(-16),%sp
    moveml  %d0-%d3,%sp@
    bsr     sx_ms2lr
    lea.l   sx_buf+32,%a0
    movel   %a0,fx_buf
    movel   %d4,%d2
    lsll    #2,%d2                | the track's slot in the per-track arrays
    cmpil   #1,%d0
    bnes    sxf_2
    lea.l   lf_ph,%a0             | Lo-fi: same phase, R's own held value
    movel   %a0@(0,%d2:l),%d3
    lea.l   lf_hold,%a1
    movel   %a1@(0,%d2:l),%d1
    movel   %d1,sx_tmp
    lea.l   sx_lfh,%a1
    movel   %a1@(0,%d2:l),%d1
    lea.l   lf_hold,%a1
    movel   %d1,%a1@(0,%d2:l)
    movel   %d4,%d0
    bsr     lofi_apply
    lea.l   lf_hold,%a1
    movel   %a1@(0,%d2:l),%d1
    lea.l   sx_lfh,%a0
    movel   %d1,%a0@(0,%d2:l)
    movel   sx_tmp,%d1
    movel   %d1,%a1@(0,%d2:l)
    lea.l   lf_ph,%a0
    movel   %d3,%a0@(0,%d2:l)
    braw    sxf_out
sxf_2:
    cmpil   #2,%d0
    bnes    sxf_3
    lea.l   tp_lp,%a0             | Tape: R's own lowpass
    lea.l   sx_tpl,%a1
    bsr     sx_swap1
    movel   %d4,%d0
    bsr     tape_apply
    lea.l   tp_lp,%a0
    lea.l   sx_tpl,%a1
    bsr     sx_swap1
    bras    sxf_out
sxf_3:
    lea.l   vn_lp,%a0             | Vinyl: R's own lowpass, the same noise
    lea.l   sx_vnl,%a1
    bsr     sx_swap1
    lea.l   vn_cr,%a0
    movel   %a0@(0,%d2:l),%d3
    movel   vn_rng,%d1
    movel   %d1,sx_tmp
    movel   %d4,%d0
    bsr     vinyl_apply
    lea.l   vn_cr,%a0
    movel   %d3,%a0@(0,%d2:l)
    movel   sx_tmp,%d1
    movel   %d1,vn_rng
    lea.l   vn_lp,%a0
    lea.l   sx_vnl,%a1
    bsr     sx_swap1
sxf_out:
    lea.l   sampler_buf+32,%a0
    movel   %a0,fx_buf
    moveml  %sp@,%d0-%d3
    lea.l   %sp@(16),%sp
    rts
| swap a0[d2] with a1[d2] (d2 = track * 4). Keeps d0/d2-d7.
sx_swap1:
    movel   %a0@(0,%d2:l),%d1
    movel   %d1,sx_tmp2
    movel   %a1@(0,%d2:l),%d1
    movel   %d1,%a0@(0,%d2:l)
    movel   sx_tmp2,%d1
    movel   %d1,%a1@(0,%d2:l)
    rts
| mid/side <-> left/right over the two 2x buffers (64 longs each). Keeps d0-d7.
sx_ms2lr:
    lea.l   %sp@(-12),%sp
    moveml  %d0-%d2,%sp@
    lea.l   sampler_buf+32,%a0
    lea.l   sx_buf+32,%a1
    moveq   #31,%d2               | once per pair
sxm2_l:
    movel   %a0@,%d0              | mid
    movel   %a1@,%d1              | side
    addl    %d1,%d0
    satsl   %d0                   | L
    movel   %a0@,%d1
    subl    %a1@,%d1
    satsl   %d1                   | R
    movel   %d0,%a0@+
    movel   %d0,%a0@+
    movel   %d1,%a1@+
    movel   %d1,%a1@+
    subql   #1,%d2
    bpls    sxm2_l
    moveml  %sp@,%d0-%d2
    lea.l   %sp@(12),%sp
    rts
sx_fx_back:
    tstl    sx_ok
    beqs    sxb_out
    lea.l   %sp@(-12),%sp
    moveml  %d0-%d2,%sp@
    lea.l   sampler_buf+32,%a0
    lea.l   sx_buf+32,%a1
    moveq   #31,%d2               | once per pair
sxb_l:
    movel   %a0@,%d0              | L
    asrl    #1,%d0
    movel   %a1@,%d1              | R
    asrl    #1,%d1
    movel   %d0,%a0@
    addl    %d1,%a0@              | mid (L+R)/2
    movel   %a0@+,%a0@+
    subl    %d1,%d0
    movel   %d0,%a1@+             | side (L-R)/2
    movel   %d0,%a1@+
    subql   #1,%d2
    bpls    sxb_l
    moveml  %sp@,%d0-%d2
    lea.l   %sp@(12),%sp
sxb_out:
    rts

| swap the track's ladder state with the side's (d4 = track). Keeps d0-d7.
sx_swapf:
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    movel   %d4,%d2
    lsll    #2,%d2
    lea.l   filt_y1,%a0           | filt_y1..4 and sx_y1..4: four rows of six
    lea.l   sx_y1,%a1
    adda.l  %d2,%a0
    adda.l  %d2,%a1
    moveq   #3,%d2
sxs_l:
    movel   %a0@,%d3
    movel   %a1@,%a0@
    movel   %d3,%a1@
    lea.l   %a0@(24),%a0
    lea.l   %a1@(24),%a1
    subql   #1,%d2
    bpls    sxs_l
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    rts

sv_nofilt:


    movel   %d3,%sp@-
    pea     sampler_buf
    movel   %d2,%sp@-
    jsr     0x400a9f58            | 2x decimate into outBuf
    lea.l   %sp@(12),%sp
    tstl    sx_ok
    beqs    sv_nx1
    bsr     sx_dec                | the side, with a decimator state of its own
sv_nx1:

    movel   %d2,%sp@-
    jsr     0x400a9252
    addql   #4,%sp
    tstl    sle_run               | the slice editor tapping this track: Amp
    beqs    sv_ntap               | Decay held at full. 0x400a9252 makes the
    cmpl    sle_trk,%d4           | level (+0x230), which 0x400a9430 ramps the
    bnes    sv_ntap               | output to from +0x234 and the next block
    movea.l %d2,%a0               | decays from; 0x80000000 is its "instant"
    movel   #0x80000000,%d0       | full level (0x400a9264). The side's pass
    movel   %d0,%a0@(0x230)       | (sx_amp) takes the same.
    movel   %d0,%a0@(0x234)
sv_ntap:
    tstl    sx_ok
    beqs    sv_nx2
    bsr     sx_amp                | the side through the same gain stages
sv_nx2:
    movel   %d2,%sp@-
    movel   %d3,%sp@-
    jsr     0x400a9430
    lea.l   %sp@(8),%sp
    movel   %d2,%sp@-
    movel   %d3,%sp@-
    jsr     amp_hook              | NOT 0x400a967a directly: the six stock call
    lea.l   %sp@(8),%sp           | sites are retargeted to amp_hook, and ours
                                  | has to go the same way or the Sampler is the
                                  | one machine with no attack
    tstl    sx_ok                 | how loud the note still is, both planes
    beqs    sv_sn1
    movel   %d4,%d0
    lsll    #7,%d0
    addil   #sx_side,%d0
    movel   %d0,sil_b2
sv_sn1:
    movea.l %d3,%a0
    movel   %d4,%d0
    bsr     sil_note
    clrl    sil_b2
sv_tail:
    lea.l   sx_on,%a0             | the mixer: this track is stereo this block
    movel   sx_ok,%d0
    movel   %d0,%a0@(0,%d4:l:4)
    clrl    sx_ok                 | and nothing else reads it as this track's

    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(48),%sp         | matches the 48-byte prologue
    rts


| sv_idle_enter (d2 = voice, d4 = track): the first idle block. What the
| skipped stages would have let decay is cleared instead, so the next note
| starts from silence rather than from frozen state: both ladders, both
| decimator states, the grains, and Pluck's delay line (re-zeroed on its next
| use). Keeps d2-d7.
SV_IDLE_ENV = 0x00010000          | -90 dB of the envelope's 0x7fffffff
sv_idle_enter:
    lea.l   sv_idle,%a0
    tstb    %a0@(0,%d4:l)
    bnew    sie_out
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d4:l)
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    movel   %d4,%d1
    lsll    #2,%d1
    moveq   #0,%d0
    lea.l   filt_y1,%a0           | the ladders: filt_y1..4, sx_y1..4
    lea.l   sx_y1,%a1
    adda.l  %d1,%a0
    adda.l  %d1,%a1
    moveq   #3,%d3
sie_f:
    movel   %d0,%a0@
    movel   %d0,%a1@
    lea.l   %a0@(24),%a0
    lea.l   %a1@(24),%a1
    subql   #1,%d3
    bpls    sie_f
    movea.l %d2,%a0               | the decimator: the stock state...
    movea.l %a0@(0x318),%a0
    moveq   #11,%d3
sie_d:
    movel   %d0,%a0@+
    subql   #1,%d3
    bpls    sie_d
    movel   %d4,%d1               | ...and the side's
    lsll    #4,%d1
    movel   %d1,%d3
    addl    %d3,%d3
    addl    %d3,%d1
    lea.l   sx_dstate,%a0
    adda.l  %d1,%a0
    moveq   #11,%d3
sie_s:
    movel   %d0,%a0@+
    subql   #1,%d3
    bpls    sie_s
    movel   %d4,%d1               | the grains: none left
    movel   #GR_MAX*GR_STRIDE,%d3
    mulsl   %d3,%d1
    lea.l   gran_state,%a0
    adda.l  %d1,%a0
    moveq   #GR_MAX-1,%d3
sie_g:
    movel   %d0,%a0@(8)
    lea.l   %a0@(GR_STRIDE),%a0
    subql   #1,%d3
    bpls    sie_g
    lea.l   pk_clr,%a0            | Pluck: the lines cleared from here on, a
    clrl    %a0@(0,%d4:l:4)       | little each idle block (sv_pk_clear) -
    movel   %d4,%d1               | not all 2048 on the next strike
    lsll    #2,%d1
    lea.l   pk_lp,%a0             | and the strings' own state now
    clrl    %a0@(0,%d1:l)
    lea.l   pk_eleft,%a0
    clrl    %a0@(0,%d1:l)
    lea.l   sx_pklp,%a0
    clrl    %a0@(0,%d1:l)
    lea.l   sx_pkel,%a0
    clrl    %a0@(0,%d1:l)
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
sie_out:
    rts

| sv_pk_clear (d4 = track): 256 entries of each of the track's two Pluck lines
| per idle block, until all 2048 are clear. Keeps d2-d4.
sv_pk_clear:
    lea.l   pk_clr,%a0
    movel   %a0@(0,%d4:l:4),%d0
    cmpil   #2048,%d0
    bccs    spc_out
    movel   %d0,%d1
    addil   #256,%d1
    movel   %d1,%a0@(0,%d4:l:4)
    lsll    #2,%d0                | byte offset in the line
    movel   %d4,%d1
    moveq   #13,%d5
    lsll    %d5,%d1               | 8 KiB per track
    addl    %d0,%d1
    movea.l %d1,%a0
    movea.l %d1,%a1
    adda.l  #DLY_BASE,%a0
    adda.l  #DLY2_BASE,%a1
    moveq   #0,%d0
    movel   #255,%d1
spc_l:
    movel   %d0,%a0@+
    movel   %d0,%a1@+
    subql   #1,%d1
    bpls    spc_l
spc_out:
    rts

| sp_lock (d2 = track), at a new note: the sound this trig uses is where the
| render left it, 0x800015a0 + (147 + t) * 4 (0x40058a0a stores it with the
| trig, before the voices run). The track's own is the playing kit's +28 +
| t * 100; anything else is a sound lock - a pool sound. If that is a Sampler
| whose token names a resident sample, this note plays it (track_slot, and
| track_lock says so); the next unlocked note goes back to the pattern's
| sample. A locked sample not yet in RAM plays the pattern's own - the
| preloader loads every pool sound's sample. Keeps every register.
CUR_SNDS = 0x800017EC
sp_lock:
    lea.l   %sp@(-20),%sp
    moveml  %d0-%d1/%d3/%a0-%a1,%sp@
    moveq   #1,%d0
    cmpl    kit_ok,%d0
    bnew    spl_out
    movel   %d2,%d0
    lsll    #2,%d0
    addil   #CUR_SNDS,%d0
    movea.l %d0,%a0
    movel   %a0@,%d1              | the trig's sound
    cmpil   #0x40000000,%d1       | only a sound in RAM (0: none recorded)
    bcsw    spl_own
    cmpil   #0x48000000,%d1
    bccw    spl_own
    movel   CUR_KIT,%d0           | the track's own sound
    addil   #KIT_SND,%d0
    moveq   #SND_SIZE,%d3
    mulul   %d2,%d3
    addl    %d3,%d0
    cmpl    %d0,%d1
    beqs    spl_own
    movea.l %d1,%a0               | a sound lock: its sample, if resident
    bsr     tok_of
    tstl    %d0
    beqs    spl_own
    moveq   #0,%d3
spl_f:
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d3:l:4),%d0
    beqs    spl_hit
    addql   #1,%d3
    cmpil   #MAX_SLOT,%d3
    bcss    spl_f
    moveq   #1,%d0                | not in RAM: the preloader's job
    movel   %d0,pl_dirty
    bras    spl_own
spl_hit:
    lea.l   track_slot,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    lea.l   track_lock,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    bras    spl_out
spl_own:
    lea.l   track_lock,%a0        | the note before was locked: back to the
    tstb    %a0@(0,%d2:l)         | pattern's sample
    beqs    spl_out
    clrb    %a0@(0,%d2:l)
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    moveq   #-1,%d1
    tstl    %d0
    beqs    spl_set
    moveq   #0,%d3
spl_g:
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d3:l:4),%d0
    beqs    spl_gh
    addql   #1,%d3
    cmpil   #MAX_SLOT,%d3
    bcss    spl_g
    bras    spl_set
spl_gh:
    movel   %d3,%d1
spl_set:
    lea.l   track_slot,%a0
    movel   %d1,%a0@(0,%d2:l:4)
spl_out:
    moveml  %sp@,%d0-%d1/%d3/%a0-%a1
    lea.l   %sp@(20),%sp
    rts
track_lock:  .byte 0,0,0,0,0,0,0,0 | this note plays a sound lock's sample
    .balign 4

| sil_note(a0 = the track's 32 output samples, d0 = track): the run of blocks
| in a row whose peak, and sil_b2's if set (a stereo side), stays under
| SIL_LVL. voice_quiet ends a note on it: the voice's own envelope (stage 5
| at +0x298) only runs for voices with +0x48 set - for the rest 0x400a967a
| holds +0x294 at full and the stage stays 1 from the first trig on, which is
| every stock drum. Clobbers d0 and a0 only.
SIL_LVL   = 0x00010000            | under 2 LSB of 16-bit, as s << 15
SIL_STOCK = 375                   | 0.25 s of blocks
SIL_SMP   = 4500                  | 3 s: a take's silent gap is not its end
SIL_KILL  = 8                     | ~5 ms, after All Sound Off
| All Sound Off (0x40056004: a stop while stopped, CC 120, loads) sets this to
| 2; the next render block turns it to 1 and pulses voice+0x3c on every track
| with no trigs (0x400592fe), and it stays 1 until a trig is processed
| (0x4005919e).
SND_KILL  = 0x40a78e18
sil_note:
    lea.l   %sp@(-16),%sp
    moveml  %d1-%d3/%a1,%sp@
    movel   %d0,%d3
    moveq   #0,%d1
    bsr     sn_peak
    movel   sil_b2,%d0
    beqs    sn_one
    movea.l %d0,%a0
    bsr     sn_peak
sn_one:
    lea.l   sil_pk,%a1
    movel   %d1,%a1@(0,%d3:l:4)
    lea.l   sil_cnt,%a1
    lea.l   %a1@(0,%d3:l:4),%a1
    cmpil   #SIL_LVL,%d1
    bcss    sn_q
    clrl    %a1@
    bras    sn_out
sn_q:
    movel   %a1@,%d0
    cmpil   #0xffff,%d0
    bccs    sn_out
    addql   #1,%a1@
sn_out:
    moveml  %sp@,%d1-%d3/%a1
    lea.l   %sp@(16),%sp
    rts
sn_peak:                          | d1 = max(d1, |a0[0..31]|), unsigned
    moveq   #31,%d2
sn_l:
    movel   %a0@+,%d0
    bpls    sn_p
    negl    %d0
sn_p:
    cmpl    %d1,%d0
    blss    sn_n
    movel   %d0,%d1
sn_n:
    subql   #1,%d2
    bpls    sn_l
    rts
    .balign 4
sil_cnt:  .long 0,0,0,0,0,0,0     | per track: silent blocks in a row
sil_pk:   .long 0,0,0,0,0,0,0     | per track: the last live block's peak
sil_b2:   .long 0                 | sil_note: a second buffer, or 0

| voice_quiet (a0 = voice, d1 = track) -> d0 = 1 when rendering it would only
| produce silence: a Sampler muted by hand (mute_sil) has faded out - which
| also ends its note; MUT holds it at zero (rs_silence, faded to 0); All Sound
| Off reached it idle, or its output has been silent SIL_KILL blocks since; or, with no
| trig this block or the last, the track has not been triggered since power-on,
| or the mixer plays it at nothing - its six current gains (main L/R, both
| sends: 0x40a78c08/be8/bd0/bb8/b9c/b80, ramped by the stock mix each block)
| all under -90 dB, which is what a stock mute (FUNC + pad) or zero volume
| does - or the stock amp envelope has finished below -90 dB. Never for the
| source of a recording in progress. Keeps a0 and d1.
VQ_GAIN = 0x00010000              | -90 dB of the mixer's full-scale gain
voice_quiet:
    tstl    sle_run               | the slice editor tapping it: it plays on
    beqs    vq_tap                | to the sample's end
    cmpl    sle_trk,%d1
    beqw    vq_no
vq_tap:
    tstl    rs_state
    beqs    vq_ns
    cmpl    rs_src,%d1
    beqw    vq_no
vq_ns:
    movel   mute_sil,%d0          | muted by hand (a Sampler), and faded out:
    btst    %d1,%d0               | its note is over, so an unmute waits for
    beqs    vq_rs                 | the next trig
    lea.l   gv_gain,%a1
    tstl    %a1@(0,%d1:l:4)
    bnes    vq_rs
    lea.l   sil_cnt,%a1
    movel   #0xffff,%d0
    movel   %d0,%a1@(0,%d1:l:4)
    braw    vq_yes
vq_rs:
    movel   rs_silence,%d0
    btst    %d1,%d0
    beqs    vq_env
    lea.l   gv_gain,%a1
    tstl    %a1@(0,%d1:l:4)
    beqw    vq_yes
vq_env:
    tstl    %a0@(0x34)
    bnew    vq_trig
    tstl    %a0@(0x38)
    bnew    vq_trig
    tstl    %a0@(0x3c)
    beqs    vq_nop
    tstl    SND_KILL              | the other pulse, from All Sound Off (a
    beqw    vq_trig               | double stop, CC 120, a load) - every track
    lea.l   trig_seen,%a1         | gets it: an idle voice stays idle, a
    tstb    %a1@(0,%d1:l)         | sounding one renders it (not a new note)
    beqw    vq_yes
    bsr     vq_over
    tstl    %d0
    bnew    vq_yes
    braw    vq_no
vq_nop:
    lea.l   trig_seen,%a1         | never played since power-on: silent
    tstb    %a1@(0,%d1:l)
    beqw    vq_yes
    movel   %d2,%sp@-             | the mixer's gains for this track
    movel   %d1,%d2
    lsll    #2,%d2
    lea.l   vq_gains,%a1
vq_g:
    movel   %a1@+,%d0
    beqs    vq_gmute              | all six under the floor: muted
    movel   %a1,%sp@-
    movea.l %d0,%a1
    movel   %a1@(0,%d2:l),%d0
    movea.l %sp@+,%a1
    bpls    vq_gp
    negl    %d0
vq_gp:
    cmpil   #VQ_GAIN,%d0
    blss    vq_g
    movel   %sp@+,%d2             | audible: on to the envelope
    bras    vq_envf
vq_gmute:
    movel   %sp@+,%d2
    braw    vq_yes
vq_trig:
    lea.l   trig_seen,%a1
    moveq   #1,%d0
    moveb   %d0,%a1@(0,%d1:l)
    lea.l   sil_cnt,%a1           | a new note: the silent run starts again
    clrl    %a1@(0,%d1:l:4)
    braw    vq_no
vq_envf:
    moveq   #5,%d0
    cmpl    %a0@(0x298),%d0
    bnes    vq_sil
    movel   %a0@(0x294),%d0
    cmpil   #SV_IDLE_ENV,%d0
    bles    vq_yes
vq_sil:                           | the note's output has been silent long enough
    bsr     vq_over
    tstl    %d0
    bnes    vq_yes
vq_no:
    moveq   #0,%d0
    rts
vq_yes:
    moveq   #1,%d0
    rts
| vq_over (d1 = track) -> d0 = 1 once the track's silent run ends its note:
| SIL_KILL blocks after All Sound Off, else SIL_STOCK, or SIL_SMP for a
| Sampler. Clobbers a1.
vq_over:
    lea.l   sil_cnt,%a1
    movel   %a1@(0,%d1:l:4),%d0
    tstl    SND_KILL
    beqs    vqo_n
    cmpil   #SIL_KILL,%d0
    bccs    vqo_y
vqo_n:
    cmpil   #SIL_STOCK,%d0
    bcss    vqo_no
    lea.l   trk_mach,%a1
    moveq   #6,%d0
    cmpl    %a1@(0,%d1:l:4),%d0
    bnes    vqo_y
    lea.l   sil_cnt,%a1           | a Sampler: a take may hold a silent stretch
    movel   %a1@(0,%d1:l:4),%d0
    cmpil   #SIL_SMP,%d0
    bcss    vqo_no
vqo_y:
    moveq   #1,%d0
    rts
vqo_no:
    moveq   #0,%d0
    rts
    .balign 4
vq_gains:
    .long 0x40a78c08, 0x40a78be8, 0x40a78bd0, 0x40a78bb8, 0x40a78b9c, 0x40a78b80, 0
trig_seen:
    .byte 0,0,0,0,0,0,0,0
    .balign 2

| ---- the side's chain: sx_dec and sx_amp (d2 = voice, d4 = track) --------
| The stock decimator keeps its state in the 12 longs voice+0x318 points at;
| the side gets 12 of its own for the one call. Keeps d2-d7.
sx_dec:
    movea.l %d2,%a0
    lea.l   sx_dsv,%a1
    movel   %a0@(0x318),%a1@
    movel   %d4,%d0               | sx_dstate + track * 48
    lsll    #4,%d0
    movel   %d0,%d1
    addl    %d1,%d1
    addl    %d1,%d0
    addil   #sx_dstate,%d0
    movel   %d0,%a0@(0x318)
    movel   %d4,%d0
    lsll    #7,%d0
    addil   #sx_side,%d0
    movel   %d0,%sp@-             | out: the track's side channel
    pea     sx_buf
    movel   %d2,%sp@-
    jsr     0x400a9f58
    lea.l   %sp@(12),%sp
    movea.l %d2,%a0
    movel   sx_dsv,%d0
    movel   %d0,%a0@(0x318)
    rts

| The two gain stages ahead of the mixer are ramps driven by voice words they
| also advance: 0x400a9430 (+0x230 -> +0x234) and the envelope 0x400a967a
| (+0x28c..+0x298), plus our Attack's atk_gain. Saving them, running the side
| through 0x400a9430 and amp_hook, and putting them back gives the side the
| very gains the mid is about to get. amp_hook skips its capture and the stock
| filter for the side (sx_inside). Then the halving 0x400a7e24 gives outBuf,
| so the side's channel matches the mid's. Keeps d2-d4, d6, d7; uses d5.
sx_amp:
    movea.l %d2,%a0
    lea.l   sx_vsv,%a1
    movel   %a0@(0x230),%a1@+
    movel   %a0@(0x234),%a1@+
    movel   %a0@(0x28c),%a1@+
    movel   %a0@(0x290),%a1@+
    movel   %a0@(0x294),%a1@+
    movel   %a0@(0x298),%a1@+
    lea.l   atk_gain,%a0
    movel   %a0@(0,%d4:l:4),%a1@
    movel   %d4,%d5
    lsll    #7,%d5
    addil   #sx_side,%d5
    movel   %d2,%sp@-
    movel   %d5,%sp@-
    jsr     0x400a9430
    addql   #8,%sp
    moveq   #1,%d0
    movel   %d0,sx_inside
    movel   %d2,%sp@-
    movel   %d5,%sp@-
    jsr     amp_hook
    addql   #8,%sp
    clrl    sx_inside
    movea.l %d2,%a0
    lea.l   sx_vsv,%a1
    movel   %a1@+,%a0@(0x230)
    movel   %a1@+,%a0@(0x234)
    movel   %a1@+,%a0@(0x28c)
    movel   %a1@+,%a0@(0x290)
    movel   %a1@+,%a0@(0x294)
    movel   %a1@+,%a0@(0x298)
    lea.l   atk_gain,%a0
    movel   %a1@,%a0@(0,%d4:l:4)
    movea.l %d5,%a0               | the halving
    moveq   #31,%d1
sxa_h:
    movel   %a0@,%d0
    asrl    #1,%d0
    movel   %d0,%a0@+
    subql   #1,%d1
    bpls    sxa_h
    rts

| ================= granular mode =================
| gran_fill(track, whole, frac, pcmBase, count) fills sampler_buf's 32 pairs
| with up to GR_MAX Hann-windowed grains read from the track's sample.
|   - grains start every gr_int output samples (Density x Size), sample-
|     accurately: a grain due mid-block starts at that sample, not the next block
|   - each starts at gr_pos plus a random offset within gr_spray, centred
|   - each plays gr_len output samples at the note's step, so the note
|     transposes the grains without changing their length
| When every grain is busy a new one is dropped, which caps the cost: GR_MAX
| grains x 32 samples of uncached PCM reads per track per block.
| Nothing spawns until the track has been triggered once in this mode.
| Grain record, 24 bytes: +0 index, +4 fraction (Q0.32), +8 samples left
| (0 = free), +12 window phase (Q16 of 256 steps), +16 its step, +20 the
| sample in this block where it starts.
    GR_MAX    = 6
    GR_STRIDE = 28                | +24: this grain plays backwards
gran_fill:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@  | args from sp@(44): track, whole, frac,
                                  | pcmBase, count
    lea.l   gran_acc,%a1
    moveq   #31,%d0
    moveq   #0,%d1
gf_clr:
    movel   %d1,%a1@+
    subql   #1,%d0
    bpls    gf_clr
    movel   %sp@(44),%d2          | track
    movel   %d2,%d0
    movel   #GR_MAX*GR_STRIDE,%d1
    mulsl   %d1,%d0
    lea.l   gran_state,%a2
    addal   %d0,%a2               | this track's grains
    lea.l   gf_rev,%a0            | set below for a reversed stretch
    clrl    %a0@

    | ---- spawn ----
    lea.l   gr_trig,%a0
    tstb    %a0@(0,%d2:l)
    beqs    gf_notrig
    clrb    %a0@(0,%d2:l)
    lea.l   gr_on,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    lea.l   gr_cd,%a0
    clrl    %a0@(0,%d2:l:4)       | first grain on this block's first sample
    lea.l   gr_pos,%a0            | Freeze: Position as the note found it
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   gr_fpos,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   gr_ph,%a0             | stretch: the playhead back to the top -
    clrl    %a0@(0,%d2:l:4)       | or, playing in reverse, to the end
    lea.l   st_opt,%a1
    movel   %a1@(0,%d2:l:4),%d0
    cmpil   #1,%d0
    beqs    gf_trv
    cmpil   #3,%d0
    bnes    gf_trf
gf_trv:
    movel   %sp@(60),%d0
    subql   #1,%d0
    bmis    gf_trf
    movel   %d0,%a0@(0,%d2:l:4)
gf_trf:
    lea.l   gr_phf,%a0
    clrl    %a0@(0,%d2:l:4)
gf_notrig:
    lea.l   gr_on,%a0
    tstb    %a0@(0,%d2:l)
    beqw    gf_render

    | ---- stretch: grains come from a playhead moving at Speed ----
    | The playhead is an index plus a 16-bit fraction; it advances 32 * speed
    | per block (speed Q16, at most ~3.8x, so 32x fits easily) and wraps at the
    | end of the sample, so a long stretch keeps going. Grains spawned this
    | block start where it was at the top of the block.
    lea.l   loop_mode,%a0
    moveq   #4,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnew    gf_nostretch
    lea.l   gr_ph,%a0
    movel   %a0@(0,%d2:l:4),%d3
    cmpl    %sp@(60),%d3
    bcss    gf_ph_in
    moveq   #0,%d3                | a shorter sample was loaded under it
gf_ph_in:
    lea.l   gr_pos,%a1
    movel   %d3,%a1@(0,%d2:l:4)
    lea.l   gr_speed,%a1
    movel   %a1@(0,%d2:l:4),%d0
    lsll    #5,%d0                | 32 samples' worth, Q16
    | Options: 1 and 3 run backwards (and play each grain backwards, gf_rev),
    | 2 and 3 stop at the end - no more grains until the next note.
    lea.l   st_opt,%a1
    movel   %a1@(0,%d2:l:4),%d1
    cmpil   #1,%d1
    beqs    gf_rv
    cmpil   #3,%d1
    bnes    gf_fw
gf_rv:
    negl    %d0
    lea.l   gf_rev,%a1
    moveq   #1,%d4
    movel   %d4,%a1@
gf_fw:
    movel   %d0,%d1
    andil   #0xffff,%d1           | fraction
    swap    %d0
    extl    %d0                   | whole samples, signed
    lea.l   gr_phf,%a1
    addl    %a1@(0,%d2:l:4),%d1
    movel   %d1,%d4
    clrw    %d4
    swap    %d4                   | carry out of the fraction
    addl    %d4,%d0
    andil   #0xffff,%d1
    movel   %d1,%a1@(0,%d2:l:4)
    addl    %d0,%d3
    lea.l   st_opt,%a1
    movel   %a1@(0,%d2:l:4),%d1
    subql   #2,%d1                | 0 or 1: a one-pass option
    tstl    %d3
    bpls    gf_ph_hi
    cmpil   #1,%d1                | below the start
    blss    gf_ph_s0
    addl    %sp@(60),%d3          | wrap to the end
    bpls    gf_ph_ok
    moveq   #0,%d3
    bras    gf_ph_ok
gf_ph_s0:
    moveq   #0,%d3
    bras    gf_ph_stop
gf_ph_hi:
    cmpl    %sp@(60),%d3
    bcss    gf_ph_ok
    cmpil   #1,%d1                | past the end
    blss    gf_ph_s1
    subl    %sp@(60),%d3          | wrap
    cmpl    %sp@(60),%d3
    bcss    gf_ph_ok
    moveq   #0,%d3
    bras    gf_ph_ok
gf_ph_s1:
    movel   %sp@(60),%d3
    subql   #1,%d3
gf_ph_stop:
    lea.l   gr_on,%a1             | one pass done: grains already out finish
    clrb    %a1@(0,%d2:l)
gf_ph_ok:
    movel   %d3,%a0@(0,%d2:l:4)
gf_nostretch:
    lea.l   gr_len,%a0
    movel   %a0@(0,%d2:l:4),%d4   | d4 = grain length
    beqw    gf_render
    lea.l   gr_int,%a0
    movel   %a0@(0,%d2:l:4),%d5   | d5 = spacing, >= 1
    lea.l   gr_cd,%a0
    movel   %a0@(0,%d2:l:4),%d6   | d6 = samples until the next grain
gf_spawn:
    cmpil   #32,%d6
    bgew    gf_spawn_done
    movea.l %a2,%a3
    moveq   #GR_MAX-1,%d0
gf_find:
    tstl    %a3@(8)
    beqs    gf_free
    lea.l   %a3@(GR_STRIDE),%a3
    subql   #1,%d0
    bpls    gf_find
    braw    gf_next               | all busy: this grain is dropped
gf_free:
    lea.l   gr_pos,%a0            | Granular with Freeze: the position the note
    lea.l   gr_frz,%a1            | started at, whatever Position does since
    tstl    %a1@(0,%d2:l:4)
    beqs    gf_pz
    lea.l   loop_mode,%a1
    moveq   #3,%d7
    cmpl    %a1@(0,%d2:l:4),%d7
    bnes    gf_pz
    lea.l   gr_fpos,%a0
gf_pz:
    movel   %a0@(0,%d2:l:4),%d7
    lea.l   gr_spray,%a0
    movel   %a0@(0,%d2:l:4),%d3
    beqs    gf_nospray
    lea.l   gran_seed,%a0         | LCG, Numerical Recipes constants
    movel   %a0@,%d0
    movel   #1664525,%d1
    mulsl   %d1,%d0
    addil   #1013904223,%d0
    movel   %d0,%a0@
    swap    %d0
    andil   #0xffff,%d0           | r = 0..65535, the LCG's better half
    movel   %d3,%d1
    lsrl    #5,%d1                | range>>5 <= 65536, so r*that fits 32 bits
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #3,%d0                | offset = r * range / 65536, 0..range
    addl    %d0,%d7
    lsrl    #1,%d3
    subl    %d3,%d7               | centred on Position
    bpls    gf_nospray
    moveq   #0,%d7
gf_nospray:
    cmpl    %sp@(60),%d7
    bcss    gf_pos_ok
    movel   %sp@(60),%d7
    subql   #1,%d7                | never past the last sample
gf_pos_ok:
    movel   %d7,%a3@              | index
    clrl    %a3@(4)               | fraction
    movel   %d4,%a3@(8)           | samples left = length
    clrl    %a3@(12)              | window phase
    movel   #0x1000000,%d0        | 256 steps in Q16 across the whole grain
    divul   %d4,%d0
    movel   %d0,%a3@(16)
    movel   %d6,%a3@(20)          | starts at this sample of the block
    lea.l   gr_dir,%a0            | Direction: 0 forward, 1 reverse, 2 random
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #2,%d0
    bnes    gf_dset
    lea.l   gran_seed,%a0         | a coin toss, from the LCG's top bit
    movel   %a0@,%d0
    movel   #1664525,%d1
    mulsl   %d1,%d0
    addil   #1013904223,%d0
    movel   %d0,%a0@
    smi     %d0
    andil   #1,%d0
gf_dset:
    movel   %d0,%a3@(24)
gf_next:
    addl    %d5,%d6
    braw    gf_spawn
gf_spawn_done:
    subil   #32,%d6
    lea.l   gr_cd,%a0
    movel   %d6,%a0@(0,%d2:l:4)

    | ---- render every live grain into gran_acc ----
    | d2 index, d3 fraction, d4 samples left, d5 window phase, d6 count,
    | d7 step fraction, a0 PCM, a1 gran_acc cursor, a2 grain, a3 window,
    | a4 window step, a5 grains to go. d0/d1 scratch.
gf_render:
    | ---- stereo: the grains once over the side plane, then for real ----
    | sx_gpcm (from sampler_render) is the side plane's base. The records
    | the spawn left are copied and the copy rendered from the side into
    | sx_buf, with the step and the PCM base put back afterwards (a reversed
    | stretch negates the step in place); then the real records render from
    | the mid as always. Both channels hear identical grains.
    tstl    sx_gpcm
    beqs    gf_r0
    movea.l %a2,%a0
    lea.l   sx_grec,%a1
    moveq   #GR_MAX*GR_STRIDE/4-1,%d0
gf_cp:
    movel   %a0@+,%a1@+
    subql   #1,%d0
    bpls    gf_cp
    movel   %a2,sx_ga2
    lea.l   sx_grec,%a2
    movel   %sp@(48),%d0
    movel   %d0,sx_gwh
    movel   %sp@(56),%d0
    movel   %d0,sx_gmid
    movel   sx_gpcm,%d0
    movel   %d0,%sp@(56)
    clrl    sx_gpcm
    lea.l   sx_buf+32,%a0
    movel   %a0,gf_dst
gf_r0:
    movel   %sp@(44),%d0          | Shape: this track's window table
    lea.l   gr_shape,%a3
    movel   %a3@(0,%d0:l:4),%d0
    cmpil   #3,%d0
    blss    gf_shp
    moveq   #0,%d0
gf_shp:
    lea.l   gr_shapes,%a3
    movea.l %a3@(0,%d0:l:4),%a3
    movea.l %sp@(56),%a0
    movel   %sp@(52),%d7
    lea.l   gf_rev,%a1            | a reversed stretch plays grains backwards
    tstl    %a1@
    beqs    gf_fwd
    movel   %sp@(48),%d0
    negl    %d7
    negxl   %d0
    movel   %d0,%sp@(48)
gf_fwd:
    movea.l #GR_MAX,%a5
gf_g:
    movel   %a2@(8),%d4
    beqw    gf_gnext              | free
    movel   %a2@(20),%d0
    clrl    %a2@(20)              | later blocks start at sample 0
    lea.l   gran_acc,%a1
    lea.l   %a1@(0,%d0:l:4),%a1
    moveq   #32,%d6
    subl    %d0,%d6               | samples left in this block
    cmpl    %d4,%d6
    blss    gf_nok
    movel   %d4,%d6               | ...or in this grain, if fewer
gf_nok:
    subl    %d6,%d4
    movel   %d4,%a2@(8)
    movel   %a2@,%d2
    movel   %a2@(4),%d3
    movel   %a2@(12),%d5
    movea.l %a2@(16),%a4
    tstl    %a2@(24)              | a reversed grain: the step negated for it
    beqs    gf_s                  | alone, and back again after
    movel   %sp@(48),%d0
    negl    %d7
    negxl   %d0
    movel   %d0,%sp@(48)
gf_s:
    cmpl    %sp@(60),%d2
    bccs    gf_s_adv              | past the end of the sample: silent
    mvsw    %a0@(0,%d2:l:2),%d0
    movel   %d5,%d1
    swap    %d1
    andil   #0xff,%d1
    mvzw    %a3@(0,%d1:l:2),%d1
    mulsl   %d1,%d0
    asrl    #8,%d0
    asrl    #7,%d0                | sample * window, back to 16 bits
    addl    %d0,%a1@
gf_s_adv:
    addql   #4,%a1
    addl    %a4,%d5
    movel   %sp@(48),%d0          | whole step; the add below sets X for addx
    addl    %d7,%d3
    addxl   %d0,%d2
    subql   #1,%d6
    bnes    gf_s
    movel   %d2,%a2@
    movel   %d3,%a2@(4)
    movel   %d5,%a2@(12)
    tstl    %a2@(24)
    beqs    gf_gnext
    movel   %sp@(48),%d0
    negl    %d7
    negxl   %d0
    movel   %d0,%sp@(48)
gf_gnext:
    lea.l   %a2@(GR_STRIDE),%a2
    subql   #1,%a5
    movel   %a5,%d0
    bnew    gf_g

    | ---- to the buffer's format: clamp, <<15, each sample twice ----
    lea.l   gran_acc,%a0
    movea.l gf_dst,%a1            | sampler_buf+32, or sx_buf's for the side
    moveq   #31,%d1
gf_out:
    movel   %a0@+,%d0
    cmpil   #32767,%d0
    bles    gf_o1
    movel   #32767,%d0
gf_o1:
    cmpil   #-32768,%d0
    bges    gf_o2
    movel   #-32768,%d0
gf_o2:
    lsll    #8,%d0
    lsll    #7,%d0
    movel   %d0,%a1@+
    movel   %d0,%a1@+
    subql   #1,%d1
    bpls    gf_out
    movel   gf_dst,%d0            | the side just done: now the mid
    cmpil   #sampler_buf+32,%d0
    beqs    gf_done
    lea.l   sampler_buf+32,%a0
    movel   %a0,gf_dst
    movea.l sx_ga2,%a2
    movel   sx_gwh,%d0
    movel   %d0,%sp@(48)
    movel   sx_gmid,%d0
    movel   %d0,%sp@(56)
    lea.l   gran_acc,%a1
    moveq   #31,%d0
    moveq   #0,%d1
gf_clr2:
    movel   %d1,%a1@+
    subql   #1,%d0
    bpls    gf_clr2
    braw    gf_r0
gf_done:
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts

| ================= pluck (Karplus-Strong) =================
| pluck_fill(track, stepQ16, pcmBase, count) fills sampler_buf's 32 pairs from
| a string: a delay line one period long, fed back through a one-pole lowpass
| (Tone) at gain Feedback. A trigger "strikes" it by adding the sample, from
| the strike position, for the strike length - short for a pluck, long and it
| turns into a resonator the sample is played through.
| Period: N = 48000/261.63 Hz / step, Q8 - step 1.0 is note 60 - less the
| delay the lowpass itself adds (pcomp_tab), read with linear interpolation.
| Simulated in integer arithmetic: within ~3 cents of equal temperament over
| notes 36..72 and every Tone setting, and it always decays.
| Values in the line are 16-bit samples in Q4. Bounds: (y1-y0)*frac < 2^28,
| (d-lp)*a < 2^30, (lp>>4)*g < 2^30, all inside a signed 32-bit multiply.
| Delay lines: DLY_BASE + 8 KiB per track, 2048 longs, so the longest period
| is 2046 samples (~23 Hz). They are in the sample region, uncached: three
| accesses per output sample. That region is not cleared at boot, so each
| line is zeroed on its track's first use.
    PK_MASK = 2047
PK_A     = 0                      | locals: tone coefficient a, Q10
PK_G     = 4                      | feedback g, Q15
PK_CNT   = 8                      | sample length
PK_FRAC  = 12                     | period fraction, Q8
PK_EXC   = 16                     | exciter: 0 sample, 1 noise, 2 click, 3 drum
PK_RNG   = 20                     | noise state
PK_LCGA  = 24                     | the LCG multiplier: mulsl has no immediate
PK_DRUM  = 28                     | Drum: the loop's sign flips at random
PK_TRK   = 76                     | args, after 32 locals + 40 saved
PK_STEP  = 80
PK_BASE  = 84
PK_COUNT = 88
pluck_fill:
    lea.l   %sp@(-72),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@(32)
    movel   %sp@(PK_TRK),%d2
    movel   %d2,%d0
    moveq   #13,%d1
    lsll    %d1,%d0               | 8 KiB per track
    addl    pk_dbase,%d0          | DLY_BASE, or the side's DLY2_BASE
    movea.l %d0,%a2               | a2 = this track's delay line
    movea.l pk_initp,%a0          | pk_init, or the side's sx_pkinit
    tstb    %a0@(0,%d2:l)
    bnes    pf_inited
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d2:l)
    movea.l %a2,%a1
    movel   #PK_MASK,%d0
    moveq   #0,%d1
pf_clr:
    movel   %d1,%a1@+
    subql   #1,%d0
    bpls    pf_clr
    lea.l   pk_lp,%a0
    clrl    %a0@(0,%d2:l:4)
    lea.l   pk_wp,%a0
    clrl    %a0@(0,%d2:l:4)
    lea.l   pk_eleft,%a0
    clrl    %a0@(0,%d2:l:4)
pf_inited:
    lea.l   pk_trig,%a0           | strike: restart the exciter
    tstb    %a0@(0,%d2:l)
    beqs    pf_notrig
    clrb    %a0@(0,%d2:l)
    lea.l   pk_epos,%a0
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   pk_eidx,%a1
    movel   %d0,%a1@(0,%d2:l:4)
    lea.l   pk_elen,%a0
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   pk_exc,%a0            | Click: a single sample, whatever the length
    moveq   #2,%d1
    cmpl    %a0@(0,%d2:l:4),%d1
    bnes    pf_tlen
    moveq   #1,%d0
pf_tlen:
    lea.l   pk_eleft,%a1
    movel   %d0,%a1@(0,%d2:l:4)
pf_notrig:
    | ---- the period, from the note ----
    movel   %sp@(PK_STEP),%d1
    bnes    pf_st
    movel   #0x10000,%d1
pf_st:
    movel   #3078087446,%d0       | 48000/261.6255653 * 2^24
    divul   %d1,%d0               | N in Q8
    lea.l   pk_comp,%a0
    subl    %a0@(0,%d2:l:4),%d0   | less the lowpass's own delay
    bmis    pf_nlo
    cmpil   #512,%d0
    bges    pf_n1
pf_nlo:
    movel   #512,%d0              | at least 2 samples
pf_n1:
    cmpil   #523776,%d0
    bles    pf_n2
    movel   #523776,%d0           | at most 2046
pf_n2:
    movel   %d0,%d5
    lsrl    #8,%d5                | d5 = whole period
    andil   #0xff,%d0
    movel   %d0,%sp@(PK_FRAC)
    lea.l   pk_damp,%a0
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%sp@(PK_A)
    lea.l   pk_fb,%a0
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%sp@(PK_G)
    movel   %sp@(PK_COUNT),%sp@(PK_CNT)
    lea.l   pk_exc,%a0
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%sp@(PK_EXC)
    lea.l   pk_mode,%a0           | Drum is its own switch now, with any exciter
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%sp@(PK_DRUM)
    lea.l   pk_rng,%a0
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%sp@(PK_RNG)
    movel   #1664525,%d0
    movel   %d0,%sp@(PK_LCGA)
    movea.l %sp@(PK_BASE),%a0
    lea.l   pk_lp,%a1
    movel   %a1@(0,%d2:l:4),%d3   | d3 = lowpass state
    lea.l   pk_eleft,%a1
    movel   %a1@(0,%d2:l:4),%d4   | d4 = strike samples left
    lea.l   pk_eidx,%a1
    movel   %a1@(0,%d2:l:4),%d6   | d6 = strike read index
    lea.l   pk_wp,%a1
    movel   %a1@(0,%d2:l:4),%d7
    movea.l %d2,%a5               | a5 = track, for the write-back
    movel   %d7,%d2               | d2 = write position
    movea.l pk_dst,%a3            | sampler_buf+32, or sx_buf's for the side
    moveq   #32,%d7
pf_s:
    movel   %d2,%d0               | read one period back, interpolated
    subl    %d5,%d0
    andil   #PK_MASK,%d0
    movel   %a2@(0,%d0:l:4),%d1   | y0
    subql   #1,%d0
    andil   #PK_MASK,%d0
    movel   %a2@(0,%d0:l:4),%d0   | y1, one sample further back
    subl    %d1,%d0
    mulsl   %sp@(PK_FRAC),%d0
    asrl    #8,%d0
    addl    %d0,%d1               | d = y0 + (y1 - y0) * frac
    subl    %d3,%d1               | Tone: lp += (d - lp) * a
    mulsl   %sp@(PK_A),%d1
    asrl    #8,%d1
    asrl    #2,%d1
    addl    %d1,%d3
    movel   %d3,%d1               | Feedback: y = lp * g
    asrl    #4,%d1
    mulsl   %sp@(PK_G),%d1
    asrl    #8,%d1
    asrl    #3,%d1
    | Drum: Karplus-Strong's drum variant - the loop's sign flips at random,
    | half the time, which turns the pitched string into a noisy drum body
    tstl    %sp@(PK_DRUM)
    beqs    pf_nodrum
    movel   %sp@(PK_RNG),%d0
    mulsl   %sp@(PK_LCGA),%d0
    addil   #1013904223,%d0
    movel   %d0,%sp@(PK_RNG)
    bpls    pf_nodrum
    negl    %d1
pf_nodrum:
    tstl    %d4                   | strike: add the exciter, at half gain
    beqw    pf_noexc
    subql   #1,%d4
    movel   %sp@(PK_EXC),%d0
    bnes    pf_exc_gen
    cmpl    %sp@(PK_CNT),%d6
    bccs    pf_exc_adv            | past the end of the sample
    mvsw    %a0@(0,%d6:l:2),%d0
    asll    #3,%d0
    addl    %d0,%d1
    bras    pf_exc_adv
pf_exc_gen:
    cmpil   #2,%d0
    bnes    pf_exc_noise
    addil   #262136,%d1           | Click: one full-scale sample (32767 << 3)
    bras    pf_exc_adv
pf_exc_noise:
    movel   %sp@(PK_RNG),%d0      | Noise (and Drum's strike): white noise
    mulsl   %sp@(PK_LCGA),%d0
    addil   #1013904223,%d0
    movel   %d0,%sp@(PK_RNG)
    asrl    #8,%d0
    asrl    #5,%d0                | full-scale 16-bit, << 3 as a sample is
    addl    %d0,%d1
pf_exc_adv:
    addql   #1,%d6
pf_noexc:
    cmpil   #524272,%d1           | +-32767 in Q4
    bles    pf_c1
    movel   #524272,%d1
pf_c1:
    cmpil   #-524272,%d1
    bges    pf_c2
    movel   #-524272,%d1
pf_c2:
    movel   %d1,%a2@(0,%d2:l:4)
    addql   #1,%d2
    andil   #PK_MASK,%d2
    asrl    #4,%d1                | to the buffer's format: sample << 15
    lsll    #8,%d1
    lsll    #7,%d1
    movel   %d1,%a3@+
    movel   %d1,%a3@+
    subql   #1,%d7
    bnew    pf_s
    movel   %a5,%d0               | track
    lea.l   pk_wp,%a1
    movel   %d2,%a1@(0,%d0:l:4)
    lea.l   pk_lp,%a1
    movel   %d3,%a1@(0,%d0:l:4)
    lea.l   pk_eleft,%a1
    movel   %d4,%a1@(0,%d0:l:4)
    lea.l   pk_eidx,%a1
    movel   %d6,%a1@(0,%d0:l:4)
    movel   %sp@(PK_RNG),%d1
    lea.l   pk_rng,%a1
    movel   %d1,%a1@(0,%d0:l:4)
    moveml  %sp@(32),%d2-%d7/%a2-%a5
    lea.l   %sp@(72),%sp
    rts

| ---- Pluck and Wavetable in stereo: the side through the same code ----
| pluck_st / wave_st (track, step, base, count) replace the calls to
| pluck_fill / wave_fill. With no side (sx_side_off = 0) they are those. With
| one, the side goes first into sx_buf: Pluck strikes a second string of its
| own - the track's state swapped for the side's (sx_pk*), the second bank of
| lines, the same trigger and the same noise sequence; Wavetable reads the
| side's frames with the phases and trigger saved and put back. Then the mid,
| exactly as in mono.
pluck_st:
    tstl    sx_side_off
    bnes    pst_go
    jmp     pluck_fill
pst_go:
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    movel   %sp@(12),%d2
    lsll    #2,%d2                | track * 4, for sx_swap1
    bsr     pst_swap
    movel   %sp@(12),%d0
    lea.l   pk_trig,%a0
    moveb   %a0@(0,%d0:l),%d3     | the trigger: both strings are struck
    lea.l   pk_rng,%a0
    movel   %a0@(0,%d2:l),%d1
    movel   %d1,sx_tmp2           | the noise: the same sequence for both
    lea.l   sx_pkinit,%a0
    movel   %a0,pk_initp
    movel   #DLY2_BASE,%d0
    movel   %d0,pk_dbase
    lea.l   sx_buf+32,%a0
    movel   %a0,pk_dst
    movel   %sp@(24),%sp@-        | count
    movel   %sp@(24),%d0
    addl    sx_side_off,%d0
    movel   %d0,%sp@-             | the side plane
    movel   %sp@(24),%sp@-        | step
    movel   %sp@(24),%sp@-        | track
    jsr     pluck_fill
    lea.l   %sp@(16),%sp
    lea.l   pk_init,%a0
    movel   %a0,pk_initp
    movel   #DLY_BASE,%d0
    movel   %d0,pk_dbase
    lea.l   sampler_buf+32,%a0
    movel   %a0,pk_dst
    movel   sx_tmp2,%d1
    lea.l   pk_rng,%a0
    movel   %d1,%a0@(0,%d2:l)
    movel   %sp@(12),%d0
    lea.l   pk_trig,%a0
    moveb   %d3,%a0@(0,%d0:l)
    bsr     pst_swap
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    jsr     pluck_fill
    lea.l   %sp@(16),%sp
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    rts
pst_swap:                         | the string's state <-> the side's
    lea.l   pk_lp,%a0
    lea.l   sx_pklp,%a1
    bsr     sx_swap1
    lea.l   pk_wp,%a0
    lea.l   sx_pkwp,%a1
    bsr     sx_swap1
    lea.l   pk_eleft,%a0
    lea.l   sx_pkel,%a1
    bsr     sx_swap1
    lea.l   pk_eidx,%a0
    lea.l   sx_pkei,%a1
    bsr     sx_swap1
    rts

wave_st:
    tstl    sx_side_off
    bnes    wst_go
    jmp     wave_fill
wst_go:
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    movel   %sp@(12),%d2          | track
    movel   %d2,%d0               | its three phases, saved
    movel   %d0,%d1
    addl    %d0,%d0
    addl    %d1,%d0
    lsll    #2,%d0
    lea.l   wv_ph,%a0
    adda.l  %d0,%a0
    lea.l   sx_wvph,%a1
    movel   %a0@+,%a1@+
    movel   %a0@+,%a1@+
    movel   %a0@,%a1@
    lea.l   wv_trig,%a0
    moveb   %a0@(0,%d2:l),%d3
    lea.l   sx_buf+32,%a0
    movel   %a0,wf_dst
    movel   %sp@(24),%sp@-        | count
    movel   %sp@(24),%d0
    addl    sx_side_off,%d0
    movel   %d0,%sp@-             | the side plane
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    jsr     wave_fill
    lea.l   %sp@(16),%sp
    lea.l   sampler_buf+32,%a0
    movel   %a0,wf_dst
    movel   %d2,%d0               | the phases and trigger back
    movel   %d0,%d1
    addl    %d0,%d0
    addl    %d1,%d0
    lsll    #2,%d0
    lea.l   wv_ph,%a0
    adda.l  %d0,%a0
    lea.l   sx_wvph,%a1
    movel   %a1@+,%a0@+
    movel   %a1@+,%a0@+
    movel   %a1@,%a0@
    lea.l   wv_trig,%a0
    moveb   %d3,%a0@(0,%d2:l)
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    movel   %sp@(24),%sp@-
    jsr     wave_fill
    lea.l   %sp@(16),%sp
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    rts

| ================= wavetable =================
| wave_fill(track, stepQ16, pcmBase, count) plays the sample as a wavetable:
| frames of 2^shift samples, one frame per cycle, at the note's pitch (step 1.0
| = note 60 = 261.63 Hz). Each output sample reads two adjacent frames at the
| same point, each interpolated linearly within the frame, and morphs between
| them by wv_m8 - Position picks the pair, Smooth shapes the morph. Detune adds
| two unison voices a Q16 ratio above and below; the centre then counts double
| and the sum is /4, so the peak level is unchanged. Four uncached reads per
| voice per sample: 4 without Detune, 12 with it.
| Phase is Q32 of one cycle; the step per sample is step * 2^32 * 261.63 /
| 48000 / 65536 = step * 357.2031 (357 + 52/256, 0.02 cents off).
WV_MASK  = 0                      | locals, reached through a5 from wv_voice
WV_M8    = 4                      | morph, Q8
WV_VW    = 8                      | this voice's weight, as a shift
WV_F     = 12                     | frame length
WV_DELTA = 16                     | unison step offset
WV_OSH   = 20                     | output shift
WV_TRK   = 68                     | args, after 24 locals + 40 saved
WV_STEP  = 72
WV_BASE  = 76
wave_fill:
    lea.l   %sp@(-64),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@(24)
    movea.l %sp,%a5
    movel   %sp@(WV_TRK),%d5      | d5 = track, for the whole routine
    lea.l   wv_shift,%a0
    movel   %a0@(0,%d5:l:4),%d0
    beqw    wf_silent
    moveq   #1,%d1
    lsll    %d0,%d1
    movel   %d1,%a5@(WV_F)
    subql   #1,%d1
    movel   %d1,%a5@(WV_MASK)
    lea.l   wv_fa,%a0             | the two frames, as byte addresses
    movel   %a0@(0,%d5:l:4),%d1
    lsll    %d0,%d1
    addl    %d1,%d1
    addl    %sp@(WV_BASE),%d1
    movea.l %d1,%a4               | parked: wv_voice uses a0/a1, not a4 until
    lea.l   wv_fb,%a0             | it starts
    movel   %a0@(0,%d5:l:4),%d1
    lsll    %d0,%d1
    addl    %d1,%d1
    addl    %sp@(WV_BASE),%d1
    movea.l %d1,%a1
    movea.l %a4,%a0
    lea.l   wv_m8,%a2
    movel   %a2@(0,%d5:l:4),%d0
    movel   %d0,%a5@(WV_M8)
    movel   %d5,%d0               | a2 = this track's three phases
    movel   %d0,%d1
    addl    %d0,%d0
    addl    %d1,%d0
    lsll    #2,%d0
    lea.l   wv_ph,%a2
    addal   %d0,%a2
    lea.l   wv_trig,%a3
    tstb    %a3@(0,%d5:l)
    beqs    wf_notrig
    clrb    %a3@(0,%d5:l)
    clrl    %a2@                  | a note restarts the centre voice at zero,
    movel   #0x55555555,%d0       | and the unison voices a third and two thirds
    movel   %d0,%a2@(4)           | round, so they do not start in phase
    movel   #0xAAAAAAAA,%d0
    movel   %d0,%a2@(8)
wf_notrig:
    movel   %sp@(WV_STEP),%d1
    bnes    wf_st
    movel   #0x10000,%d1
wf_st:
    movel   %d1,%d3
    movel   #357,%d0
    mulul   %d0,%d3
    moveq   #52,%d0
    mulul   %d0,%d1
    lsrl    #8,%d1
    addl    %d1,%d3               | phase step per output sample
    lsrl    #1,%d3                | 2x oversampled: 64 real samples per block,
                                  | half the step each; the stock decimator's
                                  | filter then removes what lands between 24
                                  | and 48 kHz instead of it folding back down.
                                  | Losing the step's bottom bit is 0.0003
                                  | cents at middle C.
    lea.l   gran_acc,%a3
    moveq   #63,%d0
    moveq   #0,%d1
wf_clr:
    movel   %d1,%a3@+
    subql   #1,%d0
    bpls    wf_clr
    lea.l   wv_det,%a3
    movel   %a3@(0,%d5:l:4),%d1
    beqs    wf_mono
    movel   %d3,%d0               | delta = step * ratio, in two halves so the
    lsrl    #8,%d0                | product stays inside 32 bits
    mulul   %d1,%d0
    lsrl    #8,%d0
    movel   %d0,%a5@(WV_DELTA)
    moveq   #1,%d0
    movel   %d0,%a5@(WV_VW)       | centre counts double
    moveq   #2,%d0
    movel   %d0,%a5@(WV_OSH)
    movel   %a2@,%d2
    bsr     wv_voice
    movel   %d2,%a2@
    clrl    %a5@(WV_VW)
    movel   %a2@(4),%d2
    movel   %d3,%sp@-
    addl    %a5@(WV_DELTA),%d3
    bsr     wv_voice
    movel   %sp@+,%d3
    movel   %d2,%a2@(4)
    movel   %a2@(8),%d2
    subl    %a5@(WV_DELTA),%d3
    bsr     wv_voice
    movel   %d2,%a2@(8)
    bras    wf_out
wf_mono:
    moveq   #1,%d0
    movel   %d0,%a5@(WV_VW)
    movel   %d0,%a5@(WV_OSH)      | 2c >> 1 = c
    movel   %a2@,%d2
    bsr     wv_voice
    movel   %d2,%a2@
wf_out:
    movel   %a5@(WV_OSH),%d2
    lea.l   gran_acc,%a0
    movea.l wf_dst,%a1            | sampler_buf+32, or sx_buf's for the side
    moveq   #63,%d1               | 64 distinct samples, each written once
wf_o:
    movel   %a0@+,%d0
    asrl    %d2,%d0
    cmpil   #32767,%d0
    bles    wf_o1
    movel   #32767,%d0
wf_o1:
    cmpil   #-32768,%d0
    bges    wf_o2
    movel   #-32768,%d0
wf_o2:
    lsll    #8,%d0
    lsll    #7,%d0
    movel   %d0,%a1@+
    subql   #1,%d1
    bpls    wf_o
    bras    wf_done
wf_silent:
    movea.l wf_dst,%a1
    moveq   #63,%d1
    moveq   #0,%d0
wf_z:
    movel   %d0,%a1@+
    subql   #1,%d1
    bpls    wf_z
wf_done:
    moveml  %sp@(24),%d2-%d7/%a2-%a5
    lea.l   %sp@(64),%sp
    rts

| One voice into gran_acc: d2 = phase (updated), d3 = its step, a0/a1 = frames
| A and B, a5 = wave_fill's locals. Clobbers d0/d1/d4/d6/d7/a3/a4.
wv_voice:
    lea.l   gran_acc,%a3
    movea.l #64,%a4               | the 2x rate: see wf_st
wv_s:
    movel   %d2,%d0
    clrw    %d0
    swap    %d0                   | cycle position, Q16
    mulul   %a5@(WV_F),%d0        | -> sample position in the frame, Q16
    movel   %d0,%d4
    clrw    %d4
    swap    %d4                   | index
    movel   %d0,%d6
    lsrl    #8,%d6
    andil   #0xff,%d6             | fraction, Q8
    movel   %d4,%d1
    addql   #1,%d1
    andl    %a5@(WV_MASK),%d1     | next index, wrapping inside the frame
    mvsw    %a0@(0,%d4:l:2),%d7
    mvsw    %a0@(0,%d1:l:2),%d0
    subl    %d7,%d0
    mulsl   %d6,%d0
    asrl    #8,%d0
    addl    %d0,%d7               | frame A, interpolated
    mvsw    %a1@(0,%d1:l:2),%d1
    mvsw    %a1@(0,%d4:l:2),%d0
    subl    %d0,%d1
    mulsl   %d6,%d1
    asrl    #8,%d1
    addl    %d1,%d0               | frame B, interpolated
    subl    %d7,%d0
    mulsl   %a5@(WV_M8),%d0
    asrl    #8,%d0
    addl    %d7,%d0               | morphed
    movel   %a5@(WV_VW),%d1
    asll    %d1,%d0
    addl    %d0,%a3@+
    addl    %d3,%d2
    subql   #1,%a4
    movel   %a4,%d0
    bnes    wv_s
    rts

| ---- hand out the Sampler's private descriptor for index 7 ----
| Slot 7 does not exist (the table has seven slots, 0..6, and slot 6 is Chord's),
| so index 7 is answered with our own descriptor rather than an out-of-range slot.
descr_hook:
    | Registers are saved on the STACK, not in static slots. The old version
    | parked d0/d1/a0/a1 in globals (dh_sd0..dh_sa1); descriptor lookups happen
    | from more than one context, so a second entry overwrote the first one's
    | saved values and the first caller resumed with FOREIGN a0/a1 - then wrote
    | through them. ColdFire write faults are imprecise, which is why the
    | reported PC landed in sampler_pre (the hottest code) rather than here.
    lea.l   %sp@(-16),%sp
    moveml  %d0-%d1/%a0-%a1,%sp@
    movel   %sp@(20),%d0
    | choose which label set the table should carry for this page
    moveq   #0,%d1
    cmpil   #7,%d0
    bnes    ns_go
    moveq   #1,%d1
ns_go:
    bsr     apply_names
ns_done:
    moveml  %sp@,%d0-%d1/%a0-%a1
    lea.l   %sp@(16),%sp
    movel   %sp@(4),%d0
    cmpil   #7,%d0
    bnes    dh_pass
    | sampler_descr is built by sampler_pre on the AUDIO thread. Until that has
    | happened it is 76 zero bytes, and the caller dereferences fields out of
    | it - so until then let the stock path answer. movea does not touch the
    | flags, so the tstb result survives the restore of a0.
    movel   %a0,%sp@-
    lea.l   descr_done,%a0
    tstb    %a0@
    movea.l %sp@+,%a0
    beqs    dh_pass
    | While the modifier is held, hand out the variant whose Decay position carries
    | Attack instead. The dial then edits Attack directly and Decay is never
    | written, so there is nothing to put back - changing it and restoring it
    | never stuck, because something else owns that word between our writes.
    | mod_held is refreshed by atk_watch, which tick_hook drives on key input,
    | so the swap follows the button within a frame.
    movel   %a0,%sp@-
    lea.l   mod_held,%a0
    tstl    %a0@
    movea.l %sp@+,%a0
    bnes    dh_atk
    movel   #sampler_descr,%d0
    rts
dh_atk:
    movel   #sampler_descr_atk,%d0
    rts
dh_pass:
    | Modifier held: the Decay dial carries Attack on EVERY machine, not just
    | ours. Take that machine's own descriptor, copy it and swap position 1 -
    | the stock table is never written, so letting go restores it for free.
    movel   %a0,%sp@-
    lea.l   mod_held,%a0
    tstl    %a0@
    movea.l %sp@+,%a0
    beqs    dh_stock
    movel   %d1,%sp@-
    movel   %a0,%sp@-
    movel   %a1,%sp@-
    movel   %sp@(16),%sp@-        | the descriptor index we were asked for
    jsr     table_lookup_a_fixed
    addql   #4,%sp
    movea.l %d0,%a0
    lea.l   other_descr,%a1
    moveq   #18,%d1               | 19 longs = 76 bytes
dh_cp:
    movel   %a0@+,%a1@+
    subql   #1,%d1
    bpls    dh_cp
    lea.l   other_descr,%a0
    moveq   #0x0d,%d1
    movel   %d1,%a0@(12)          | position 1: Attack, not that machine's Decay
    moveq   #0x0c,%d1
    movel   %d1,%a0@(24)          | position 4: Filter, not Sweep
    moveq   #0x0b,%d1
    movel   %d1,%a0@(28)          | position 5: Resonance, not Contour
    movel   #other_descr,%d0
    movea.l %sp@+,%a1
    movea.l %sp@+,%a0
    movel   %sp@+,%d1
    rts
dh_stock:
    jmp     table_lookup_a_fixed

| ---- make the Sampler's four machine params visible as LFO destinations ----
| The LFO destination list is BUILT, not tabulated. 0x40061866 walks trackData
| offset indices 0..32 calling paramIdFor(0x4005a692) and blanks every slot
| that answers 0; the destination the user picks IS that offset index, so the
| modulation lands on trackData+2*idx with no further mapping.
|
| paramIdFor(offsetIdx, group) resolves the four machine slots (offsetIdx
| 11..14 = trackData +22/+24/+26/+28) out of a 6x8 array at 0x40a79418 that an
| init pass at 0x4005a274 fills from param_table's long[0] (the machine group).
| No entry carries group 6, so the array has no row for us, and the lookup's
| own `5 >= group` bound returned 0 for every one of our params - which is
| exactly why a Sampler track offered only the common destinations.
|
| Rather than grow that array into whatever follows it in BSS, intercept the
| bound check and answer group 6 from our own table. Entered in place of
|     moveq #5,%d1 ; cmpl %d2,%d1 ; bccs 0x4005a6dc
| with %a2 = offsetIdx and %d2 = group, and with %d2/%a2 already saved on the
| stack by the function's prologue. Both exits below restore them.
sampler_lfo_gate:
    cmpil   #5,%d2
    blss    lg_stock              | groups 0..5 keep the stock array
    cmpil   #6,%d2
    bnes    lg_none               | -1 (unclamped) and everything else: none
    movel   %a2,%d0
    subil   #11,%d0               | offsetIdx 11..14 -> 0..3
    cmpil   #3,%d0
    bhis    lg_none               | unsigned, so <11 wraps high and is rejected
    lea.l   sampler_lfo_ids,%a0
    movel   %a0@(0,%d0:l:4),%d0
    jmp     0x4005a6fc            | pops %d2/%a2, returns %d0
lg_stock:
    jmp     0x4005a6dc
lg_none:
    jmp     0x4005a6ac            | clrl %d0, then the same epilogue

| ---- and the same for Amp Decay, which takes a different branch -----------
| offsetIdx 18 (trackData +36) is Amp Decay, and paramIdFor answers it from
| TBL_A[machine*32] - row 0 of each machine, holding that machine's own Amp
| Decay duplicate (0x32 Kick, 0x37 Snare ... 0x4b Chord). That branch has NO
| machine bound at all, so machine 6 indexed 0x40a79418 + 192 = 0x40a794d8,
| one row past the end of the 6x32 array the init pass fills and memsets. It
| read whatever follows in BSS, which is why every stock machine offered Decay
| as an LFO destination and the Sampler did not.
|
| We answer 0x4b, CHORD's Amp Decay duplicate, and our descriptor carries the
| same id at position 1 - the LED painter searches the descriptor for whatever
| id paramIdFor returns, so the two must agree. It has to be a per-machine
| duplicate rather than the common 0x18: the destination list is sorted on
| long[10], which is 30 for every machine's own Amp Decay and 70 for the common
| one, and 70 put Decay after the machine params. Every variant has
| long[1]*2 = 36, so the modulation lands on the same word regardless.
|
| Entered in place of the six bytes at 0x4005a6b6
|     lsll #5,%d2 ; lea 0x40a79418,%a0
| which this replays for machines 0..5. The eight bytes behind it are orphaned
| but unreachable: nothing branches between 0x4005a6b6 and 0x4005a6c4.
sampler_amp_gate:
    cmpil   #6,%d2
    bnes    sag_stock
    moveq   #0x4b,%d0
    jmp     0x4005a6fc            | pops %d2/%a2, returns %d0
sag_stock:
    lsll    #5,%d2
    lea.l   0x40a79418,%a0
    movel   %a0@(0,%d2:l),%d0
    jmp     0x4005a6fc

| The ids our descriptor hands out, in trackData order. These must stay in step
| with the descriptor build in sampler_pre: offsetIdx 11..14 are +22/+24/+26/+28
| and param_table's long[1]*2 for each id below is exactly that offset, so the
| LFO writes the same words the render reads. descr_hook's name_swap renames
| these four entries while the Sampler page is up, so the list shows our labels.
    .align 2
sampler_lfo_ids:
    .long   0x2e                  | +22  Start   (stock Kick Color)
    .long   0x3e                  | +24  End     (stock Perc Shape)
    .long   0x49                  | +26  Flt     (stock Chord Sweep)
    .long   0x4a                  | +28  Res     (stock Chord Contour)

| ---- hand the Sampler's own descriptor to the per-machine descriptor lookup --
| 0x4004df76 (Phase 1 redirects it to table_lookup_b_fixed) answers "descriptor
| for raw machine index N". It has exactly three callers, and all three do the
| same thing: copy the descriptor's id array from +8 and linear-search it for a
| param id, turning the position they land on into a dial LED.
|   0x400261aa  currently-selected parameter
|   0x4002ae0e  LFO destination        (PadMenuView)
|   0x4002affe  dial -> parameter id   (PadMenuView)
| Phase 1 aliases machine 6 to raw index 0 = Kick, so every one of them searched
| Kick's ids 0x2a/0x18/0x2e/0x2f/0x30/0x31. Ours are 0x2a/0x18/0x2e/0x3e/0x49/
| 0x4a, so only Pitch, Amp Decay and Start were ever found - End, Flt and Res
| matched nothing and lit no LED.
|
| Patching the lookup itself rather than one call site: all three consumers want
| the same answer, and a first attempt that redirected only 0x4002ae90 changed
| nothing on hardware, so the LED being complained about is painted by one of
| the other two.
| ===================== Track + Preset -> loop / one-shot ==================
| Wraps 0x4007240c, the KeyEvent key-code accessor: a three-instruction leaf
|     moveal %sp@(4),%a0 ; movel %a0@(12),%d0 ; rts
| that every consumer of a key event calls, whatever view is on screen. That
| makes it the one place a chord can be seen without knowing which view owns
| the buttons - and the event pointer is right there, so the flags word at +16
| is available too.
|
| Key codes were measured on hardware with a probe build: Track = 2,
| Preset = 5 (the menu keys are 1 and 15, and 16..31 are the trig keys).
| Flags bit 0 is "down" and bit 3 is "auto-repeat": the stock dispatcher gates
| on 0x400724a0, which is exactly `bit0 && !bit3`, before switching on a code.
|
| d0/d1/a0/a1 are caller-saved, so d1/a1 are free; d0 is the accessor's result
| and is preserved across the toggle.
KEY_TRACK  = 2
KEY_PRESET = 5
KEY_PATTERN= 3         | measured: Track 2, Pattern 3, Preset 5, FUNC 1, PAGE 15
KEY_OPTS   = 6         | measured: the options button (samplerEU's probe)
KEY_RESAMPLE = 9       | measured: samplerFG's probe; the user's pick
KEY_RETRIG = 4         | measured: samplerHJ's probe (F9 held, F16 released)
KEY_ATKMOD = KEY_PRESET | the modifier the attack dial uses. Track was
                        | taken (it copies a dial to every track) and
                        | Pattern fired its own action on the way out.

key_hook:
    moveal  %sp@(4),%a0
    movel   %a0@(12),%d0          | exactly what the stock accessor returns
    tstl    rtg_on
    bnew    kh_rtg                | the retrig page: the trig keys are its
    tstl    sle_on
    bnew    kh_sle                | the slice editor: the trig keys play slices
kh_norm:
    cmpil   #KEY_TRACK,%d0
    beqs    kh_track
    cmpil   #KEY_PRESET,%d0
    beqs    kh_preset
    lea.l   track_held,%a1
    tstl    %a1@
    bnew    kh_other
    rts                           | every other key: nothing to do. This rts went
                                  | missing when the Pattern handler was reverted
                                  | in samplerEB, and every key then fell through
                                  | into kh_track and latched ITS state as "Track
                                  | held" - so FUNC+Preset, or any key+Preset,
                                  | toggled the mode. The build now checks it.

    | Track: remember whether it is down. One press is read many times, but
    | every read of the same event carries the same flags, so this is idempotent.
kh_track:
    movel   %a0@(16),%d1
    andil   #1,%d1
    lea.l   track_held,%a1
    movel   %d1,%a1@
    rts

kh_preset:
    movel   %a0@(16),%d1
    btst    #0,%d1
    bnes    kh_p_down
    lea.l   kh_eaten,%a1
    tstl    %a1@
    beqs    kh_out                | an ordinary release: pass it through
    clrl    %a1@                  | the release of a press we swallowed: swallow
    bras    kh_eat                | it too, so nothing sees an unpaired key-up
kh_p_down:
    lea.l   kh_eaten,%a1
    tstl    %a1@
    bnes    kh_eat                | a later read of a press already swallowed
    btst    #3,%d1
    bnes    kh_out                | auto-repeat, not a fresh press
    lea.l   track_held,%a1
    tstl    %a1@
    beqs    kh_out                | Preset alone: leave the machine page alone
    moveq   #1,%d1
    lea.l   kh_eaten,%a1
    movel   %d1,%a1@              | fire once per press, not once per read
    | ---- consume the press, so Preset's own action does not also run ----
    | Two mechanisms, because handlers differ in what they look at first. The
    | base dispatcher at 0x40075f3c calls the gate 0x400724a0 BEFORE it reads
    | the code, so a handler earlier in the chain than us cannot be stopped by
    | the flags alone:
    |   1. set bit 3 (auto-repeat) in the event, so everything that gates on
    |      `down && !repeat` drops it from here on;
    |   2. answer 0 for every later read of this press. 0 is in range for any
    |      table a consumer might index by key code, so the worst case is a
    |      harmless lookup rather than a wild access - which is why it is 0 and
    |      not -1.
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    movel   %d0,%sp@-
    jsr     mode_menu_open
    movel   %sp@+,%d0
kh_eat:
    moveq   #0,%d0
    rts
kh_out:
    rts

    | ---- the retrig page is up: trig keys 1..16 (codes 16..31) hold repeats ----
    | Every read of an event carries the same flags, so this is idempotent:
    | down (bit 0) marks the step held - once, with the next press number, so
    | the newest held step wins - and up clears it. In Latch a fresh press
    | toggles that step instead. The key is then taken from everything else,
    | as the chords are: bit 3 set, and code 0 for this and later reads.
kh_rtg:
    movel   %d0,%d1
    subil   #16,%d1
    cmpil   #15,%d1
    bhiw    kh_rtg_n              | not a trig key: as usual
    tstl    rtg_pat               | Pattern held: the key is the pattern's
    beqs    krk_ours              | (Pattern closes the page anyway)
    btst    #0,%a0@(19)           | a release still lets go of a held repeat
    bnes    krk_pass
    lea.l   rtg_held,%a1
    clrl    %a1@(0,%d1:l:4)
krk_pass:
    rts
krk_ours:
    movel   %d2,%sp@-
    movel   %a0@(16),%d2          | flags
    lea.l   rtg_held,%a1
    lea.l   %a1@(0,%d1:l:4),%a1
    btst    #0,%d2
    beqs    krk_up
    tstl    %a1@
    bnes    krk_done              | already down: a later read, or a repeat
    movel   rtg_seq,%d2
    addql   #1,%d2
    movel   %d2,rtg_seq
    movel   %d2,%a1@
    tstl    rtg_latch
    beqs    krk_done
    cmpl    rtg_lstep,%d1         | Latch: the same step again stops it
    bnes    krk_lset
    moveq   #-1,%d1
krk_lset:
    movel   %d1,rtg_lstep
    bras    krk_done
krk_up:
    clrl    %a1@
krk_done:
    movel   %sp@+,%d2
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    moveq   #0,%d0
    rts
kh_rtg_n:
    cmpil   #KEY_TRACK,%d0
    beqw    kh_track
    cmpil   #KEY_PATTERN,%d0      | Pattern held: the trig keys choose patterns
    bnes    krn_np
    moveq   #0,%d1
    btst    #0,%a0@(19)
    beqs    krn_ps
    moveq   #1,%d1
krn_ps:
    movel   %d1,rtg_pat
    rts
krn_np:
    cmpil   #KEY_RETRIG,%d0       | the Retrig that opened the page: its later
    bnes    krn_out               | reads and its release are the chord's
    lea.l   kh_eaten4,%a1
    tstl    %a1@
    beqs    krn_out               | a fresh Retrig: mm_key closes the page
    btst    #0,%a0@(19)
    bnew    kh_eat
    clrl    %a1@
    braw    kh_eat
krn_out:
    rts

    | ---- the slice editor is up: trig keys 1..16 play slices 1..16 of the
    | edited sample (with FUNC held, 17..32) and select them. The note starts
    | as the track pad starts one (0x4001d05e), without its recording: the core
    | note-on 0x4008171e(track, note, velocity, 0x40, 0, -1, -1), note 52 +
    | slice; the release ends it (0x4008145e(track, note, 0x40)). Every read
    | of an event carries the same flags - a key's note is kept while it
    | sounds, so each press plays once - and the key is taken, as the retrig
    | page takes it. FUNC passes on as usual.
kh_sle:
    cmpil   #KEY_OPTS,%d0         | the options key: tap mode on / off
    beqw    ksl_opt
    cmpil   #1,%d0                | FUNC: held or not
    bnes    ksl_t
    moveq   #0,%d1
    btst    #0,%a0@(19)
    beqs    ksl_f
    moveq   #1,%d1
ksl_f:
    movel   %d1,sle_func
    braw    kh_norm
ksl_t:
    movel   %d0,%d1
    subil   #16,%d1
    cmpil   #15,%d1
    bhiw    kh_norm               | not a trig key
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    movea.l %a0,%a2               | the event
    lea.l   sle_held,%a3
    lea.l   %a3@(0,%d1:l:4),%a3   | this key's note + 1 while it sounds
    btst    #0,%a2@(19)
    beqs    ksl_up
    tstl    %a3@
    bnes    ksl_done              | a later read of the press, or a repeat
    tstl    sle_tap
    bnew    ksl_tap               | tapping: the key starts or marks
    movel   %d1,%d2
    tstl    sle_func
    beqs    ksl_n
    addil   #16,%d2
ksl_n:
    movel   sle_trk,%d0
    jsr     mk_trk
    tstl    %d0
    beqs    ksl_done
    movea.l %d0,%a0
    cmpl    %a0@(4),%d2
    bccs    ksl_done              | past the last slice
    movel   %d2,sle_sel
    moveq   #1,%d0
    movel   %d0,sle_dirty
    movel   %d2,%d3
    addil   #52,%d3               | trig pad 1 is note 52 = slice 1
    movel   %d3,%d0
    addql   #1,%d0
    movel   %d0,%a3@
    pea     -1
    pea     -1
    clrl    %sp@-
    pea     0x40
    pea     100                   | velocity
    movel   %d3,%sp@-
    movel   sle_trk,%sp@-
    jsr     0x4008171e
    lea.l   %sp@(28),%sp
    bras    ksl_done
ksl_up:
    movel   %a3@,%d0
    beqs    ksl_done
    clrl    %a3@
    subql   #1,%d0
    jsr     sle_off
ksl_done:
    movel   %a2@(16),%d1
    oril    #8,%d1
    movel   %d1,%a2@(16)
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
    moveq   #0,%d0
    rts
    | Tapping, armed: the first trig press clears the markers to one slice and
    | plays the whole sample from its start (sampler_render, while sle_run);
    | each press after it adds a marker where it is playing - phase_table's
    | sample, MK_MINL past the last and short of the end, 32 at most. The note
    | is not the key's: releasing it leaves the sample playing.
ksl_tap:
    btst    #3,%a2@(19)
    bnew    ksl_done              | a later read, or a repeat
    movel   sle_trk,%d0
    jsr     mk_trk
    tstl    %d0
    beqw    ksl_done
    movea.l %d0,%a3               | the entry
    tstl    sle_run
    bnes    ksl_mark
    moveq   #1,%d0
    movel   %d0,%a3@(4)
    clrl    %a3@(8)
    movel   %d0,%a3@(136)
    addql   #1,mk_gen
    clrl    sle_sel
    clrl    sle_zoom
    movel   blk_clk,%d1
    movel   %d1,sle_t0
    movel   %d0,sle_run
    movel   %d0,sle_dirty
    pea     -1
    pea     -1
    clrl    %sp@-
    pea     0x40
    pea     100
    pea     52                    | slice 1's note (the render plays it whole)
    movel   sle_trk,%sp@-
    jsr     0x4008171e
    lea.l   %sp@(28),%sp
    braw    ksl_done
ksl_mark:
    movel   %a3@(4),%d2           | slices so far
    cmpil   #MK_MAX,%d2
    bccw    ksl_done
    movel   sle_trk,%d0
    lsll    #3,%d0
    lea.l   phase_table,%a0
    movel   %a0@(0,%d0:l),%d3     | where it is playing
    movel   %a3@(4,%d2:l:4),%d0   | past the last start
    addil   #MK_MINL,%d0
    cmpl    %d0,%d3
    bcsw    ksl_done
    movel   sle_trk,%d0           | short of the end
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d0
    bmiw    ksl_done
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d0
    subil   #MK_MINL,%d0
    cmpl    %d0,%d3
    bccw    ksl_done
    movel   %d3,%a3@(8,%d2:l:4)
    movel   %d2,sle_sel
    addql   #1,%d2
    movel   %d2,%a3@(4)
    moveq   #1,%d0
    movel   %d0,%a3@(136)
    addql   #1,mk_gen
    moveq   #1,%d0
    movel   %d0,sle_dirty
    braw    ksl_done
    | the options key, pressed: arm or disarm tapping, or stop it (the note
    | ends and the markers stay). Press and release are both taken.
ksl_opt:
    btst    #0,%a0@(19)
    beqs    kso_eat               | the release
    btst    #3,%a0@(19)
    bnes    kso_eat               | a later read, or a repeat
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    tstl    sle_run
    bnes    kso_stop
    movel   sle_tap,%d1
    eoril   #1,%d1
    movel   %d1,sle_tap
    bras    kso_d
kso_stop:
    jsr     sle_tstop
kso_d:
    moveq   #1,%d1
    movel   %d1,sle_dirty
kso_eat:
    moveq   #0,%d0
    rts

    | ---- Track + key 9: the Resample menu ----
    | Key 9 measured on hardware with samplerFG's probe. Press and release are
    | swallowed as the options chord's are, once the menu is up.
kh_rs:
    cmpil   #KEY_RETRIG,%d0
    beqw    kh_rt
    cmpil   #MM_KEY_RETURN,%d0
    beqw    kh_rx
    cmpil   #KEY_RESAMPLE,%d0
    bnew    kh_out
    movel   %a0@(16),%d1
    lea.l   kh_eaten3,%a1
    btst    #0,%d1
    bnes    kh_r_down
    tstl    %a1@                  | a release: ours only if we took the press
    beqw    kh_out
    clrl    %a1@
    braw    kh_eat
kh_r_down:
    tstl    %a1@
    bnew    kh_eat
    btst    #3,%d1
    bnew    kh_out
    movel   %a0,%sp@-
    movel   %d0,%sp@-
    jsr     rs_menu_open
    movel   %sp@+,%d0
    movea.l %sp@+,%a0
    lea.l   mm_opened,%a1
    tstl    %a1@
    beqw    kh_out
    lea.l   kh_eaten3,%a1
    moveq   #1,%d1
    movel   %d1,%a1@
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    braw    kh_eat

    | ---- Track + Return: the master FX off, from anywhere ----
    | The retrig page's effects outlive it; this turns them all off (fading,
    | as Return on the page does) and says so. Press and release swallowed.
kh_rx:
    movel   %a0@(16),%d1
    lea.l   kh_eaten5,%a1
    btst    #0,%d1
    bnes    kh_x_down
    tstl    %a1@
    beqw    kh_out
    clrl    %a1@
    braw    kh_eat
kh_x_down:
    btst    #3,%d1                | a fresh press acts even if an old flag was
    beqs    kh_x_new              | left behind (Track let go before Return)
    tstl    %a1@
    bnew    kh_eat
    braw    kh_out
kh_x_new:
    moveq   #1,%d1
    movel   %d1,%a1@
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    movel   %a0,%sp@-
    jsr     mfx_reset
    pea     msg_fxoff
    jsr     show_popup
    addql   #4,%sp
    movea.l %sp@+,%a0
    braw    kh_eat

    | ---- Track + Retrig: the retrig page, its press and release swallowed ----
kh_rt:
    movel   %a0@(16),%d1
    lea.l   kh_eaten4,%a1
    btst    #0,%d1
    bnes    kh_t_down
    tstl    %a1@
    beqw    kh_out
    clrl    %a1@
    braw    kh_eat
kh_t_down:
    btst    #3,%d1                | a fresh press opens, even if an old flag
    beqs    kh_t_new              | was left behind
    tstl    %a1@
    bnew    kh_eat
    braw    kh_out
kh_t_new:
    movel   %a0,%sp@-
    movel   %d0,%sp@-
    jsr     rtg_open
    movel   %sp@+,%d0
    movea.l %sp@+,%a0
    lea.l   mm_opened,%a1
    tstl    %a1@
    beqw    kh_out
    lea.l   kh_eaten4,%a1
    moveq   #1,%d1
    movel   %d1,%a1@
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    braw    kh_eat

    | ---- Track + key 6: the current mode's options menu ----
    | Key 6 was measured on hardware with a probe build (samplerEU). The menu
    | only exists for One shot and Slice; for any other mode, or anything else
    | that stops it opening, the press is left alone, so key 6 keeps doing what
    | it always did. Once a menu is up the press - and its release - are
    | swallowed exactly as the Preset chord is.
kh_other:
    cmpil   #KEY_OPTS,%d0
    bnew    kh_rs
    movel   %a0@(16),%d1
    lea.l   kh_eaten2,%a1
    btst    #0,%d1
    bnes    kh_o_down
    tstl    %a1@                  | a release: ours only if we took the press
    beqw    kh_out
    clrl    %a1@
    braw    kh_eat
kh_o_down:
    tstl    %a1@
    bnew    kh_eat                | a later read of a press already taken
    btst    #3,%d1
    bnew    kh_out
    movel   %a0,%sp@-
    movel   %d0,%sp@-
    jsr     gran_menu_open        | every mode: its list of settings
kh_o_open:
    movel   %sp@+,%d0
    movea.l %sp@+,%a0
    lea.l   mm_opened,%a1
    tstl    %a1@
    beqw    kh_out                | no menu for this mode: key 6 as normal
    lea.l   kh_eaten2,%a1
    moveq   #1,%d1
    movel   %d1,%a1@
    movel   %a0@(16),%d1
    oril    #8,%d1
    movel   %d1,%a0@(16)
    braw    kh_eat

| ================= lo-fi =================
| d0 = track. Sample-and-hold then bit masking over the 64-sample 2x buffer
| the normal fill has just written. The hold advances lf_inc (Q16) per buffer
| sample and takes a new value each time it wraps: 32768 at dial 127 takes one
| per 48 kHz sample - which the zero-order-hold buffer repeats anyway, so the
| clean end of the dial is transparent. The held value is masked to the bits
| Crush keeps. Phase and held value carry across blocks. Run once per PAIR
| (both halves hold the same sample): the phase moves 2 x lf_inc, <= 65536,
| so it wraps at most once a pair.
lofi_apply:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a2,%sp@
    movel   %d0,%d2
    lea.l   lf_inc,%a0
    movel   %a0@(0,%d2:l:4),%d3
    lea.l   lf_mask,%a0
    movel   %a0@(0,%d2:l:4),%d4
    lea.l   lf_ph,%a0
    movel   %a0@(0,%d2:l:4),%d5
    lea.l   lf_hold,%a0
    movel   %a0@(0,%d2:l:4),%d1
    movea.l fx_buf,%a2            | sampler_buf+32, or the right channel's
    addl    %d3,%d3               | a pair's worth
    moveq   #31,%d0
lf_l:
    addl    %d3,%d5
    cmpil   #65536,%d5
    bcss    lf_keep
    subil   #65536,%d5
    movel   %a2@,%d1
    andl    %d4,%d1
lf_keep:
    movel   %d1,%a2@+
    movel   %d1,%a2@+
    subql   #1,%d0
    bpls    lf_l
    lea.l   lf_ph,%a0
    movel   %d5,%a0@(0,%d2:l:4)
    lea.l   lf_hold,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    moveml  %sp@,%d2-%d5/%a2
    lea.l   %sp@(20),%sp
    rts

| ================= One shot: Tape and Vinyl =================
| Both work on the 64-sample 2x buffer after the normal fill, with the ladder
| off: Filter is Tone and Res is Wear. Tone (tv_tone) is a one-pole lowpass
| coefficient, 127 passing everything and 0 about 460 Hz. Wear (tv_wear,
| 0..127) is how much of the effect; at 0 each is clean apart from Tone. The
| pitch wobble is step_mod's, also scaled by Wear.
| tape_apply(d0 = track): drive into a soft clip, y = (3x - x^3)/2 on x =
| 0.66 * gain * the sample, gain 1 + Wear/32 (up to ~5x) - so Wear pushes
| from warm into squashed - then Tone.
tape_apply:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d6/%a2,%sp@
    movel   %d0,%d2
    lea.l   tp_lp,%a0
    movel   %a0@(0,%d2:l:4),%d3   | lowpass state, 16-bit
    lea.l   tv_wear,%a0
    movel   %a0@(0,%d2:l:4),%d6
    lsll    #3,%d6
    addil   #256,%d6              | drive gain, Q8
    lea.l   tv_tone,%a0
    movel   %a0@(0,%d2:l:4),%d0   | Tone, Q16, per 96 kHz sample
    bsr     tone48
    movea.l %d0,%a0               | ...per pair: all of it once a pair
    movea.l fx_buf,%a2
    moveq   #31,%d5
tp_l:
    movel   %a2@,%d0
    asrl    #8,%d0
    asrl    #7,%d0                | the sample
    mulsl   %d6,%d0
    asrl    #8,%d0                | * gain
    movel   #21627,%d1
    mulsl   %d1,%d0
    asrl    #8,%d0
    asrl    #7,%d0                | * 0.66
    cmpil   #32767,%d0
    bles    tp_c1
    movel   #32767,%d0
tp_c1:
    cmpil   #-32767,%d0
    bges    tp_c2
    movel   #-32767,%d0
tp_c2:
    movel   %d0,%d1
    mulsl   %d0,%d1
    asrl    #8,%d1
    asrl    #7,%d1
    mulsl   %d0,%d1
    asrl    #8,%d1
    asrl    #7,%d1                | x^3, Q15
    movel   %d0,%d4
    addl    %d4,%d4
    addl    %d0,%d4
    subl    %d1,%d4
    asrl    #1,%d4                | (3x - x^3) / 2
    subl    %d3,%d4               | Tone: lp += (y - lp) * a
    movel   %a0,%d1
    mulsl   %d1,%d4
    asrl    #8,%d4
    asrl    #8,%d4
    addl    %d4,%d3
    movel   %d3,%d0
    lsll    #8,%d0
    lsll    #7,%d0
    movel   %d0,%a2@+
    movel   %d0,%a2@+
    subql   #1,%d5
    bpls    tp_l
    lea.l   tp_lp,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    moveml  %sp@,%d2-%d6/%a2
    lea.l   %sp@(24),%sp
    rts

| vinyl_apply(d0 = track): Tone, then crackle and hiss scaled by Wear -
| clicks at up to ~40 a second (chance per 96 kHz sample Wear^2/600 in
| 65536), each up to full strength and dying away over a few samples, and
| hiss up to about -36 dB.
vinyl_apply:
    lea.l   %sp@(-28),%sp
    moveml  %d2-%d7/%a2,%sp@
    movel   %d0,%d2
    lea.l   vn_lp,%a0
    movel   %a0@(0,%d2:l:4),%d3   | lowpass state
    lea.l   vn_cr,%a0
    movel   %a0@(0,%d2:l:4),%d4   | crackle
    lea.l   vn_rng,%a0
    movel   %a0@,%d5
    lea.l   tv_wear,%a0
    movel   %a0@(0,%d2:l:4),%d7
    lea.l   tv_tone,%a0
    movel   %a0@(0,%d2:l:4),%d0   | Tone, Q16, per 96 kHz sample
    bsr     tone48
    movea.l %d0,%a0               | ...per pair: all of it once a pair
    movea.l fx_buf,%a2
    movea.l #32,%a1               | pairs to go
    movel   %d7,%d6               | the click chance: Wear^2 / 300 of 65536 a
    mulsl   %d7,%d6               | pair (/600 per 96 kHz sample, twice)
    movel   #300,%d1
    divul   %d1,%d6
    moveq   #31,%d1               | a silent block (the note over, or muted and
vn_s:                             | rung out) gets no crackle or hiss, or the
    movel   %a2@,%d0              | track would never fall idle
    addql   #8,%a2
    bpls    vn_sp
    negl    %d0
vn_sp:
    cmpil   #SIL_LVL,%d0
    bccs    vn_live
    subql   #1,%d1
    bpls    vn_s
    moveq   #0,%d6                | no clicks, no hiss; Tone and a click
    moveq   #0,%d7                | already dying still run
vn_live:
    movea.l fx_buf,%a2
    movel   #181,%d0              | the hiss's own scale, on the stack: Wear x
    mulsl   %d7,%d0               | 0.707 - a value a pair, not a 96 kHz
    asrl    #8,%d0                | sample, puts ~3 dB more noise in band
    movel   %d0,%sp@-
vn_l:
    movel   %a2@,%d0
    asrl    #8,%d0
    asrl    #7,%d0
    subl    %d3,%d0               | Tone
    movel   %a0,%d1
    mulsl   %d1,%d0
    asrl    #8,%d0
    asrl    #8,%d0
    addl    %d0,%d3
    movel   #1664525,%d1
    mulsl   %d1,%d5
    addil   #1013904223,%d5
    movel   %d5,%d0               | a click? top 16 bits under the chance
    clrw    %d0
    swap    %d0
    cmpl    %d6,%d0
    bccs    vn_nc
    movel   %d5,%d4               | strength from the low half, scaled by Wear
    extl    %d4
    mulsl   %d7,%d4
    asrl    #7,%d4
vn_nc:
    movel   %d3,%d0
    addl    %d4,%d0
    movel   %d5,%d1               | hiss: +-362 at full Wear
    asrl    #8,%d1
    asrl    #8,%d1
    asrl    #6,%d1                | +-512
    mulsl   %sp@,%d1
    asrl    #7,%d1
    addl    %d1,%d0
    moveq   #25,%d1               | the click dies away: x 0.625 a 96 kHz
    mulsl   %d4,%d1               | sample is x 25/64 a pair
    asrl    #6,%d1
    movel   %d1,%d4
    cmpil   #32767,%d0
    bles    vn_c1
    movel   #32767,%d0
vn_c1:
    cmpil   #-32767,%d0
    bges    vn_c2
    movel   #-32767,%d0
vn_c2:
    lsll    #8,%d0
    lsll    #7,%d0
    movel   %d0,%a2@+
    movel   %d0,%a2@+
    subql   #1,%a1
    movel   %a1,%d0
    bnew    vn_l
    addql   #4,%sp                | the hiss scale
    lea.l   vn_lp,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    lea.l   vn_cr,%a0
    movel   %d4,%a0@(0,%d2:l:4)
    lea.l   vn_rng,%a0
    movel   %d5,%a0@
    moveml  %sp@,%d2-%d7/%a2
    lea.l   %sp@(28),%sp
    rts

| tone48 (d0 = a one-pole coefficient per 96 kHz sample, Q16, 0..65536) ->
| d0 = the same pole per 48 kHz pair: 1 - (1 - a)^2 = 2a - a^2. Clobbers d1.
tone48:
    movel   %d0,%d1
    lsrl    #8,%d1
    mulul   %d1,%d1               | a^2, Q16
    addl    %d0,%d0
    subl    %d1,%d0
    rts

| ---- the playback step, adjusted per option (from sv_havestep) ----
| d1 = step, Q16.16; d4 = track. Everything but d1 survives.
| One shot Tape: wow (0.57 Hz, +-0.27%) and flutter (7 Hz, +-0.09%).
| One shot Vinyl: a slower wow (0.53 Hz, +-0.18%).
| Loop Sync 1/2/4 bars: the step that makes the loop window last exactly
| that long at the project tempo, (span << 10) / (bars >> 6), ignoring the
| note - the loop's length is the point.
| LFO steps are per block: 1500 blocks a second of 32 samples.
step_mod:
    lea.l   %sp@(-16),%sp
    moveml  %d0/%d2-%d3/%a0,%sp@
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d4:l:4),%d0
    cmpil   #1,%d0
    bnew    sm_os
    lea.l   lp_sync,%a0           | loop sync: 1, 2 or 4 bars
    movel   %a0@(0,%d4:l:4),%d0
    subql   #1,%d0
    bmiw    sm_os
    movel   0x40149310,%d2
    beqw    sm_out
    movel   #1382400000,%d3
    divul   %d2,%d3               | one bar
    lsll    %d0,%d3               | 1/2/4 bars
    lsrl    #6,%d3
    beqw    sm_out
    lea.l   win_span,%a0
    movel   %a0@(0,%d4:l:4),%d2
    beqw    sm_out
    lsll    #8,%d2
    lsll    #2,%d2
    divul   %d3,%d2
    movel   %d2,%d1
sm_os:                            | Tape and Vinyl wobble: One shot, Loop, Slice
    lea.l   loop_mode,%a0
    moveq   #2,%d0
    cmpl    %a0@(0,%d4:l:4),%d0
    bcsw    sm_out
    lea.l   fx_sel,%a0
    movel   %a0@(0,%d4:l:4),%d0
    cmpil   #2,%d0
    beqs    sm_tape
    cmpil   #3,%d0
    bnew    sm_out
    lea.l   tv_wear,%a0           | vinyl: wow, up to +-1.5% at full Wear
    movel   %a0@(0,%d4:l:4),%d3
    beqw    sm_out
    lea.l   wow_ph,%a0
    lea.l   %a0@(0,%d4:l:4),%a0
    movel   %a0@,%d2
    addil   #1517600,%d2          | 0.53 Hz
    movel   %d2,%a0@
    bsr     sm_tri
    movel   %d3,%d0
    lsll    #3,%d0                | wear * 8
    mulsl   %d0,%d2
    bras    sm_apply
sm_tape:
    lea.l   tv_wear,%a0           | tape: wow up to +-2.5%, flutter +-0.6%
    movel   %a0@(0,%d4:l:4),%d3
    beqw    sm_out
    lea.l   wow_ph,%a0
    lea.l   %a0@(0,%d4:l:4),%a0
    movel   %a0@,%d2
    addil   #1631588,%d2          | 0.57 Hz
    movel   %d2,%a0@
    bsr     sm_tri
    moveq   #13,%d0               | wear * 13
    mulsl   %d3,%d0
    mulsl   %d0,%d2
    movel   %d2,%sp@-             | park the wow
    lea.l   flu_ph,%a0
    lea.l   %a0@(0,%d4:l:4),%a0
    movel   %a0@,%d2
    addil   #20043209,%d2         | 7 Hz
    movel   %d2,%a0@
    bsr     sm_tri
    movel   %d3,%d0
    lsll    #2,%d0                | wear * 4
    mulsl   %d0,%d2
    addl    %sp@+,%d2
sm_apply:
    asrl    #8,%d2
    asrl    #7,%d2                | the wobble, Q16
    movel   %d1,%d0
    lsrl    #8,%d0
    mulsl   %d2,%d0
    asrl    #8,%d0
    addl    %d0,%d1
sm_out:
    moveml  %sp@,%d0/%d2-%d3/%a0
    lea.l   %sp@(16),%sp
    rts
| d2 = phase -> d2 = triangle, -32768..32767
sm_tri:
    lsrl    #8,%d2
    lsrl    #7,%d2                | 0..131071
    cmpil   #65536,%d2
    bcss    smt_up
    negl    %d2
    addil   #131071,%d2
smt_up:
    subil   #32768,%d2
    rts

| ================= slice tables =================
| Each Slice track has a row of sl_tbl: the first sample of every slice and,
| after the last, the sample's length - so slice i is [row[i], row[i+1]).
| sl_N is the option's slice count (8/16/32), sl_S how many the row holds (0
| while it is being built: the render then plays 16 equal slices). Built here
| on the UI side whenever the sample, the mode or the option changes, which
| sl_key notices. Equal division is instant; transient detection reads the
| sample once, a quarter of it, so a long sample holds the UI for a moment.
SLROW = 33*4
slice_watch:
    lea.l   %sp@(-36),%sp
    moveml  %d2-%d7/%a2-%a4,%sp@
    moveq   #0,%d2
swt_l:
    lea.l   loop_mode,%a0
    moveq   #2,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnew    swt_next
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    swt_next
    lea.l   slot_base,%a0
    movel   %a0@(0,%d0:l:4),%d3   | file base
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4   | samples
    cmpil   #64,%d4
    bcsw    swt_next              | too short to slice
    lea.l   sl_cfg,%a0
    movel   %a0@(0,%d2:l:4),%d5   | option 0..5
    movel   %d4,%d0               | key: base ^ count<<4 ^ option<<28, never 0
    lsll    #4,%d0
    eorl    %d3,%d0
    movel   %d5,%d1
    moveq   #28,%d6
    lsll    %d6,%d1
    eorl    %d1,%d0
    cmpil   #6,%d5
    bnes    swt_k
    addl    mk_gen,%d0            | MAN: every edit rebuilds it
swt_k:
    bset    #0,%d0
    lea.l   sl_key,%a0
    cmpl    %a0@(0,%d2:l:4),%d0
    beqw    swt_next
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   sl_S,%a0              | the render falls back while this is written
    clrl    %a0@(0,%d2:l:4)
    cmpil   #6,%d5
    beqw    swt_man               | MAN: the sample's own markers
    movel   %d5,%d7               | log2 count = 3 + option % 3
    cmpil   #3,%d7
    bcss    swt_lg
    subql   #3,%d7
swt_lg:
    addql   #3,%d7
    moveq   #1,%d6
    lsll    %d7,%d6               | N
    lea.l   sl_N,%a0
    movel   %d6,%a0@(0,%d2:l:4)
    movel   %d2,%d0               | a2 = this track's row
    lsll    #5,%d0
    addl    %d2,%d0
    lsll    #2,%d0
    lea.l   sl_tbl,%a2
    addal   %d0,%a2
    cmpil   #3,%d5
    bcsw    swt_equal
    | transients: slice_detect(row, pcm, count, N) -> slices found, 0 = none
    movel   %d6,%sp@-
    movel   %d4,%sp@-
    movel   %d3,%d0
    addil   #64,%d0               | past the file header
    movel   %d0,%sp@-
    movel   %a2,%sp@-
    bsr     slice_detect
    lea.l   %sp@(16),%sp
    cmpil   #2,%d0
    bcsw    swt_equal             | nothing clear enough: equal slices instead
    braw    swt_set
swt_man:
    movel   %d2,%d0               | a2 = this track's row
    lsll    #5,%d0
    addl    %d2,%d0
    lsll    #2,%d0
    lea.l   sl_tbl,%a2
    addal   %d0,%a2
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d0:l:4),%d0
    jsr     mk_get                | from its file, the first time
    tstl    %d0
    beqs    swt_m16
    movea.l %d0,%a3
    movel   %a3@(4),%d5           | slices
    beqs    swt_m16
    cmpil   #MK_MAX,%d5
    bhis    swt_m16
    tstl    %a3@(8)
    bnes    swt_m16               | slice 1 starts the sample
    moveq   #0,%d1
swt_mc:
    movel   %a3@(8,%d1:l:4),%d0   | each inside the sample, after the last
    cmpl    %d4,%d0
    bccs    swt_m16
    tstl    %d1
    beqs    swt_mw
    cmpl    %a3@(4,%d1:l:4),%d0
    blss    swt_m16
swt_mw:
    movel   %d0,%a2@(0,%d1:l:4)
    addql   #1,%d1
    cmpl    %d5,%d1
    bcss    swt_mc
    movel   %d4,%a2@(0,%d1:l:4)   | the sample's end closes the last
    moveq   #1,%d6                | N: the power of two the notes wrap at
swt_mn:
    cmpl    %d5,%d6
    bccs    swt_mN
    addl    %d6,%d6
    bras    swt_mn
swt_mN:
    lea.l   sl_N,%a0
    movel   %d6,%a0@(0,%d2:l:4)
    movel   %d5,%d0
    bras    swt_set
swt_m16:
    moveq   #4,%d7                | none (yet): 16 equal slices
    moveq   #16,%d6
    lea.l   sl_N,%a0
    movel   %d6,%a0@(0,%d2:l:4)
swt_equal:
    moveq   #0,%d1                | row[i] = count * i / N, i = 0..N
swt_eq:
    movel   %d4,%d0
    mulul   %d1,%d0
    lsrl    %d7,%d0
    movel   %d0,%a2@(0,%d1:l:4)
    addql   #1,%d1
    cmpl    %d6,%d1
    blss    swt_eq
    movel   %d6,%d0
swt_set:
    lea.l   sl_S,%a0
    movel   %d0,%a0@(0,%d2:l:4)
swt_next:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcsw    swt_l
    moveml  %sp@,%d2-%d7/%a2-%a4
    lea.l   %sp@(36),%sp
    rts

| ================= manual slices (MOD MAN, sl_cfg 6) =================
| Each sample's own slice starts, by the sample's hash, in mk_tbl at MK_BASE:
| 64 entries of {hash, n, 32 starts} - slice i is [start i, start i+1), the
| last ends at the sample's end, and start 0 is always 0. slice_watch copies
| them into the track's row. +136 says an entry has changed since it was
| saved. Each sample's are kept on disk as /Slices/<its hash, 8 hex digits>:
| 136 bytes, "SLC1", n and the 32 starts - read the first time the sample's
| entry is wanted (mk_get), written by mk_post's UI-task message.
MK_ENT  = 140
MK_MAGIC = 0x534c4331             | "SLC1"
MK_NUM  = 64
MK_MAX  = 32
MK_MINL = 64                      | a slice's least length, samples
| mk_ready: the table from nothing, once after boot. Keeps every register.
mk_ready:
    tstl    mk_ok
    bnes    mkr_x
    lea.l   %sp@(-8),%sp
    moveml  %d0/%a0,%sp@
    movea.l #MK_BASE,%a0
    movel   #MK_NUM*MK_ENT/4-1,%d0
mkr_l:
    clrl    %a0@+
    subql   #1,%d0
    bpls    mkr_l
    moveq   #1,%d0
    movel   %d0,mk_ok
    moveml  %sp@,%d0/%a0
    lea.l   %sp@(8),%sp
mkr_x:
    rts
| mk_find(d0 = hash) -> d0 = its entry, or 0. Keeps d1-d7, a1.
mk_find:
    bsr     mk_ready
    tstl    %d0
    beqs    mkf_no
    movel   %d1,%sp@-
    movea.l #MK_BASE,%a0
    moveq   #MK_NUM-1,%d1
mkf_l:
    cmpl    %a0@,%d0
    beqs    mkf_hit
    lea.l   %a0@(MK_ENT),%a0
    subql   #1,%d1
    bpls    mkf_l
    movel   %sp@+,%d1
mkf_no:
    moveq   #0,%d0
    rts
mkf_hit:
    movel   %sp@+,%d1
    movel   %a0,%d0
    rts
| mk_new(d0 = hash) -> d0 = its entry: the one it has, else a new one (n 0) -
| an empty entry, or one whose sample is no longer resident. Keeps d2-d7.
mk_new:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d3/%a2,%sp@
    movel   %d0,%d2
    bsr     mk_find
    tstl    %d0
    bnes    mkn_out
    movea.l #MK_BASE,%a2
    moveq   #MK_NUM-1,%d3
mkn_l:
    movel   %a2@,%d0
    beqs    mkn_take
    jsr     wfk_find              | still resident?
    tstl    %d0
    bmis    mkn_take
    lea.l   %a2@(MK_ENT),%a2
    subql   #1,%d3
    bpls    mkn_l
    movea.l #MK_BASE,%a2          | every one in use: the first goes
mkn_take:
    movel   %d2,%a2@
    clrl    %a2@(4)
    clrl    %a2@(136)
    movel   %a2,%d0
mkn_out:
    moveml  %sp@,%d2-%d3/%a2
    lea.l   %sp@(12),%sp
    rts
| mk_get(d0 = hash) -> d0 = its entry: the table's, or else a new one read
| from the sample's file (n 0 if it has none - asked once a boot). 0 for
| hash 0. Keeps d2-d7, a2-a6.
mk_get:
    tstl    %d0
    beqs    mkg_x
    lea.l   %sp@(-8),%sp
    movel   %d0,%sp@
    movel   %a2,%sp@(4)
    bsr     mk_find
    tstl    %d0
    bnes    mkg_o
    movel   %sp@,%d0
    bsr     mk_new
    movea.l %d0,%a2
    bsr     mk_read
    movel   %a2,%d0
mkg_o:
    movea.l %sp@(4),%a2
    lea.l   %sp@(8),%sp
mkg_x:
    rts
| mk_path(d0 = hash, a1 = 20 bytes): "/Slices/XXXXXXXX". Keeps d2-d7.
mk_path:
    movel   %d2,%sp@-
    lea.l   mk_s_dir,%a0
mkpa_c:
    moveb   %a0@+,%d1
    beqs    mkpa_h
    moveb   %d1,%a1@+
    bras    mkpa_c
mkpa_h:
    moveq   #28,%d2
mkpa_x:
    movel   %d0,%d1
    lsrl    %d2,%d1
    andil   #15,%d1
    cmpil   #10,%d1
    bcss    mkpa_d
    addql   #7,%d1
mkpa_d:
    addil   #48,%d1
    moveb   %d1,%a1@+
    subql   #4,%d2
    bpls    mkpa_x
    clrb    %a1@
    movel   %sp@+,%d2
    rts
| mk_read(a2 = an entry, n 0): its sample's file, if it has a good one, into
| it - through the firmware's small-file calls (as 0x400a2b52 uses them):
| open 0x4007bc5e(path, "r", fh), read 0x4007baaa(buf, len, fh), close
| 0x4007bc1c(fh); fh is 16 bytes. A take's hash is never on disk. Keeps d2-d7,
| a2-a6. Frame: path -20, fh -36, the file -172, a String -176, its tag -177.
mk_read:
    linkw   %fp,#-180
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    movel   %a2@,%d0
    movel   %d0,%d1
    andil   #0xffffff00,%d1
    cmpil   #RS_HASH,%d1
    beqw    mkrd_out
    lea.l   %fp@(-20),%a1
    bsr     mk_path
    pea     %fp@(-36)
    pea     0x40126ce4            | "r"
    pea     %fp@(-20)
    jsr     0x4007bc5e
    lea.l   %sp@(12),%sp
    tstl    %d0
    bnew    mkrd_out              | no file
    pea     %fp@(-36)
    pea     136
    pea     %fp@(-172)
    jsr     0x4007baaa
    lea.l   %sp@(12),%sp
    movel   %d0,%d2
    pea     %fp@(-36)
    jsr     0x4007bc1c
    addql   #4,%sp
    cmpil   #136,%d2
    bnes    mkrd_out
    lea.l   %fp@(-172),%a0
    movel   %a0@,%d0
    cmpil   #MK_MAGIC,%d0
    bnes    mkrd_out
    movel   %a0@(4),%d0
    beqs    mkrd_out
    cmpil   #MK_MAX,%d0
    bhis    mkrd_out
    moveq   #33,%d1               | n and the 32 starts
mkrd_c:
    movel   %a0@(0,%d1:l:4),%d0
    movel   %d0,%a2@(0,%d1:l:4)
    subql   #1,%d1
    bnes    mkrd_c
mkrd_out:
    moveml  %sp@,%d2/%a2
    unlk    %fp
    rts
| mk_write(a2 = an entry): its file, replaced - prepared as the FileWriter
| prepares a path (0x4007c410: 0x4007c18e(path), then its folder made,
| 0x4007c262 of 0x40095284's), then open "w", 0x4007bb76(fh, 0, size), write
| 0x4007bb0a(buf, len, fh), 0x4007e2f6(fh), close: 0x400a2b52's sequence.
| In the UI task only (mk_sv_run). Keeps d2-d7, a2-a6.
mk_write:
    linkw   %fp,#-180
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    movel   %a2@,%d0
    movel   %d0,%d1
    andil   #0xffffff00,%d1
    cmpil   #RS_HASH,%d1
    beqw    mkw_out               | an unsaved take: nowhere to keep them
    lea.l   %fp@(-20),%a1
    bsr     mk_path
    lea.l   %fp@(-172),%a1        | the file: the entry, "SLC1" for its hash
    movel   #MK_MAGIC,%d0
    movel   %d0,%a1@
    moveq   #33,%d1
mkw_c:
    movel   %a2@(0,%d1:l:4),%d0
    movel   %d0,%a1@(0,%d1:l:4)
    subql   #1,%d1
    bnes    mkw_c
    pea     %fp@(-20)
    jsr     0x4007c18e
    addql   #4,%sp
    pea     %fp@(-20)
    jsr     0x40095284            | its folder
    addql   #4,%sp
    tstl    %d0
    beqs    mkw_open
    pea     %fp@(-177)
    movel   %d0,%sp@-
    pea     %fp@(-176)
    jsr     0x400f980c            | as a String
    lea.l   %sp@(12),%sp
    pea     %fp@(-176)
    jsr     0x4007c262            | made, if it is not there
    addql   #4,%sp
    pea     %fp@(-176)
    jsr     0x400f7d5c
    addql   #4,%sp
mkw_open:
    pea     %fp@(-36)
    pea     0x401272db            | "w"
    pea     %fp@(-20)
    jsr     0x4007bc5e
    lea.l   %sp@(12),%sp
    tstl    %d0
    bnes    mkw_out
    pea     136
    clrl    %sp@-
    pea     %fp@(-36)
    jsr     0x4007bb76
    lea.l   %sp@(12),%sp
    pea     %fp@(-36)
    pea     136
    pea     %fp@(-172)
    jsr     0x4007bb0a
    lea.l   %sp@(12),%sp
    pea     %fp@(-36)
    jsr     0x4007e2f6
    addql   #4,%sp
    pea     %fp@(-36)
    jsr     0x4007bc1c
    addql   #4,%sp
mkw_out:
    moveml  %sp@,%d2/%a2
    unlk    %fp
    rts
| mk_post: a UI-task message (as sv_post's) that writes every changed entry's
| file - writing on the LED clock froze the audio (see sv_post). Already
| queued: that one will do. Clobbers d0, d1, a0, a1.
mk_post:
    lea.l   mk_msg,%a0
    tstl    %a0@(0x18)
    bnes    mkpo_out
    movel   %a0,%sp@-
    pea     1
    jsr     ALLOC
    addql   #4,%sp
    movea.l %sp@+,%a0
    movel   %d0,%a0@(4)
    clrl    %a0@(8)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a0@(0x0c)
    movel   #mk_sv_run,%d0
    movel   %d0,%a0@(0x10)
    clrl    %a0@(0x14)
    moveq   #1,%d0
    movel   %d0,%a0@(0x18)
    moveq   #6,%d0                | type 6: run the callback
    moveb   %d0,%a0@
    movel   %a0,%sp@-
    pea     MQ_MAIN
    jsr     0x40001fba
    addql   #8,%sp
mkpo_out:
    rts
mk_sv_run:                        | (closure, arg), in the UI task
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    bsr     mk_ready
    movea.l #MK_BASE,%a2
    moveq   #MK_NUM-1,%d2
mks_l:
    tstl    %a2@(136)
    beqs    mks_n
    clrl    %a2@(136)
    tstl    %a2@
    beqs    mks_n
    bsr     mk_write
mks_n:
    lea.l   %a2@(MK_ENT),%a2
    subql   #1,%d2
    bpls    mks_l
    moveml  %sp@,%d2/%a2
    lea.l   %sp@(8),%sp
    rts
| mk_trk(d0 = track) -> d0 = the entry of the sample it plays, or 0
mk_trk:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d0
    bmis    mkt_no
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d0:l:4),%d0
    braw    mk_find
mkt_no:
    moveq   #0,%d0
    rts

| sle_seed(d0 = track): a sample going MAN keeps the slices it had - the
| track's row, Equal or Transient - unless it has markers already. Keeps
| d2-d7, a2.
sle_seed:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    movel   %d0,%d2
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    sls_out
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4   | samples
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d0:l:4),%d0
    beqw    sls_out
    bsr     mk_get
    movea.l %d0,%a2
    tstl    %a2@(4)
    bnes    sls_out               | it has its slices already (or on disk)
    lea.l   sl_S,%a0              | the row, as it was built
    movel   %a0@(0,%d2:l:4),%d3
    beqs    sls_eq
    cmpil   #MK_MAX,%d3
    bhis    sls_eq
    movel   %d2,%d0
    movel   #SLROW,%d1
    mulul   %d1,%d0
    lea.l   sl_tbl,%a0
    addal   %d0,%a0
    moveq   #0,%d1
sls_c:
    movel   %a0@(0,%d1:l:4),%d0
    movel   %d0,%a2@(8,%d1:l:4)
    addql   #1,%d1
    cmpl    %d3,%d1
    bcss    sls_c
    bras    sls_n
sls_eq:
    moveq   #16,%d3               | not built: 16 equal slices
    moveq   #0,%d1
sls_e:
    movel   %d4,%d0
    mulul   %d1,%d0
    lsrl    #4,%d0
    movel   %d0,%a2@(8,%d1:l:4)
    addql   #1,%d1
    cmpl    %d3,%d1
    bcss    sls_e
sls_n:
    movel   %d3,%a2@(4)
    addql   #1,mk_gen
    moveq   #1,%d0                | kept, as a file
    movel   %d0,%a2@(136)
    bsr     mk_post
sls_out:
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    rts

| ---- the slice editor: EDT on Slice's options list, a page of kind MM_SLE ----
| The edited sample is the one sle_trk plays. sle_sel is the slice selected,
| sle_zoom the view: count >> zoom samples across (at least 128), centred on
| the selected slice's start.
| sle_ctx -> d0 = 1 and a2 = the entry, d4 = samples (also sle_cnt), d5 =
| slices; or d0 = 0 (flags from d0). Clobbers d1, a0.
sle_ctx:
    suba.l  %a2,%a2
    movel   sle_trk,%d0
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d0
    bmis    slc_no
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d4
    movel   %d4,sle_cnt
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d0:l:4),%d0
    bsr     mk_find
    tstl    %d0
    beqs    slc_no
    movea.l %d0,%a2
    movel   %a2@(4),%d5
    beqs    slc_no
    moveq   #1,%d0
    rts
slc_no:
    moveq   #0,%d0
    rts
| sle_view (a2 = the entry): sle_v0, sle_sp. Clobbers d0, d1.
sle_view:
    movel   sle_cnt,%d1
    movel   sle_zoom,%d0
    lsrl    %d0,%d1
    cmpil   #128,%d1
    bccs    svw_sp
    movel   sle_cnt,%d1           | no closer than 128 samples (or all of it)
    cmpil   #128,%d1
    blss    svw_sp
    movel   #128,%d1
svw_sp:
    movel   %d1,sle_sp
    movel   sle_sel,%d0
    movel   %a2@(8,%d0:l:4),%d0
    lsrl    #1,%d1
    subl    %d1,%d0
    bpls    svw_lo
    moveq   #0,%d0
svw_lo:
    movel   sle_cnt,%d1
    subl    sle_sp,%d1            | the furthest the view can start
    cmpl    %d1,%d0
    blss    svw_hi
    movel   %d1,%d0
svw_hi:
    movel   %d0,sle_v0
    rts
| d0 = a sample -> d0 = its column in the view, or -1 outside it (sle_colof),
| or clamped to 0..127 (sle_colc). Clobbers d1.
sle_colof:
    subl    sle_v0,%d0
    bmis    sco_no
    cmpl    sle_sp,%d0
    bccs    sco_no
    bras    sco_div
sco_no:
    moveq   #-1,%d0
    rts
sle_colc:
    subl    sle_v0,%d0
    bpls    sco_div
    moveq   #0,%d0
    rts
sco_div:
    movel   sle_sp,%d1
    lsrl    #7,%d1                | samples a column
    bnes    sco_d
    moveq   #1,%d1
sco_d:
    divul   %d1,%d0
    cmpil   #127,%d0
    blss    sco_x
    moveq   #127,%d0
sco_x:
    rts

| sle_knob(d0 = clicks, d1 = the knob): DATA selects a slice; knob 2 moves
| its start a column a click, knob 3 a sixteenth of one (at least a sample),
| knob 4 zooms. Keeps d2-d7, a2-a6.
sle_knob:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a2,%sp@
    movel   %d0,%d2
    movel   %d1,%d3
    bsr     sle_ctx
    beqw    skn_out
    bsr     sle_view
    cmpil   #1,%d3
    beqs    skn_sel
    cmpil   #4,%d3
    beqs    skn_zm
    cmpil   #2,%d3
    beqs    skn_mv
    cmpil   #3,%d3
    bnew    skn_out
skn_mv:
    movel   sle_sp,%d0
    lsrl    #7,%d0                | a column
    cmpil   #3,%d3
    bnes    skn_c
    lsrl    #4,%d0                | fine: a sixteenth of one
skn_c:
    tstl    %d0
    bnes    skn_c1
    moveq   #1,%d0
skn_c1:
    mulsl   %d2,%d0
    bsr     sle_move
    bras    skn_out
skn_sel:
    movel   sle_sel,%d0
    addl    %d2,%d0
    bpls    skn_s1
    moveq   #0,%d0
skn_s1:
    cmpl    %d5,%d0
    bcss    skn_s2
    movel   %d5,%d0
    subql   #1,%d0
skn_s2:
    movel   %d0,sle_sel
    bras    skn_out
skn_zm:
    movel   sle_zoom,%d0
    addl    %d2,%d0
    bpls    skn_z1
    moveq   #0,%d0
skn_z1:
    cmpil   #16,%d0
    blss    skn_z2
    moveq   #16,%d0
skn_z2:
    tstl    %d0                   | no closer than 128 samples across
    beqs    skn_z3
    movel   sle_cnt,%d1
    lsrl    %d0,%d1
    cmpil   #128,%d1
    bccs    skn_z3
    subql   #1,%d0
    bras    skn_z2
skn_z3:
    movel   %d0,sle_zoom
skn_out:
    moveml  %sp@,%d2-%d5/%a2
    lea.l   %sp@(20),%sp
    rts

| sle_move(d0 = samples, signed): the selected slice's start, kept MK_MINL
| from its neighbours (slice 1's is the sample's start and stays). Keeps
| d2-d7, a2-a6.
sle_move:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a2,%sp@
    movel   %d0,%d2
    movel   %d0,sle_dir
    bsr     sle_ctx
    beqs    slm_out
    movel   sle_sel,%d3
    beqs    slm_out
    cmpl    %d5,%d3
    bccs    slm_out
    movel   %a2@(8,%d3:l:4),%d0
    addl    %d2,%d0
    movel   %d4,%d1               | the next start, or the end...
    movel   %d3,%d2
    addql   #1,%d2
    cmpl    %d5,%d2
    bccs    slm_h
    movel   %a2@(12,%d3:l:4),%d1
slm_h:
    subil   #MK_MINL,%d1          | ...less the least length
    cmpl    %d1,%d0
    bles    slm_l
    movel   %d1,%d0
slm_l:
    movel   %a2@(4,%d3:l:4),%d1   | the start before, plus the least length
    addil   #MK_MINL,%d1
    cmpl    %d1,%d0
    bges    slm_set
    movel   %d1,%d0
slm_set:
    tstl    sle_func              | FUNC held: on to a zero crossing
    beqs    slm_w
    bsr     sle_snap
slm_w:
    movel   %d0,%a2@(8,%d3:l:4)
    moveq   #1,%d0
    movel   %d0,%a2@(136)
    addql   #1,mk_gen
slm_out:
    moveml  %sp@,%d2-%d5/%a2
    lea.l   %sp@(20),%sp
    rts

| sle_snap(d0 = the start as moved, d3 = its slice, d4 = samples, a2 = the
| entry) -> d0: on, the way the dial turned (sle_dir), to the first sample
| whose sign differs from the one before it - within 4096 samples and
| MK_MINL of the neighbours - or as it was if there is none. Keeps d2-d7.
sle_snap:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d7,%sp@
    movel   %d0,%d6               | none found: as it was
    movel   %d4,%d7               | the furthest: the next start, or the end,
    movel   %d3,%d1
    addql   #1,%d1
    cmpl    %a2@(4),%d1
    bccs    ssn_h
    movel   %a2@(12,%d3:l:4),%d7
ssn_h:
    subil   #MK_MINL,%d7          | ...less the least length
    movel   %a2@(4,%d3:l:4),%d5
    addil   #MK_MINL,%d5          | the nearest: the start before, plus it
    movel   sle_trk,%d1
    lea.l   track_slot,%a0
    movel   %a0@(0,%d1:l:4),%d1
    bmis    ssn_no
    lea.l   slot_base,%a0
    movea.l %a0@(0,%d1:l:4),%a0
    lea.l   %a0@(64),%a0          | the samples, big-endian 16-bit
    moveq   #1,%d4
    tstl    sle_dir
    bpls    ssn_d
    moveq   #-1,%d4
ssn_d:
    movel   #4096,%d3
ssn_l:
    cmpl    %d5,%d0
    blts    ssn_no
    cmpl    %d7,%d0
    bgts    ssn_no
    mvsw    %a0@(-2,%d0:l:2),%d1  | the sample before
    mvsw    %a0@(0,%d0:l:2),%d2   | ...and this one: signs differ?
    eorl    %d1,%d2
    bmis    ssn_x
    addl    %d4,%d0
    subql   #1,%d3
    bnes    ssn_l
ssn_no:
    movel   %d6,%d0
ssn_x:
    moveml  %sp@,%d2-%d7
    lea.l   %sp@(24),%sp
    rts

| sle_dpress: DATA's press - a marker at the middle of the selected slice,
| which splits it; with FUNC held, the selected slice's marker goes and it
| joins the one before. Keeps d2-d7, a2-a6.
sle_dpress:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a2,%sp@
    bsr     sle_ctx
    beqw    sdp_out
    movel   sle_sel,%d3
    cmpl    %d5,%d3
    bccw    sdp_out
    tstl    sle_func
    bnes    sdp_del
    cmpil   #MK_MAX,%d5
    bccw    sdp_out               | 32 already
    movel   %a2@(8,%d3:l:4),%d2   | its start
    movel   %d4,%d1               | its end
    movel   %d3,%d0
    addql   #1,%d0
    cmpl    %d5,%d0
    bccs    sdp_e
    movel   %a2@(12,%d3:l:4),%d1
sdp_e:
    subl    %d2,%d1               | its length
    cmpil   #2*MK_MINL,%d1
    bcsw    sdp_out               | too short to split
    lsrl    #1,%d1
    addl    %d1,%d2               | the new start
    movel   %d5,%d0               | the later ones up one
sdp_s:
    subql   #1,%d0
    cmpl    %d3,%d0
    bles    sdp_i
    movel   %a2@(8,%d0:l:4),%d1
    movel   %d1,%a2@(12,%d0:l:4)
    bras    sdp_s
sdp_i:
    movel   %d2,%a2@(12,%d3:l:4)
    addql   #1,%d5
    movel   %d5,%a2@(4)
    addql   #1,%d3
    movel   %d3,sle_sel
    bras    sdp_g
sdp_del:
    tstl    %d3
    beqs    sdp_out               | slice 1 starts the sample
    movel   %d3,%d0               | the later ones down one
sdp_d:
    movel   %d0,%d1
    addql   #1,%d1
    cmpl    %d5,%d1
    bccs    sdp_dd
    movel   %a2@(12,%d0:l:4),%d1
    movel   %d1,%a2@(8,%d0:l:4)
    addql   #1,%d0
    bras    sdp_d
sdp_dd:
    subql   #1,%d5
    movel   %d5,%a2@(4)
    subql   #1,%d3
    movel   %d3,sle_sel
sdp_g:
    moveq   #1,%d0
    movel   %d0,%a2@(136)
    addql   #1,mk_gen
sdp_out:
    moveml  %sp@,%d2-%d5/%a2
    lea.l   %sp@(20),%sp
    rts

| sle_off(d0 = note): its note-off on the edited track
sle_off:
    pea     0x40
    movel   %d0,%sp@-
    movel   sle_trk,%sp@-
    jsr     0x4008145e
    lea.l   %sp@(12),%sp
    rts
| sle_tend -> d0 = 1 when the tapped sample has played to its end (its last
| block), which ends tapping. Not in the first 16 blocks, while the trig may
| not have reached the render and the phase is still the last note's.
| Clobbers d0, d1, a0, a1.
sle_tend:
    movel   blk_clk,%d0
    subl    sle_t0,%d0
    cmpil   #16,%d0
    bcss    ste_no
    movel   sle_trk,%d0
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d1
    bmis    ste_stop
    lea.l   slot_count,%a0
    movel   %a0@(0,%d1:l:4),%d1
    subil   #32,%d1
    lsll    #3,%d0
    lea.l   phase_table,%a0
    cmpl    %a0@(0,%d0:l),%d1
    bhis    ste_no
ste_stop:
    bsr     sle_tstop
    moveq   #1,%d0
    rts
ste_no:
    moveq   #0,%d0
    rts
| sle_tstop: tapping ends - its note too. Clobbers d0, d1, a0, a1.
sle_tstop:
    clrl    sle_tap
    tstl    sle_run
    beqs    sts_x
    clrl    sle_run
    moveq   #52,%d0
    bsr     sle_off
sts_x:
    rts
| sle_close: the page gone - the notes its keys hold end. Keeps every register.
sle_close:
    tstl    sle_on
    beqs    scl_x
    lea.l   %sp@(-20),%sp
    moveml  %d0-%d2/%a0-%a1,%sp@
    clrl    sle_on
    bsr     sle_tstop
    bsr     mk_post               | what changed goes to disk
    moveq   #15,%d2
scl_l:
    lea.l   sle_held,%a0
    movel   %a0@(0,%d2:l:4),%d0
    beqs    scl_n
    clrl    %a0@(0,%d2:l:4)
    subql   #1,%d0
    bsr     sle_off
scl_n:
    subql   #1,%d2
    bpls    scl_l
    moveml  %sp@,%d0-%d2/%a0-%a1
    lea.l   %sp@(20),%sp
scl_x:
    rts

| EDT's press (closure, item) on Slice's options list: the track goes MAN
| (keeping the slices it had), then the editor opens over the list
sle_press:
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    movel   gm_track,%d2
    lea.l   sl_md,%a0
    moveq   #2,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    beqs    slp_man
    movel   %d0,%a0@(0,%d2:l:4)
    jsr     opt_mc2cfg            | MAN, seeded
    movel   %d2,%d0
    jsr     state_store
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d1
    beqs    slp_man
    movel   %d2,%d0
    jsr     name_store
slp_man:
    movel   %d2,%d0
    bsr     sle_seed
    moveq   #5,%d0                | MM_SLE
    jsr     mm_open
    tstl    mm_opened
    beqs    slp_out
    movel   mm_track,%d0
    movel   %d0,sle_trk
    clrl    sle_sel
    clrl    sle_zoom
    clrl    sle_func
    clrl    sle_tap
    clrl    sle_run
    lea.l   sle_held,%a0
    moveq   #15,%d0
slp_h:
    clrl    %a0@+
    subql   #1,%d0
    bpls    slp_h
    moveq   #1,%d0
    movel   %d0,sle_on
slp_out:
    moveml  %sp@,%d2/%a2
    lea.l   %sp@(8),%sp
    rts

| SEQ's press (closure, item) on Slice's options list: the track's trigs in
| the pattern on screen, in step order, get notes that walk the sample - the
| first trig slice 1, the next slice 2, round again after the last. The
| track's pattern data is 0x4000cfcc(0x4000f208(0x400cf866()), track), as the
| stock lock wrappers find it (0x4000bb94); a step has a trig when bit 0 of
| its flags word (data + 2 x step) is set, as the trig builder reads it
| (0x40054926); and a trig's note is its Trig Note byte, +580 + step (-1:
| the track's, +712), set by 0x40016642(track data, step, note), which
| tells the pattern's observers - the setter 0x4000abdc picks for param
| 0x0f (its getter 0x40015eaa). The trig params are per-step bytes, not
| p-locks: +128 is Velocity (samplerIY set that), and samplerIZ's lock in
| slot 0 is cleared again here. Slice k is note 52 + k, as the trig keys
| play it. The step
| count is the track's length (0x40016402).
sle_seq:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d6/%a2,%sp@
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000f208            | the pattern
    addql   #4,%sp
    movel   gm_track,%sp@-
    movel   %d0,%sp@-
    jsr     0x4000cfcc            | this track of it
    addql   #8,%sp
    tstl    %d0
    beqw    ssq_out
    movea.l %d0,%a2
    movel   %a2,%sp@-
    jsr     0x40016402            | its length
    addql   #4,%sp
    movel   %d0,%d5
    movel   gm_track,%d0
    lea.l   sl_S,%a0
    movel   %a0@(0,%d0:l:4),%d4   | how many slices
    bnes    ssq_n
    moveq   #16,%d4
ssq_n:
    moveq   #0,%d2                | the step
    moveq   #0,%d3                | trigs set
    moveq   #0,%d6                | the next slice
ssq_l:
    cmpl    %d5,%d2
    bges    ssq_done
    movea.l %a2@,%a0
    movel   %a2,%sp@-
    movea.l %a0@(40),%a0
    jsr     %a0@                  | its steps' data
    addql   #4,%sp
    tstl    %d0
    beqs    ssq_done
    movea.l %d0,%a0
    movew   %a0@(0,%d2:l:2),%d0
    btst    #0,%d0
    beqs    ssq_nx                | no trig here
    clrl    %sp@-                 | lock slot 0 ("None") cleared: samplerIZ
    movel   %d2,%sp@-             | wrote a lock there
    movel   %a2,%sp@-
    jsr     0x400164b0
    lea.l   %sp@(12),%sp
    movel   %d6,%d0
    addil   #52,%d0
    movel   %d0,%sp@-             | the Trig Note
    movel   %d2,%sp@-
    movel   %a2,%sp@-
    jsr     0x40016642
    lea.l   %sp@(12),%sp
    addql   #1,%d3
    addql   #1,%d6
    cmpl    %d4,%d6
    bcss    ssq_nx
    moveq   #0,%d6
ssq_nx:
    addql   #1,%d2
    bras    ssq_l
ssq_done:
    pea     msg_sliced
    tstl    %d3
    bnes    ssq_p
    addql   #4,%sp
    pea     msg_notrigs
ssq_p:
    jsr     show_popup
    addql   #4,%sp
ssq_out:
    moveml  %sp@,%d2-%d6/%a2
    lea.l   %sp@(24),%sp
    rts

| sle_render (d2 = ctx): the page. The top line: "SLICE 3/12" and the
| selected slice's start in seconds; under it a bar along the selected
| slice; then the view's waveform - min..max a column, at most 32 reads each,
| scaled to its loudest - with every marker dotted and the selected slice's
| start solid. Keeps d2-d7.
sle_render:
    lea.l   %sp@(-44),%sp
    moveml  %d2-%d7/%a2-%a6,%sp@
    movea.l %d2,%a4               | ctx
    movea.l %a4@(16),%a5          | its framebuffer and stride, for the
    movel   %a4@(12),%d6          | Start/End view's line helpers
    clrl    %sp@-                 | clear the screen
    pea     63
    pea     127
    clrl    %sp@-
    clrl    %sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    bsr     sle_ctx               | a2 = entry, d4 = samples, d5 = slices
    bnew    slr_go
    pea     sle_s_none
    pea     0x40124b58            | "%s"
    pea     0x12
    pea     27
    pea     64
    pea     SYS_FONT
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    braw    slr_out
slr_go:
    movel   sle_sel,%d0
    cmpl    %d5,%d0
    bcss    slr_s
    movel   %d5,%d0
    subql   #1,%d0
    movel   %d0,sle_sel
slr_s:
    bsr     sle_view
    movel   sle_trk,%d0           | the view's first sample
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d0
    lea.l   slot_base,%a0
    movel   %a0@(0,%d0:l:4),%d0
    addil   #64,%d0
    movea.l %d0,%a3
    movel   sle_v0,%d0
    addl    %d0,%d0
    addal   %d0,%a3
    movel   sle_sp,%d5
    moveq   #0,%d2                | column
    movel   #256,%d7              | the loudest, floored
slr_pk:
    movel   %d2,%d3
    mulul   %d5,%d3
    lsrl    #7,%d3                | the column's first sample
    movel   %d2,%d4
    addql   #1,%d4
    mulul   %d5,%d4
    lsrl    #7,%d4
    subl    %d3,%d4               | how many
    bgts    slr_pn
    moveq   #1,%d4
slr_pn:
    movel   %d4,%d1
    lsrl    #5,%d1                | at most 32 reads
    bnes    slr_ps
    moveq   #1,%d1
slr_ps:
    movea.l #32767,%a1            | min
    movea.l #-32768,%a6           | max
slr_pr:
    cmpl    %d5,%d3
    bccs    slr_pd
    mvsw    %a3@(0,%d3:l:2),%d0
    cmpl    %a1,%d0
    bges    slr_p1
    movea.l %d0,%a1
slr_p1:
    cmpl    %a6,%d0
    bles    slr_p2
    movea.l %d0,%a6
slr_p2:
    addl    %d1,%d3
    subl    %d1,%d4
    bgts    slr_pr
slr_pd:
    cmpal   #32767,%a1
    bnes    slr_pv
    suba.l  %a1,%a1               | nothing read: flat
    suba.l  %a6,%a6
slr_pv:
    lea.l   wf_mn,%a0
    movel   %a1,%d0
    movew   %d0,%a0@(0,%d2:l:2)
    bpls    slr_pa
    negl    %d0
slr_pa:
    cmpl    %d7,%d0
    bles    slr_pb
    movel   %d0,%d7
slr_pb:
    lea.l   wf_mx,%a0
    movel   %a6,%d0
    movew   %d0,%a0@(0,%d2:l:2)
    bpls    slr_pc
    negl    %d0
slr_pc:
    cmpl    %d7,%d0
    bles    slr_pe
    movel   %d0,%d7
slr_pe:
    addql   #1,%d2
    cmpil   #128,%d2
    bcsw    slr_pk
    clrl    wf_ck_h               | the Start/End view's columns are gone
    moveq   #0,%d2
slr_col:
    lea.l   wf_mx,%a0
    mvsw    %a0@(0,%d2:l:2),%d3
    moveq   #26,%d0               | WF_HALF
    mulsl   %d0,%d3
    divsl   %d7,%d3
    negl    %d3
    addil   #WF_MID,%d3           | top row, from the top
    lea.l   wf_mn,%a0
    mvsw    %a0@(0,%d2:l:2),%d4
    moveq   #26,%d0               | WF_HALF
    mulsl   %d0,%d4
    divsl   %d7,%d4
    negl    %d4
    addil   #WF_MID,%d4           | bottom
    cmpil   #WF_TOP,%d3
    bges    slr_c1
    moveq   #10,%d3               | WF_TOP
slr_c1:
    cmpil   #63,%d4
    bles    slr_c2
    moveq   #63,%d4
slr_c2:
    moveq   #63,%d0               | the screen counts y from the bottom
    subl    %d4,%d0
    moveq   #63,%d1
    subl    %d3,%d1
    pea     1
    movel   %d1,%sp@-
    movel   %d2,%sp@-
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    addql   #1,%d2
    cmpil   #128,%d2
    bcsw    slr_col
    movel   %a2@(4),%d5           | the markers: dotted...
    moveq   #1,%d3
slr_m:
    cmpl    %d5,%d3
    bccs    slr_md
    cmpl    sle_sel,%d3
    beqs    slr_mn
    movel   %a2@(8,%d3:l:4),%d0
    bsr     sle_colof
    tstl    %d0
    bmis    slr_mn
    jsr     wf_dotted
slr_mn:
    addql   #1,%d3
    bras    slr_m
slr_md:
    movel   sle_sel,%d3           | ...the selected one solid
    movel   %a2@(8,%d3:l:4),%d0
    bsr     sle_colof
    tstl    %d0
    bmis    slr_bar
    jsr     wf_solid
slr_bar:
    movel   %a2@(8,%d3:l:4),%d0   | the selected slice's extent, a bar on
    movel   %d0,%d4               | row 9 from the top
    bsr     sle_colc
    movel   %d0,%d2               | x0
    movel   sle_cnt,%d1           | its end: the next start, or the sample's
    movel   %d3,%d0
    addql   #1,%d0
    cmpl    %d5,%d0
    bccs    slr_be
    movel   %a2@(12,%d3:l:4),%d1
slr_be:
    movel   sle_v0,%d0
    cmpl    %d0,%d1
    blss    slr_txt               | it ends before the view
    movel   %d0,%d7
    addl    sle_sp,%d7
    cmpl    %d7,%d4
    bccs    slr_txt               | it starts after it
    movel   %d1,%d0
    subql   #1,%d0
    bsr     sle_colc              | x1
    pea     1
    pea     54
    movel   %d0,%sp@-
    pea     54
    movel   %d2,%sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
slr_txt:
    movel   %d5,%sp@-             | SLICE sel/n
    movel   sle_sel,%d0
    addql   #1,%d0
    movel   %d0,%sp@-
    pea     sle_fmt_sl
    pea     0x10
    pea     55
    pea     1
    pea     SYS_FONT
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(32),%sp
    tstl    sle_tap               | tapping: ARMED or TAP, and the playhead
    beqs    slr_time
    pea     sle_s_arm
    tstl    sle_run
    beqs    slr_st
    addql   #4,%sp
    pea     sle_s_tap
slr_st:
    pea     0x40124b58            | "%s"
    pea     0x14
    pea     55
    pea     126
    pea     SYS_FONT
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    tstl    sle_run
    beqw    slr_out
    movel   sle_trk,%d0
    lsll    #3,%d0
    lea.l   phase_table,%a0
    movel   %a0@(0,%d0:l),%d0
    bsr     sle_colof
    tstl    %d0
    bmiw    slr_out
    jsr     wf_solid
    braw    slr_out
slr_time:
    movel   sle_sel,%d3           | its start: seconds and thousandths
    movel   %a2@(8,%d3:l:4),%d0
    moveq   #48,%d1
    divul   %d1,%d0               | ms
    movel   #1000,%d3
    movel   %d0,%d1
    divul   %d3,%d1               | s
    movel   %d1,%d4
    mulul   %d3,%d4
    subl    %d4,%d0               | 0..999
    moveq   #10,%d3
    movel   %d0,%d4
    divul   %d3,%d4               | tens and hundreds
    movel   %d4,%d5
    mulul   %d3,%d5
    subl    %d5,%d0               | units
    movel   %d0,%sp@-
    movel   %d4,%d0
    divul   %d3,%d0               | hundreds
    movel   %d0,%d5
    mulul   %d3,%d5
    subl    %d5,%d4               | tens
    movel   %d4,%sp@-
    movel   %d0,%sp@-
    movel   %d1,%sp@-
    pea     sle_fmt_t
    pea     0x14
    pea     55
    pea     126
    pea     SYS_FONT
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(40),%sp
slr_out:
    moveml  %sp@,%d2-%d7/%a2-%a6
    lea.l   %sp@(44),%sp
    rts

| ---- slice_detect(row, pcm, count, N) -> d0 = slices written, or 0 ----
| 1. Energy per hop: sum of |x| over every 4th sample of each hop of 2^sh
|    samples, sh from 8 (5.3 ms) up until there are at most 4096 hops. Kept in
|    the free 16 KiB above Pluck's delay lines.
| 2. Onset strength: the rise in energy from the previous hop, 0 if it fell.
| 3. Pick up to N-1 of the strongest, each at least a quarter of an average
|    slice from the last, and each above a 32nd of the strongest - so a
|    sample with fewer clear hits gives fewer slices rather than noise.
| 4. Pull each pick back to the hit: the first sample, from a quarter hop
|    before it, that reaches half the picked hop's peak, less 16 samples.
| 5. Sort; slice 0 starts at 0 and the sample's end closes the last.
SD_E     = DLY_BASE + 6*0x2000    | 4096 longs, above the six delay lines
SD_ROW   = 44                     | args, after 40 saved
SD_PCM   = 48
SD_COUNT = 52
SD_N     = 56
slice_detect:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
    movea.l %sp@(SD_PCM),%a3
    movel   %sp@(SD_COUNT),%d4
    moveq   #8,%d7                | sh
sd_sh:
    movel   %d4,%d0
    lsrl    %d7,%d0
    cmpil   #4096,%d0
    blss    sd_shok
    addql   #1,%d7
    bras    sd_sh
sd_shok:
    movel   %d0,%d6               | F, hops
    cmpil   #4,%d6
    bcsw    sd_none
    | 1. energies
    movea.l #SD_E,%a4
    moveq   #0,%d2                | hop
sd_e1:
    movel   %d2,%d3
    lsll    %d7,%d3               | first sample of the hop
    moveq   #1,%d5
    lsll    %d7,%d5
    lsrl    #2,%d5                | samples read per hop
    moveq   #0,%d1                | sum
sd_e2:
    mvsw    %a3@(0,%d3:l:2),%d0
    bpls    sd_e3
    negl    %d0
sd_e3:
    addl    %d0,%d1
    addql   #4,%d3
    subql   #1,%d5
    bnes    sd_e2
    movel   %d1,%a4@(0,%d2:l:4)
    addql   #1,%d2
    cmpl    %d6,%d2
    bcss    sd_e1
    | 2. rises, in place from the top; and the strongest
    movel   %d6,%d2
    subql   #1,%d2
    moveq   #0,%d5                | strongest
sd_f1:
    movel   %a4@(0,%d2:l:4),%d0
    movel   %d2,%d1
    subql   #1,%d1
    subl    %a4@(0,%d1:l:4),%d0
    bpls    sd_f2
    moveq   #0,%d0
sd_f2:
    movel   %d0,%a4@(0,%d2:l:4)
    cmpl    %d5,%d0
    blss    sd_f3
    movel   %d0,%d5
sd_f3:
    subql   #1,%d2
    bnes    sd_f1
    clrl    %a4@
    tstl    %d5
    beqw    sd_none
    lsrl    #5,%d5                | threshold: 1/32 of the strongest rise.
                                  | Simulated on a drum loop: 1/16 missed the
                                  | quiet hats, 1/32 found all 15 hits at 16
                                  | slices with none false
    movel   %d5,%sp@-             | park it: sp@(0) threshold
    | minimum spacing, in hops: F / (4N), at least 1
    movel   %d6,%d0
    movel   %sp@(SD_N+4),%d1
    lsll    #2,%d1
    divul   %d1,%d0
    bnes    sd_ms
    moveq   #1,%d0
sd_ms:
    movea.l %d0,%a5               | a5 = spacing
    | 3. picks, as hop numbers, into row[1..]
    movea.l %sp@(SD_ROW+4),%a2
    moveq   #0,%d3                | found
sd_p1:
    movel   %sp@(SD_N+4),%d0
    subql   #1,%d0
    cmpl    %d0,%d3
    bccs    sd_pdone
    moveq   #0,%d0                | best value
    moveq   #-1,%d1               | best hop
    moveq   #1,%d2
sd_p2:
    cmpl    %a4@(0,%d2:l:4),%d0
    bccs    sd_p3
    movel   %a4@(0,%d2:l:4),%d0
    movel   %d2,%d1
sd_p3:
    addql   #1,%d2
    cmpl    %d6,%d2
    bcss    sd_p2
    cmpl    %sp@,%d0
    blss    sd_pdone              | nothing clear enough is left
    addql   #1,%d3
    movel   %d1,%a2@(0,%d3:l:4)
    movel   %d1,%d2               | clear the neighbourhood
    subl    %a5,%d2
    bpls    sd_p4
    moveq   #0,%d2
sd_p4:
    movel   %d1,%d5
    addl    %a5,%d5
    cmpl    %d6,%d5
    bcss    sd_p5
    movel   %d6,%d5
    subql   #1,%d5
sd_p5:
    clrl    %a4@(0,%d2:l:4)
    addql   #1,%d2
    cmpl    %d5,%d2
    blss    sd_p5
    bras    sd_p1
sd_pdone:
    addql   #4,%sp                | drop the threshold
    tstl    %d3
    beqw    sd_none
    | 4. each pick back to its hit
    moveq   #1,%d2
sd_r1:
    movel   %a2@(0,%d2:l:4),%d0   | hop
    movel   %d0,%d5
    lsll    %d7,%d5               | its first sample
    moveq   #1,%d1
    lsll    %d7,%d1
    movel   %d5,%a0               | a0 = scan end: the hop's end
    addal   %d1,%a0
    cmpal   %d4,%a0
    blss    sd_r2
    movea.l %d4,%a0
sd_r2:
    moveq   #0,%d1                | peak of the hop, full resolution
    movel   %d5,%d0
sd_r3:
    cmpal   %d0,%a0
    blss    sd_r5
    mvsw    %a3@(0,%d0:l:2),%d6
    bpls    sd_r4
    negl    %d6
sd_r4:
    cmpl    %d1,%d6
    blss    sd_r4b
    movel   %d6,%d1
sd_r4b:
    addql   #1,%d0
    bras    sd_r3
sd_r5:
    lsrl    #1,%d1                | half the peak
    moveq   #1,%d0                | scan from a quarter hop before: far enough
    lsll    %d7,%d0               | to catch a hit that straddles the hop
    lsrl    #2,%d0                | boundary, not so far as to land in the
    subl    %d0,%d5               | tail of the hit before
    bpls    sd_r6
    moveq   #0,%d5
sd_r6:
    cmpal   %d5,%a0
    blss    sd_r8                 | not found: keep the hop's own start
    mvsw    %a3@(0,%d5:l:2),%d6
    bpls    sd_r7
    negl    %d6
sd_r7:
    cmpl    %d1,%d6
    bccs    sd_r9
    addql   #1,%d5
    bras    sd_r6
sd_r8:
    movel   %a2@(0,%d2:l:4),%d5
    lsll    %d7,%d5
    bras    sd_r10
sd_r9:
    subil   #16,%d5               | a few samples ahead of the hit
    bpls    sd_r10
    moveq   #0,%d5
sd_r10:
    movel   %d5,%a2@(0,%d2:l:4)
    addql   #1,%d2
    cmpl    %d3,%d2
    blss    sd_r1
    | 5. sort row[1..found] (insertion), then row[0] = 0 and the end
    moveq   #2,%d2
sd_s1:
    cmpl    %d3,%d2
    bhis    sd_s4
    movel   %a2@(0,%d2:l:4),%d0
    movel   %d2,%d1
sd_s2:
    movel   %d1,%d5
    subql   #1,%d5
    beqs    sd_s3
    cmpl    %a2@(0,%d5:l:4),%d0
    bccs    sd_s3
    movel   %a2@(0,%d5:l:4),%d6
    movel   %d6,%a2@(0,%d1:l:4)
    movel   %d5,%d1
    bras    sd_s2
sd_s3:
    movel   %d0,%a2@(0,%d1:l:4)
    addql   #1,%d2
    bras    sd_s1
sd_s4:
    clrl    %a2@
    | drop any start that is not after the one before (or is at 0)
    moveq   #1,%d2                | read
    moveq   #1,%d1                | write
sd_d1:
    cmpl    %d3,%d2
    bhis    sd_d3
    movel   %a2@(0,%d2:l:4),%d0
    movel   %d1,%d5
    subql   #1,%d5
    cmpl    %a2@(0,%d5:l:4),%d0
    blss    sd_d2
    movel   %d0,%a2@(0,%d1:l:4)
    addql   #1,%d1
sd_d2:
    addql   #1,%d2
    bras    sd_d1
sd_d3:
    movel   %d4,%a2@(0,%d1:l:4)   | the end
    movel   %d1,%d0               | slices
    bras    sd_out
sd_none:
    moveq   #0,%d0
sd_out:
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts

| ============== Granular settings: a list menu, like Scale Setup ============
| Built from the firmware's own list-menu class - the base every settings
| menu in the box derives from (ctor 0x400422a8, primary vtable 0x40108bec).
| Scale Setup ("ScaleMenuView", 0x4002f338) is that base plus pad and PAGE
| handling; its primary vtable is the base's entry for entry bar the two
| destructors, so the base alone is a complete menu: the generic key handler
| 0x40075822 turns the knob through rows, edits a row on press, and on
| Return leaves edit mode or closes. Rows are built exactly as Scale Lock's
| Scl/Key are (MENUITEM_CTOR, four closures: label, press, value, turn) and
| owned by the menu through reference-counted holders (0x40072ce6), so they
| go when it does. Opened the way the stock opener at 0x4001cab6 opens Scale
| Setup: 0x240 bytes (the stock subclasses are 0x23c..0x25c; the base's own
| fields end at 0x234), the view at +0x38, holder vtable 0x40100150 - whose
| release deletes through the object's own virtual destructor - presented
| through the root view manager as our other pages are.
| The rows edit the track that was selected when the menu opened.
GM_SIZE = 0x240
gran_menu_open:
    linkw   %fp,#-80
    lea.l   %sp@(-28),%sp
    moveml  %d2-%d4/%a2-%a5,%sp@
    lea.l   mm_opened,%a0
    clrl    %a0@
    moveq   #0,%d0
    movew   %sr,%d0
    andil   #0x0700,%d0
    bnew    gm_done
    tstl    0x40fe4178
    beqw    gm_done
    bsr     gm_live               | already up: swallow the chord, no second copy
    tstl    %d0
    bnew    gm_opened
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    lea.l   %sp@(8),%sp
    movel   %d0,%d2
    cmpil   #MAX_TRK,%d2
    bccw    gm_done
    movel   %d2,%d0
    jsr     sound_obj
    tstl    %d0
    beqw    gm_done
    movea.l %d0,%a0
    moveb   %a0@(38),%d0
    andil   #0xff,%d0
    cmpil   #6,%d0
    bnew    gm_done
    lea.l   loop_mode,%a0         | each mode has its own list of settings
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #6,%d0
    bhiw    gm_done
    lea.l   gm_descs,%a0
    movel   %a0@(0,%d0:l:4),%d0
    lea.l   gm_track,%a0
    movel   %d2,%a0@
    lea.l   gm_cur,%a1
    movel   %d0,%a1@
lm_build:                         | from here on, gm_cur says which menu
    lea.l   ALLOC,%a4
    pea     GM_SIZE
    jsr     %a4@
    addql   #4,%sp
    tstl    %d0
    beqw    gm_done
    movea.l %d0,%a2
    pea     %fp@(-5)              | the title, as a String
    movea.l gm_cur,%a0
    movel   %a0@,%sp@-
    pea     %fp@(-4)
    jsr     FORMAT_STRING
    lea.l   %sp@(12),%sp
    pea     0x4                   | the base menu. Argument 5 is the header icon
    clrl    %sp@-                 | (view +0x98, drawn at 1,1 when non-zero -
    pea     %fp@(-4)              | each stock menu has its own): none here
    pea     0x4
    movea.l gm_cur,%a0
    movel   %a0@(4),%sp@-
    movel   %a2,%sp@-
    jsr     0x400422a8
    lea.l   %sp@(24),%sp
    pea     %fp@(-4)
    jsr     FREE_TINYSTR
    addql   #4,%sp
    lea.l   gm_evt+8,%a0          | our own EncoderHandler vtable (see gm_enc)
    movel   %a0,%a2@(0x3c)
    lea.l   0x40108c78,%a0        | and View vtable (see gm_key_th): the stock
    lea.l   gm_vvt,%a1            | one - offset, typeinfo, 17 slots - with the
    moveq   #18,%d0               | key handler replaced
gm_vcp:
    movel   %a0@+,%a1@+
    subql   #1,%d0
    bpls    gm_vcp
    lea.l   gm_vvt,%a1
    movel   #gm_key_th,%d0
    movel   %d0,%a1@(16)          | slot 2
    lea.l   %a1@(8),%a0
    movel   %a0,%a2@(0x38)
    lea.l   gm_obj,%a0
    movel   %a2,%a0@
    pea     0x1                   | the view flags Scale Setup sets
    pea     %a2@(0x38)
    jsr     0x40075f18
    addql   #8,%sp
    pea     0x2
    pea     %a2@(0x38)
    jsr     0x4007649e
    addql   #8,%sp
    moveq   #0,%d3                | the rows
gm_item:
    movel   %d3,%d4
    lsll    #4,%d4
    movea.l gm_cur,%a0
    addl    %a0@(12),%d4          | d4 = this row's {label, value, turn, press}
    lea.l   %fp@(-72),%a5         | four closures
    pea     0x1
    jsr     %a4@
    addql   #4,%sp
    movel   %d0,%a5@
    clrl    %a5@(4)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a5@(8)
    movea.l %d4,%a0
    movel   %a0@,%d0
    movel   %d0,%a5@(12)
    pea     0x4
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a0
    movel   %a2,%a0@
    movel   %d0,%a5@(16)
    clrl    %a5@(20)
    movel   #SLOT2_MANAGER,%d0
    movel   %d0,%a5@(24)
    movea.l %d4,%a0               | press: edit the row, or the row's action
    movel   %a0@(12),%d0
    movel   %d0,%a5@(28)
    pea     0x1
    jsr     %a4@
    addql   #4,%sp
    movel   %d0,%a5@(32)
    clrl    %a5@(36)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a5@(40)
    movea.l %d4,%a0
    movel   %a0@(4),%d0
    movel   %d0,%a5@(44)
    pea     0x4
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a0
    movel   %a2,%a0@
    movel   %d0,%a5@(48)
    clrl    %a5@(52)
    movel   #SLOT2_MANAGER,%d0
    movel   %d0,%a5@(56)
    movea.l %d4,%a0
    movel   %a0@(8),%d0
    movel   %d0,%a5@(60)
    pea     0x54
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a3
    pea     0x8
    pea     -1
    pea     %a5@(48)
    pea     %a5@(32)
    pea     %a5@(16)
    movel   %a5,%sp@-
    movel   %a3,%sp@-
    jsr     MENUITEM_CTOR
    lea.l   %sp@(28),%sp
    movel   %a3,%sp@-
    movel   %a2,%sp@-
    jsr     MENUVIEW_ADDITEM
    addql   #8,%sp
    pea     %a5@(48)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    pea     %a5@(32)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    pea     %a5@(16)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    movel   %a5,%sp@-
    jsr     FREE_CLOSURE
    addql   #4,%sp
    addql   #1,%d3
    movea.l gm_cur,%a0
    cmpl    %a0@(8),%d3
    bcsw    gm_item
    pea     0x10                  | present it: {view at +0x38, holder}
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a0
    moveq   #1,%d1
    movel   #0x40100150,%d0
    movel   %d0,%a0@
    movel   %d1,%a0@(4)
    movel   %d1,%a0@(8)
    movel   %a2,%a0@(12)
    movel   %a0,%sp@-
    pea     %a2@(0x38)
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8
    addql   #4,%sp
    movea.l %sp,%a0
    clrl    %sp@-
    movel   %a0,%sp@-
    movel   %d0,%sp@-
    jsr     0x4007700e
    lea.l   %sp@(12),%sp
    pea     %sp@(4)
    jsr     0x400cf23c
    lea.l   %sp@(12),%sp
gm_opened:
    lea.l   mm_opened,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
gm_done:
    moveml  %sp@,%d2-%d4/%a2-%a5
    unlk    %fp
    rts

| ---- keys: Track closes, as it does the mode and options menus ----
| (view, event), from slot 2 of the view's vtable (gm_vvt). A fresh Track press
| (down, not a repeat: 0x400724a0) closes the menu through 0x40075ba6 - what
| the list's own key handler calls for Return - and is reported used. Track's
| release, like every other key, goes on to the stock handler thunk 0x4007598e
| unchanged, so the main screen still sees it and the Track LED goes out.
gm_key_th:
    movel   %sp@(8),%sp@-
    jsr     0x4007240c
    addql   #4,%sp
    cmpil   #KEY_TRACK,%d0
    bnes    gm_k_stock
    movel   %sp@(8),%sp@-
    jsr     0x400724a0            | down and not a repeat
    addql   #4,%sp
    tstb    %d0
    beqs    gm_k_stock
    movel   %sp@(4),%d0
    subil   #0x38,%d0             | the menu object
    movel   %d0,%sp@-
    jsr     0x40075ba6            | close
    addql   #4,%sp
    moveq   #1,%d0
    rts
gm_k_stock:
    jmp     0x4007598e

| ---- LEVEL/DATA ----
| The stock list handler (0x40075998, reached through the EncoderHandler base
| at +0x3c) turned out not to move this menu's selection on hardware, and
| edits a value without redrawing - Scale Setup relies on its track observer
| for that, which this menu does not have. So the +0x3c base gets its own
| vtable (gm_evt: the stock group 0x40108cc4 with the handler slot replaced)
| and gm_enc does the same job with the primitives the stock handler uses:
|   - LEVEL/DATA is encoder index 1 (0x4006f6ce); the param knobs, 2..15, are
|     passed down unconsumed, anything else is swallowed - as 0x40075998 does
|   - clicks from 0x4006f73a(ev, 1, 8), as 0x40075998 asks for
|   - a row in edit mode (item +0x50) turns its value (0x400732b6), otherwise
|     vtable[0x18] (0x40072524) moves the selection
|   - and then always 0x40076082 on the view, so both are seen at once.
| gm_enc_gate additionally sits on the one call that delivers encoder events
| (0x400081ce -> 0x40006158): while this menu is on the root view stack,
| LEVEL/DATA goes straight to gm_enc, so no view above it can take it.
gm_enc_th:
    moveq   #-0x3c,%d0            | from the +0x3c base to the object
    addl    %d0,%sp@(4)
gm_enc:                           | (object, event) -> d0 consumed
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    movea.l %sp@(20),%a2
    movea.l %sp@(24),%a3
    movel   %a3@(12),%d0          | encoder index
    cmpil   #1,%d0
    beqs    gm_e_data
    subql   #2,%d0
    cmpil   #13,%d0
    blss    gm_e_pass             | a param knob: the page below has it
    moveq   #1,%d0
    braw    gm_e_out
gm_e_pass:
    moveq   #0,%d0
    braw    gm_e_out
gm_e_data:
    pea     0x8
    pea     0x1
    movel   %a3,%sp@-
    jsr     0x4006f73a
    lea.l   %sp@(12),%sp
    movel   %d0,%d2               | clicks
    beqw    gm_e_done
    movea.l %a2@,%a0
    movea.l %a0@(0x24),%a0        | the selected row, clamped (0x4007266e)
    movel   %a2,%sp@-
    jsr     %a0@
    addql   #4,%sp
    lsll    #3,%d0                | rows: {item, holder} pairs
    movea.l %a2@(4),%a0
    movea.l %a0@(0,%d0:l),%a3
    cmpal   #0,%a3
    beqs    gm_e_move
    tstb    %a3@(0x50)
    beqs    gm_e_move
    movel   %d2,%sp@-             | editing: turn the value
    movel   %a3,%sp@-
    jsr     0x400732b6
    addql   #8,%sp
    bras    gm_e_draw
gm_e_move:
    movea.l %a2@,%a0
    movea.l %a0@(0x18),%a0        | 0x40072524: move the selection
    movel   %d2,%sp@-
    movel   %a2,%sp@-
    jsr     %a0@
    addql   #8,%sp
gm_e_draw:
    pea     %a2@(0x38)
    jsr     0x40076082
    addql   #4,%sp
gm_e_done:
    moveq   #1,%d0
gm_e_out:
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
    rts

| d0 = 1 when gm_obj is a live granular menu on the root view stack: its +0x3c
| still carries gm_evt (destruction resets it) and a stack node holds its view.
gm_live:
    lea.l   gm_obj,%a0
    movel   %a0@,%d0
    beqs    gm_l_no
    movea.l %d0,%a0
    lea.l   gm_evt+8,%a1
    cmpal   %a0@(0x3c),%a1
    bnes    gm_l_no
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8            | the root view manager
    addql   #4,%sp
    movea.l %d0,%a1
    lea.l   %a1@(0x14),%a1        | list sentinel: nodes {next, prev, view, holder}
    lea.l   gm_obj,%a0
    movel   %a0@,%d1
    addil   #0x38,%d1             | our view
    movea.l %a1@,%a0
gm_l_scan:
    cmpal   %a1,%a0
    beqs    gm_l_no
    cmpl    %a0@(8),%d1
    beqs    gm_l_yes
    movea.l %a0@,%a0
    bras    gm_l_scan
gm_l_yes:
    moveq   #1,%d0
    rts
gm_l_no:
    moveq   #0,%d0
    rts

| d0 = 1 when gm_obj's view is the TOP of the root view stack: views are
| added at the list's end (0x4007700e hooks the node before the sentinel,
| 0x400f5a80), so the top is the sentinel's prev. Anything presented over our
| menu - the take name editor, its Yes/Abort/Edit box - is then above it.
gm_top:
    movel   gm_obj,%d0
    beqs    gt_no
    movea.l %d0,%a0
    lea.l   gm_evt+8,%a1
    cmpal   %a0@(0x3c),%a1
    bnes    gt_no                 | not one of ours any more
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8            | the root view manager
    addql   #4,%sp
    movea.l %d0,%a1
    lea.l   %a1@(0x14),%a1        | the sentinel
    movea.l %a1@(4),%a0           | the last node: the top view
    cmpal   %a1,%a0
    beqs    gt_no                 | empty
    movel   gm_obj,%d1
    addil   #0x38,%d1
    cmpl    %a0@(8),%d1
    bnes    gt_no
    moveq   #1,%d0
    rts
gt_no:
    moveq   #0,%d0
    rts

| replaces `jsr 0x40006158` at 0x400081ce: (root, event), result unused there
gm_enc_gate:
    movea.l %sp@(8),%a0
    moveq   #1,%d0
    cmpl    %a0@(12),%d0
    bnes    gm_g_stock
    bsr     gm_top                | our menu, and nothing over it (a name
    tstl    %d0                   | editor or a question box takes the dial)
    beqs    gm_g_stock
    movel   %sp@(8),%sp@-
    lea.l   gm_obj,%a0
    movel   %a0@,%sp@-
    bsr     gm_enc
    addql   #8,%sp
    moveq   #1,%d0
    rts
gm_g_stock:
    jmp     0x40006158

| ---- the rows' closures ----
| label: a0 = the output String; the string pointer arrives in a1.
gm_lab_shape:
    lea.l   gm_s_shape,%a1
    bras    gm_lab
gm_lab_dir:
    lea.l   gm_s_dir,%a1
    bras    gm_lab
gm_lab_frz:
    lea.l   gm_s_frz,%a1
gm_lab:
    link.w  %a6,#-4
    move.l  %d2,-(%a7)
    pea.l   -1(%a6)
    move.l  %a1,-(%a7)
    move.l  %a0,%d2
    move.l  %a0,-(%a7)
    jsr     FORMAT_STRING
    lea.l   0xc(%a7),%a7
    move.l  %d2,%d0
    move.l  -8(%a6),%d2
    unlk    %a6
    rts

| ---- the sample's name on the machine page --------------------------------
| The machine-select page draws the highlighted machine's name from
| sampler_name_table, centred at x 32 in the 5x9 font; the Sampler's entry
| points at mach_nbuf, which nm_tick keeps as NAME_W characters of the
| selected track's sample name ("Sample" when it has none). A longer name
| scrolls slowly: a pause, a character every NM_STEP blocks, a pause at the
| end, round again - and the page, which only redraws on request, is asked to
| each time the text changes. mp_obj is the page, noted by its render hook.
NAME_W   = 7                      | 5x9 font, centred: 7 sit well inside the panel
NM_STEP  = 256                    | 0.17 s a character, as the browser scrolls
NM_PAUSE = 750                    | 0.5 s at each end, as the browser

| nm_calc(d0 = track) -> a1 = the text to show, d0 = the scroll offset now.
| Keeps d2-d7.
nm_calc:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    bsr     nm_text
    moveq   #0,%d2                | length, at most 31
mc_len:
    tstb    %a1@(0,%d2:l)
    beqs    mc_l2
    addql   #1,%d2
    cmpil   #31,%d2
    bcss    mc_len
mc_l2:
    moveq   #0,%d0
    subil   #NAME_W,%d2           | how far it has to scroll
    bles    mc_out
    movel   %d2,%d3
    movel   #NM_STEP,%d1
    mulul   %d1,%d3
    addil   #2*NM_PAUSE,%d3       | one round
    movel   blk_clk,%d0           | wall time in blocks - not 0x8000184c,
                                  | whose units scale with the tempo
    movel   %d0,%d4
    divul   %d3,%d4
    mulul   %d3,%d4
    subl    %d4,%d0               | where in the round
    subil   #NM_PAUSE,%d0
    bpls    mc_mv
    moveq   #0,%d0
    bras    mc_out
mc_mv:
    divul   %d1,%d0
    cmpl    %d2,%d0
    blss    mc_out
    movel   %d2,%d0
mc_out:
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
    rts

| nm_text(d0 = track) -> a1 = what the track plays, as text: its file's name,
| "Unsaved take", "Empty" (CLR), "No sample", or "SMP" + the hash while the
| name is not known yet. Keeps d2-d7.
nm_text:
    lea.l   nm_s_mach,%a1         | no track: the machine's own name
    cmpil   #MAX_TRK,%d0
    bccw    nt_out
    lea.l   track_hash,%a0
    movel   %a0@(0,%d0:l:4),%d1
    lea.l   nm_s_mach,%a1
    beqw    nt_out
    lea.l   nm_s_empty,%a1
    cmpil   #RS_HASH+0xff,%d1
    beqw    nt_out
    movel   %d2,%sp@-
    moveq   #0,%d2
nt_f:
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d2:l:4),%d1
    beqs    nt_hit
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    nt_f
    bras    nt_hex
nt_hit:
    movel   %d1,%d0
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    bnes    nt_file
    lea.l   nm_s_take,%a1
    bras    nt_pop
nt_file:
    movel   %d2,%d0
    lsll    #5,%d0
    addil   #NAME_BASE,%d0
    movea.l %d0,%a1
    tstb    %a1@
    bnes    nt_pop
nt_hex:
    lea.l   nm_hex,%a1            | "SMP" + the hash
    moveb   #83,%a1@+
    moveb   #77,%a1@+
    moveb   #80,%a1@+
    moveq   #28,%d2               | the top nibble first
nt_h:
    movel   %d1,%d0
    lsrl    %d2,%d0
    andil   #15,%d0
    addil   #48,%d0
    cmpil   #58,%d0
    bcss    nt_hd
    addql   #7,%d0
nt_hd:
    moveb   %d0,%a1@+
    subql   #4,%d2
    bpls    nt_h
    clrb    %a1@
    lea.l   nm_hex,%a1
nt_pop:
    movel   %sp@+,%d2
nt_out:
    rts
nm_s_mach:     .asciz "Sample"
nm_s_empty:    .asciz "Empty"
nm_s_take:     .asciz "Unsaved take"
    .balign 2

| nm_clear(d0 = slot): no name yet. Keeps d0-d7.
nm_clear:
    movel   %d0,%sp@-
    lsll    #5,%d0
    addil   #NAME_BASE,%d0
    movea.l %d0,%a0
    clrb    %a0@
    movel   %sp@+,%d0
    rts

| nm_step: on the UI clock, names one slot that still needs it. The file
| system is asked for the inode's size first (0x4007eb16) - it must be the
| size the inode record gave, or the inode number is not what the file system
| means by one and nothing is taken - then for its full path (0x4007afd4:
| built back from the file to the root into PATH_BUF, 0 on failure), whose
| last part is the name. Keeps d2-d7.
nm_step:
    tstl    0x40f07cf4            | the file system is up
    beqw    nms_out
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    moveq   #0,%d2
nms_f:
    lea.l   slot_nino,%a0
    movel   %a0@(0,%d2:l:4),%d3
    beqs    nms_n
    lea.l   slot_npth,%a0         | -2: not tried yet
    moveq   #-2,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnes    nms_n
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    bnes    nms_go
nms_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    nms_f
    braw    nms_done
nms_go:
    lea.l   slot_npth,%a0         | tried once, whatever happens: -3 until the
    moveq   #-3,%d0               | sizes agree and a path is asked for
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d3,%sp@-
    jsr     0x4007eb16            | its size, as the file system has it
    addql   #4,%sp
    lea.l   slot_nfsz,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   slot_nisz,%a0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnew    nms_done
    pea     PATH_BUF
    clrl    %sp@-
    movel   %d3,%sp@-
    jsr     0x4007afd4
    lea.l   %sp@(12),%sp
    movel   %d0,%d1               | DIAG
    subil   #PATH_BUF,%d1
    tstl    %d0
    bnes    nms_pd
    moveq   #-1,%d1
nms_pd:
    lea.l   slot_npth,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    cmpil   #PATH_BUF,%d0         | a pointer into PATH_BUF, or nothing
    bcsw    nms_done
    cmpil   #PATH_BUF+0x100,%d0
    bccw    nms_done
    movea.l %d0,%a0               | past the last '/'
    movea.l %d0,%a1
nms_s:
    mvzb    %a0@+,%d1
    tstl    %d1
    beqs    nms_e
    cmpil   #47,%d1               | '/'
    bnes    nms_s
    movea.l %a0,%a1
    bras    nms_s
nms_e:
    movel   %d2,%d0
    lsll    #5,%d0
    addil   #NAME_BASE,%d0
    movea.l %d0,%a2
    moveq   #30,%d4
nms_c:
    moveb   %a1@+,%d1
    moveb   %d1,%a2@+
    beqs    nms_done
    subql   #1,%d4
    bpls    nms_c
    clrb    %a2@
nms_done:
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
nms_out:
    rts

| nm_tick: on the UI clock. While the machine page is up, mach_nbuf follows
| the selected track's sample name and the page redraws when it changes.
| Keeps d2-d7.
nm_tick:
    tstl    mp_obj
    beqw    ntk_out
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    jsr     0x400d0974            | is the page on the root view stack?
    movel   %d0,%sp@-
    jsr     0x400060d8
    addql   #4,%sp
    movea.l %d0,%a1
    lea.l   %a1@(0x14),%a1        | nodes {next, prev, view, holder}
    movel   mp_obj,%d1
    movea.l %a1@,%a0
ntk_scan:
    cmpal   %a1,%a0
    beqw    ntk_gone
    cmpl    %a0@(8),%d1
    beqs    ntk_live
    movea.l %a0@,%a0
    bras    ntk_scan
ntk_live:
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    addql   #8,%sp
    bsr     nm_calc               | a1 = text, d0 = offset
    adda.l  %d0,%a1
    lea.l   mach_nbuf,%a2         | the window: changed?
    moveq   #NAME_W-1,%d2
    moveq   #0,%d1                | 1 once anything differs
ntk_c:
    moveb   %a1@+,%d0
    cmpb    %a2@,%d0
    beqs    ntk_same
    moveq   #1,%d1
ntk_same:
    moveb   %d0,%a2@+
    tstb    %d0
    beqs    ntk_end
    subql   #1,%d2
    bpls    ntk_c
    tstb    %a2@
    beqs    ntk_end
    clrb    %a2@
    moveq   #1,%d1
ntk_end:
    tstl    %d1
    beqs    ntk_pop
    movel   mp_obj,%sp@-          | redraw, with the new text
    jsr     0x40076082
    addql   #4,%sp
    bras    ntk_pop
ntk_gone:
    clrl    mp_obj
ntk_pop:
    moveml  %sp@,%d2/%a2
    lea.l   %sp@(8),%sp
ntk_out:
    rts
    .globl  mp_obj, mach_nbuf     | blob_a_phase1's page hook and name table
    .balign 4
mp_obj:        .long 0          | the machine page, while it is up
blk_clk:       .long 0          | audio blocks rendered (rs_out)
mach_nbuf:     .asciz "Sample"  | what it shows as the Sampler's name
               .space 12
    .balign 4                     | code follows: keep it even

| value: Scale Lock's value_invoker, the string from a1 = names, a0 = values
gm_val_shape:
    lea.l   gr_shape,%a0
    lea.l   gm_n_shape,%a1
    bras    gm_valt
gm_val_dir:
    lea.l   gr_dir,%a0
    lea.l   gm_n_dir,%a1
    bras    gm_valt
gm_val_frz:
    lea.l   gr_frz,%a0
    lea.l   gm_n_frz,%a1
gm_valt:                          | a0 = a per-track table: this track's entry
    move.l  gm_track,%d0
    lsl.l   #2,%d0
    adda.l  %d0,%a0
gm_val:                           | a0 = &value, a1 = its names
    link.w  %a6,#-0x30
    movem.l %d2-%d4/%a2-%a5,(%a7)
    move.l  (%a0),%d0
    move.l  0(%a1,%d0.l*4),%d0    | the value's name
    move.l  #0x40fe4278,%d1
    move.l  %d1,-0x10(%a6)
    lea.l   FREE_TINYSTR,%a2
    move.l  %a6,%d2
    subq.l  #8,%d2
    move.l  %a6,%d3
    addi.l  #-0x10,%d3
    move.l  %d0,-(%a7)
    move.l  %d3,-(%a7)
    jsr     TINYSTR_WRAP
    addq.l  #8,%a7
    pea.l   0x40140ab0
    move.l  %d2,-(%a7)
    move.l  -0x10(%a6),%d4
    jsr     DRAW_FMT_A
    move.l  %d4,-(%a7)
    movea.l 0x14(%a6),%a0
    pea.l   4
    move.l  0x18(%a6),-(%a7)
    lea.l   0x18(%a0),%a0
    move.l  %a0,-(%a7)
    move.l  %d2,-(%a7)
    move.l  0x10(%a6),-(%a7)
    jsr     DRAW_TEXT
    lea.l   0x1c(%a7),%a7
    move.l  %d2,(%a7)
    jsr     DRAW_FMT_B
    move.l  %d3,-(%a7)
    jsr     (%a2)
    addq.l  #8,%a7
    movem.l -0x30(%a6),%d2-%d4/%a2-%a5
    unlk    %a6
    rts

| turn: Scale Lock's slot4 invoker; a1 = values, d1 = how many. Clamped,
| saved with the name token, then the same redraw Scale Lock uses.
gm_rot_shape:
    lea.l   gr_shape,%a1
    moveq   #4,%d1
    bras    gm_rot
gm_rot_dir:
    lea.l   gr_dir,%a1
    moveq   #3,%d1
    bras    gm_rot
gm_rot_frz:
    lea.l   gr_frz,%a1
    moveq   #2,%d1
gm_rot:
    lea.l   -24(%a7),%a7
    movem.l %d2-%d4/%a2-%a4,(%a7)
    move.l  36(%a7),%d4           | the turn
    move.l  gm_track,%d2
    move.l  0(%a1,%d2.l*4),%d0
    tst.l   %d4
    beq.b   gm_r_draw
    bgt.b   gm_r_up
    subq.l  #1,%d0
    bpl.b   gm_r_set
    moveq   #0,%d0
    bra.b   gm_r_set
gm_r_up:
    addq.l  #1,%d0
    cmp.l   %d1,%d0
    bcs.b   gm_r_set
    move.l  %d1,%d0
    subq.l  #1,%d0
gm_r_set:
    move.l  %d0,0(%a1,%d2.l*4)
    jsr     opt_mc2cfg            | Slice's two rows -> sl_cfg
    move.l  %d2,%d0
    jsr     state_store
    lea.l   track_hash,%a0
    move.l  0(%a0,%d2.l*4),%d1
    beq.b   gm_r_draw
    move.l  %d2,%d0
    jsr     name_store
gm_r_draw:
    jsr     0x400cf866
    move.l  %d0,-(%a7)
    jsr     0x4000f208
    addq.l  #4,%a7
    move.l  %d0,-(%a7)
    jsr     0x4000d0dc
    addq.l  #4,%a7
    movea.l %d0,%a0
    movea.l (%a0),%a1
    movea.l 0x10(%a1),%a1
    move.l  %a0,-(%a7)
    jsr     (%a1)
    addq.l  #4,%a7
    movem.l (%a7),%d2-%d4/%a2-%a4
    lea.l   24(%a7),%a7
    rts

    .align 4
gm_obj:        .long 0          | the last granular menu opened (see gm_live)
| EncoderHandler vtable for the menu's +0x3c base: offset-to-top and typeinfo
| as the stock group at 0x40108cc4, the two destructor thunks, our handler
gm_evt:        .long 0xffffffc4, 0x40108bd8, 0x400d9726, 0x400d977a, gm_enc_th
gm_vvt:        .space 76        | the View vtable copy, built in gran_menu_open
gm_track:      .long 0
gm_cur:        .long gm_desc_gran   | the menu being built / shown
| a list menu: title, view name, rows, and per row {label, value, turn, press}
gm_descs:      .long gm_desc_os, gm_desc_lp, gm_desc_sl, gm_desc_gran
               .long gm_desc_st, gm_desc_pk, gm_desc_wv
gm_desc_os:    .long mo_t_os, gm_vname, 3, mo_i_os
gm_desc_lp:    .long mo_t_lp, gm_vname, 5, mo_i_lp
gm_desc_sl:    .long mo_t_sl, gm_vname, 6, mo_i_sl
gm_desc_gran:  .long gm_title, gm_vname, 4, gm_items
gm_desc_st:    .long mo_t_st, gm_vname, 2, mo_i_st
gm_desc_pk:    .long mo_t_pk, gm_vname, 3, mo_i_pk
gm_desc_wv:    .long mo_t_wv, gm_vname, 1, mo_i_chn
gm_items:      .long gm_lab_shape, gm_val_shape, gm_rot_shape, new_slot2_invoker
               .long gm_lab_dir,   gm_val_dir,   gm_rot_dir,   new_slot2_invoker
               .long gm_lab_frz,   gm_val_frz,   gm_rot_frz,   new_slot2_invoker
               .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
mo_i_os:       .long mo_l_efx, mo_v_efx, mo_r_efx, new_slot2_invoker
               .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
               .long mo_l_stu, mo_v_stu, mo_r_stu, new_slot2_invoker
mo_i_lp:       .long mo_l_typ, mo_v_typ, mo_r_typ, new_slot2_invoker
               .long mo_l_xfd, mo_v_xfd, mo_r_xfd, new_slot2_invoker
               .long mo_l_syn, mo_v_syn, mo_r_syn, new_slot2_invoker
               .long mo_l_efx, mo_v_efx, mo_r_efx, new_slot2_invoker
               .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
mo_i_sl:       .long mo_l_mod, mo_v_slm, mo_r_slm, new_slot2_invoker
               .long mo_l_slc, mo_v_slc, mo_r_slc, new_slot2_invoker
               .long mo_l_efx, mo_v_efx, mo_r_efx, new_slot2_invoker
               .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
               .long mo_l_edt, mo_v_edt, rs_rot_none, sle_press
               .long mo_l_seq, mo_v_edt, rs_rot_none, sle_seq
mo_i_st:       .long mo_l_mod, mo_v_stm, mo_r_stm, new_slot2_invoker
               .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
mo_i_pk:       .long mo_l_mod, mo_v_pkm, mo_r_pkm, new_slot2_invoker
               .long mo_l_exc, mo_v_exc, mo_r_exc, new_slot2_invoker
mo_i_chn:      .long mo_l_chn, mo_v_chn, mo_r_chn, new_slot2_invoker
mo_n_efx:      .long mo_s_flt, mo_s_lof, mo_s_tap, mo_s_vin, gm_v_off
mo_n_chn:      .long mo_s_mon, mo_s_ste
mo_n_stu:      .long gm_v_off, mo_s_4, mo_s_8, mo_s_16, mo_s_32, mo_s_8t, mo_s_16t
mo_n_typ:      .long mo_s_fwd, mo_s_rev, mo_s_pp
mo_n_xfd:      .long gm_v_off, mo_s_10, mo_s_25, mo_s_50, mo_s_100, mo_s_250
mo_n_syn:      .long gm_v_off, rs_s_1, rs_s_2, rs_s_4
mo_n_slm:      .long mo_s_eql, mo_s_trn, mo_s_man
mo_n_go:       .long mo_s_go
sle_n_cb:      .long sle_cbuf
mo_n_slc:      .long rs_s_8, rs_s_16, mo_s_32n
mo_n_stm:      .long mo_s_fwd, mo_s_rev, mo_s_1fw, mo_s_1rv, mo_s_sy1, mo_s_sy2
               .long mo_s_sy4
mo_n_pkm:      .long mo_s_syn, mo_s_drm
mo_n_exc:      .long mo_s_smp, mo_s_nse, mo_s_clk
gm_n_shape:    .long gm_v_hann, gm_v_tri, gm_v_perc, gm_v_sq
gm_n_dir:      .long gm_v_fwd, gm_v_rev, gm_v_rand
gm_n_frz:      .long gm_v_off, gm_v_on
gm_title:      .asciz "Granular"
gm_vname:      .asciz "GranularMenuView"
mo_t_os:       .asciz "One shot"
mo_t_lp:       .asciz "Loop"
mo_t_sl:       .asciz "Slice"
mo_t_st:       .asciz "Stretch"
mo_t_pk:       .asciz "Pluck"
mo_t_wv:       .asciz "Wave"
mo_s_efx:      .asciz "EFX"
mo_s_chnl:     .asciz "CHN"
mo_s_stul:     .asciz "STU"
mo_s_typl:     .asciz "TYP"
mo_s_xfdl:     .asciz "XFD"
mo_s_synl:     .asciz "SYN"
mo_s_modl:     .asciz "MOD"
mo_s_slcl:     .asciz "SLC"
mo_s_excl:     .asciz "EXC"
mo_s_flt:      .asciz "FLT"
mo_s_lof:      .asciz "LOF"
mo_s_tap:      .asciz "TAP"
mo_s_vin:      .asciz "VIN"
mo_s_mon:      .asciz "MON"
mo_s_ste:      .asciz "STE"
mo_s_4:        .asciz "1/4"
mo_s_8:        .asciz "1/8"
mo_s_16:       .asciz "1/16"
mo_s_32:       .asciz "1/32"
mo_s_8t:       .asciz "8T"
mo_s_16t:      .asciz "16T"
mo_s_fwd:      .asciz "FWD"
mo_s_rev:      .asciz "REV"
mo_s_pp:       .asciz "P-P"
mo_s_10:       .asciz "10"
mo_s_25:       .asciz "25"
mo_s_50:       .asciz "50"
mo_s_100:      .asciz "100"
mo_s_250:      .asciz "250"
mo_s_eql:      .asciz "EQL"
mo_s_trn:      .asciz "TRN"
mo_s_man:      .asciz "MAN"
mo_s_edtl:     .asciz "EDT"
mo_s_seql:     .asciz "SEQ"
msg_sliced:    .asciz "Trigs set to\nthe slices"
msg_notrigs:   .asciz "No trigs on\nthis track"
mo_s_go:       .asciz "GO"
sle_s_none:    .asciz "NO SAMPLE"
sle_fmt_sl:    .asciz "SLICE %d/%d"
sle_fmt_t:     .asciz "%d.%d%d%dS"
sle_s_arm:     .asciz "ARMED"
mk_s_dir:      .asciz "/Slices/"
sle_s_tap:     .asciz "TAP"
mo_s_32n:      .asciz "32"
mo_s_1fw:      .asciz "1FW"
mo_s_1rv:      .asciz "1RV"
mo_s_sy1:      .asciz "SY1"
mo_s_sy2:      .asciz "SY2"
mo_s_sy4:      .asciz "SY4"
mo_s_syn:      .asciz "SYN"
mo_s_drm:      .asciz "DRM"
mo_s_smp:      .asciz "SMP"
mo_s_nse:      .asciz "NSE"
mo_s_clk:      .asciz "CLK"
    .align 2
| ---- the rows: label, value (a per-track table and its names) and turn
| (the table and how many values), each handing on to the granular list's
| own gm_lab / gm_valt / gm_rot
mo_l_efx:  lea.l mo_s_efx,%a1
           braw  gm_lab
mo_l_chn:  lea.l mo_s_chnl,%a1
           braw  gm_lab
mo_l_stu:  lea.l mo_s_stul,%a1
           braw  gm_lab
mo_l_typ:  lea.l mo_s_typl,%a1
           braw  gm_lab
mo_l_xfd:  lea.l mo_s_xfdl,%a1
           braw  gm_lab
mo_l_syn:  lea.l mo_s_synl,%a1
           braw  gm_lab
mo_l_mod:  lea.l mo_s_modl,%a1
           braw  gm_lab
mo_l_slc:  lea.l mo_s_slcl,%a1
           braw  gm_lab
mo_l_exc:  lea.l mo_s_excl,%a1
           braw  gm_lab
mo_l_edt:  lea.l mo_s_edtl,%a1
           braw  gm_lab
mo_l_seq:  lea.l mo_s_seql,%a1
           braw  gm_lab
mo_v_efx:  lea.l fx_sel,%a0
           lea.l mo_n_efx,%a1
           braw  gm_valt
mo_v_chn:  lea.l chn_sel,%a0
           lea.l mo_n_chn,%a1
           braw  gm_valt
mo_v_stu:  lea.l stu_sel,%a0
           lea.l mo_n_stu,%a1
           braw  gm_valt
mo_v_typ:  lea.l lp_type,%a0
           lea.l mo_n_typ,%a1
           braw  gm_valt
mo_v_xfd:  lea.l lp_xfd,%a0
           lea.l mo_n_xfd,%a1
           braw  gm_valt
mo_v_syn:  lea.l lp_sync,%a0
           lea.l mo_n_syn,%a1
           braw  gm_valt
mo_v_slm:  lea.l sl_md,%a0
           lea.l mo_n_slm,%a1
           braw  gm_valt
mo_v_slc:  movel gm_track,%d0
           lea.l sl_md,%a1
           moveq #2,%d1
           cmpl  %a1@(0,%d0:l:4),%d1
           beqs  mo_v_slcm
           lea.l sl_ct,%a0
           lea.l mo_n_slc,%a1
           braw  gm_valt
mo_v_slcm:                        | MAN: how many the markers make, or --
           jsr   mk_trk
           lea.l sle_cbuf,%a1
           tstl  %d0
           beqs  mvs_none
           movea.l %d0,%a0
           movel %a0@(4),%d0
           beqs  mvs_none
           moveq #48,%d1
mvs_t:     cmpil #10,%d0
           bcss  mvs_u
           subil #10,%d0
           addql #1,%d1
           bras  mvs_t
mvs_u:     cmpil #48,%d1
           beqs  mvs_1
           moveb %d1,%a1@+
mvs_1:     addil #48,%d0
           moveb %d0,%a1@+
           clrb  %a1@
           bras  mvs_go
mvs_none:  moveb #45,%a1@+
           moveb #45,%a1@+
           clrb  %a1@
mvs_go:    lea.l rs_zero,%a0
           lea.l sle_n_cb,%a1
           braw  gm_val
mo_v_edt:  lea.l rs_zero,%a0
           lea.l mo_n_go,%a1
           braw  gm_val
mo_v_stm:  lea.l st_opt,%a0
           lea.l mo_n_stm,%a1
           braw  gm_valt
mo_v_pkm:  lea.l pk_mode,%a0
           lea.l mo_n_pkm,%a1
           braw  gm_valt
mo_v_exc:  lea.l pk_exc,%a0
           lea.l mo_n_exc,%a1
           braw  gm_valt
mo_r_efx:  lea.l fx_sel,%a1
           moveq #5,%d1
           braw  gm_rot
mo_r_chn:  lea.l chn_sel,%a1
           moveq #2,%d1
           braw  gm_rot
mo_r_stu:  lea.l stu_sel,%a1
           moveq #7,%d1
           braw  gm_rot
mo_r_typ:  lea.l lp_type,%a1
           moveq #3,%d1
           braw  gm_rot
mo_r_xfd:  lea.l lp_xfd,%a1
           moveq #6,%d1
           braw  gm_rot
mo_r_syn:  lea.l lp_sync,%a1
           moveq #4,%d1
           braw  gm_rot
mo_r_slm:  lea.l sl_md,%a1
           moveq #3,%d1
           braw  gm_rot
mo_r_slc:  movel gm_track,%d0     | MAN: the markers decide
           lea.l sl_md,%a1
           moveq #2,%d1
           cmpl  %a1@(0,%d0:l:4),%d1
           beqs  mo_r_x
           lea.l sl_ct,%a1
           moveq #3,%d1
           braw  gm_rot
mo_r_x:    rts
mo_r_stm:  lea.l st_opt,%a1
           moveq #7,%d1
           braw  gm_rot
mo_r_pkm:  lea.l pk_mode,%a1
           moveq #2,%d1
           braw  gm_rot
mo_r_exc:  lea.l pk_exc,%a1
           moveq #3,%d1
           braw  gm_rot
| three letters each: the value column starts well right of the label
gm_s_shape:    .asciz "SHP"
gm_s_dir:      .asciz "DIR"
gm_s_frz:      .asciz "FRZ"
gm_v_hann:     .asciz "HAN"
gm_v_tri:      .asciz "TRI"
gm_v_perc:     .asciz "PRC"
gm_v_sq:       .asciz "SQR"
gm_v_fwd:      .asciz "FWD"
gm_v_rev:      .asciz "REV"
gm_v_rand:     .asciz "RND"
gm_v_off:      .asciz "OFF"
gm_v_on:       .asciz "ON"
    .align 4

| ============== Track + Preset: the playback-mode menu ======================
| A page built from the stock machine-select page ("DrumSelect", ctor
| 0x400a22b0, 0xd0 bytes, vtable group 0x40117918..0x401179c8), drawn and
| driven by our own handlers. Construction, the view stack and destruction are
| all the stock page's; only the object's first two vtable pointers are pointed
| at a private copy of the group (mm_vt), in which exactly the machine-page
| specific entries are replaced:
|   +0x08 / +0x0c  destructors      -> mm_dtor0 / mm_dtor1 (forget the page)
|   +0x10          key handler      (0x400a292c) -> mm_key
|   +0x18          render           (0x400a24ca) -> mm_render
|   +0x4c          encoder handler  (0x400a28b4) -> mm_enc
|   +0x60          encoder thunk for the base at +4 (0x400a2926) -> mm_enc_th
| (offsets are into the copy, which starts at 0x40117918; the primary vptr is
| copy+8 and the +4 base's is copy+0x58). The four other base vtables hold no
| machine-page code and stay stock. It is pushed exactly as show_popup pushes
| its popup, which already works from inside this very key accessor.
MM_SIZE   = 0xd0
MM_SYS    = 3                     | mm_kind: the System page (sys_render)
MM_RTG    = 4                     | mm_kind: the retrig page (rtg_render)
MM_SLE    = 5                     | mm_kind: the slice editor (sle_render)
MM_VT_SRC = 0x40117918
MM_VT_LEN = 0xb0
| The page serves three menus: kind 0 the playback mode (Track + Preset), and
| on Track + key 6 the current mode's options - kind 1 for Slice (count and
| detection), kind 2 for One shot (Normal / Lo-fi). Other modes have none, and
| key 6 then does what it always did. mm_opened says whether a menu came up.
mode_menu_open:
    moveq   #0,%d0                | and on into mm_open
mm_open:
    lea.l   mm_kind_req,%a0
    movel   %d0,%a0@
    lea.l   mm_opened,%a0
    clrl    %a0@
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d4/%a2-%a4,%sp@
    moveq   #0,%d0                | UI thread only, as loop_toggle was
    movew   %sr,%d0
    andil   #0x0700,%d0
    bnew    mm_o_done
    lea.l   mm_obj,%a0
    tstl    %a0@
    bnew    mm_o_done             | already up
    tstl    0x40fe4178
    beqw    mm_o_done             | view machinery not up yet
    moveq   #MM_SYS,%d0           | the System and retrig pages: no track,
    cmpl    mm_kind_req,%d0       | no Sampler
    beqw    mm_o_kind
    moveq   #MM_RTG,%d0
    cmpl    mm_kind_req,%d0
    beqw    mm_o_kind
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    lea.l   %sp@(8),%sp
    movel   %d0,%d2
    cmpil   #MAX_TRK,%d2
    bccw    mm_o_done
    movel   %d2,%d0
    jsr     sound_obj
    tstl    %d0
    beqw    mm_o_done
    movea.l %d0,%a2
    moveb   %a2@(38),%d0
    andil   #0xff,%d0
    cmpil   #6,%d0
    bnew    mm_o_done             | not a Sampler track: the chord means nothing
    lea.l   mm_track,%a0
    movel   %d2,%a0@
    lea.l   mm_kind_req,%a0
    movel   %a0@,%d0
    bpls    mm_o_kind
    lea.l   loop_mode,%a0         | options: which menu, if any
    movel   %a0@(0,%d2:l:4),%d1
    moveq   #1,%d0
    cmpil   #2,%d1
    beqs    mm_o_kind             | Slice has its own
    cmpil   #6,%d1
    bhiw    mm_o_done
    lea.l   opt_menus,%a0         | the rest: an option list, if the mode has one
    movel   %a0@(0,%d1:l:4),%d0
    beqw    mm_o_done
    lea.l   mm_desc,%a0
    movel   %d0,%a0@
    moveq   #2,%d0
mm_o_kind:
    lea.l   mm_kind,%a0
    movel   %d0,%a0@
    | the private vtable group, rebuilt each time from the stock one
    lea.l   MM_VT_SRC,%a0
    lea.l   mm_vt,%a1
    moveq   #(MM_VT_LEN/4)-1,%d0
mm_o_cp:
    movel   %a0@+,%a1@+
    subql   #1,%d0
    bpls    mm_o_cp
    lea.l   mm_vt,%a1
    movel   #mm_dtor0,%d0
    movel   %d0,%a1@(0x08)
    movel   #mm_dtor1,%d0
    movel   %d0,%a1@(0x0c)
    movel   #mm_key,%d0
    movel   %d0,%a1@(0x10)
    movel   #mm_render,%d0
    movel   %d0,%a1@(0x18)
    movel   #mm_enc,%d0
    movel   %d0,%a1@(0x4c)
    movel   #mm_enc_th,%d0
    movel   %d0,%a1@(0x60)
    lea.l   0x400802e0,%a3        | operator new
    pea     MM_SIZE
    jsr     %a3@
    addql   #4,%sp
    tstl    %d0
    beqw    mm_o_done
    movea.l %d0,%a4
    movel   %a4,%sp@-
    jsr     0x400a22b0            | the stock machine-select constructor
    addql   #4,%sp
    lea.l   mm_vt,%a1
    lea.l   %a1@(8),%a0
    movel   %a0,%a4@              | primary vptr
    lea.l   %a1@(0x58),%a0
    movel   %a0,%a4@(4)           | the +4 base (encoder events)
    lea.l   mm_obj,%a0
    movel   %a4,%a0@
    pea     0x10                  | the reference holder, as the stock opener
    jsr     %a3@                  | at 0x4001ca40 builds it
    addql   #4,%sp
    movea.l %d0,%a0
    moveq   #1,%d1
    movel   #0x401000c4,%d0
    movel   %d0,%a0@
    movel   %d1,%a0@(4)
    movel   %d1,%a0@(8)
    movel   %a4,%a0@(12)
    movel   %a0,%sp@-             | {page, holder} on the stack, holder on top
    movel   %a4,%sp@-
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8
    addql   #4,%sp
    movea.l %sp,%a0
    clrl    %sp@-
    movel   %a0,%sp@-
    movel   %d0,%sp@-
    jsr     0x4007700e            | present
    lea.l   %sp@(12),%sp
    pea     %sp@(4)               | drop our reference to the holder
    jsr     0x400cf23c
    lea.l   %sp@(12),%sp          | that pea, and the pair
    lea.l   mm_opened,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
mm_o_done:
    moveml  %sp@,%d2-%d4/%a2-%a4
    lea.l   %sp@(24),%sp
    rts

| ---- the page's destructors: forget it, then the stock ones ----
mm_dtor0:
    lea.l   mm_obj,%a0
    clrl    %a0@
    clrl    rtg_on                | the retrig page is gone: repeats fade out
    jsr     sle_close             | the slice editor's notes end
    jmp     0x400f43ca
mm_dtor1:
    lea.l   mm_obj,%a0
    clrl    %a0@
    clrl    rtg_on
    jsr     sle_close
    jmp     0x400f4486

| ---- keys: Return, Preset or Track closes; the rest is the stock base's ----
| (this, event).
| Return (code 12) is handled exactly as the machine page handles it
| (0x400a292c): the page closes when the event has flag bit 4 (0x40072434),
| and the key is reported used either way.
| Preset and Track close on a fresh press only (down, not a repeat:
| 0x400724a0). Every other Preset/Track event - above all Track's RELEASE after
| the chord that opened the menu - goes to the stock dispatch like any other
| key. Claiming those left the main screen waiting for a Track release that
| never came, so its Track LED stayed lit. A Preset press swallowed by the
| chord reads back as code 0, so the press that opened the menu cannot close it.
MM_KEY_RETURN = 12
MM_KEY_DATA   = 32  | the DATA knob's press: the stock list (0x40075822)
                    | edits its row on code 32 once 0x40072434 says so
mm_key:
    lea.l   %sp@(-8),%sp
    moveml  %d2/%a2,%sp@
    movea.l %sp@(12),%a2
    movel   %sp@(16),%d2
    movel   %d2,%sp@-
    jsr     0x4007240c
    addql   #4,%sp
    moveq   #MM_SLE,%d1           | the slice editor: DATA's press adds a
    cmpl    mm_kind,%d1           | marker, with FUNC removes one
    bnes    mm_k_nsle
    cmpil   #MM_KEY_DATA,%d0
    bnes    mm_k_nrt
    movel   %d2,%sp@-
    jsr     0x40072434            | the click
    addql   #4,%sp
    tstb    %d0
    beqw    mm_k_used
    jsr     sle_dpress
    movel   %a2,%sp@-
    jsr     0x40076082            | redraw
    addql   #4,%sp
    braw    mm_k_used
mm_k_nsle:
    moveq   #MM_RTG,%d1
    cmpl    mm_kind,%d1
    bnes    mm_k_nrt
    cmpil   #KEY_RETRIG,%d0       | the retrig page: Retrig closes it too
    beqw    mm_k_press
    cmpil   #KEY_PATTERN,%d0      | ...and Pattern: a new pattern is coming.
    beqw    mm_k_pat              | Keys are not handed down the view stack
                                  | (samplerIK), so the page must go for the
                                  | screen below to pick the pattern. The close
                                  | only flags it (0x40076126 -> 0x40076bd8,
                                  | removed on a later update), so the press
                                  | still goes on to the stock: its popup and
                                  | tapped or held selection, as with no page
                                  | up. The master FX stay on (mfx_stream).
    cmpil   #MM_KEY_DATA,%d0      | and the DATA press edits the row, or stops
    bnes    mm_k_nrt
    movel   %d2,%sp@-
    jsr     0x40072434            | the click, as the stock list takes it
    addql   #4,%sp
    tstb    %d0
    beqw    mm_k_used
    moveq   #1,%d0
    eorl    %d0,rtg_edit
    movel   %a2,%sp@-
    jsr     0x40076082            | redraw
    addql   #4,%sp
    braw    mm_k_used
mm_k_nrt:
    cmpil   #MM_KEY_RETURN,%d0
    beqs    mm_k_ret
    cmpil   #KEY_PRESET,%d0
    beqs    mm_k_press
    cmpil   #KEY_TRACK,%d0
    beqs    mm_k_press
mm_k_stock:
    movel   %d2,%sp@-
    movel   %a2,%sp@-
    jsr     0x40075f3c            | the stock view's own key dispatch
    addql   #8,%sp
    bras    mm_k_out
mm_k_ret:
    movel   %d2,%sp@-
    jsr     0x40072434
    addql   #4,%sp
    tstb    %d0
    beqs    mm_k_used
    moveq   #MM_RTG,%d1           | the retrig page: Return resets, not closes
    cmpl    mm_kind,%d1
    bnes    mm_k_close
    jsr     mfx_reset
    movel   %a2,%sp@-
    jsr     0x40076082            | redraw
    addql   #4,%sp
    bras    mm_k_used
mm_k_pat:
    movel   %d2,%sp@-
    jsr     0x400724a0            | down and not a repeat
    addql   #4,%sp
    tstb    %d0
    beqw    mm_k_stock
    movea.l %a2@,%a0
    movel   %a2,%sp@-
    movea.l %a0@(0x28),%a0        | close (deferred)
    jsr     %a0@
    addql   #4,%sp
    braw    mm_k_stock
mm_k_press:
    movel   %d2,%sp@-
    jsr     0x400724a0            | down and not a repeat
    addql   #4,%sp
    tstb    %d0
    beqs    mm_k_stock            | a release or a repeat: not ours
mm_k_close:
    movea.l %a2@,%a0
    movel   %a2,%sp@-
    movea.l %a0@(0x28),%a0        | close, as the stock page does
    jsr     %a0@
    addql   #4,%sp
mm_k_used:
    moveq   #1,%d0
mm_k_out:
    moveml  %sp@,%d2/%a2
    lea.l   %sp@(8),%sp
    rts

| ---- any knob: one mode per click, applied at once ----
| (this, event). 0x4006f6ce says whether this is a value-knob event at all; if
| not the stock base gets it, as in the machine page's own handler 0x400a28b4.
mm_enc_th:
    subql   #4,%sp@(4)            | from the +4 base, as 0x400a2926 does
mm_enc:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    movea.l %sp@(20),%a2          | this
    movel   %sp@(24),%d2          | event
    moveq   #MM_SLE,%d0           | the slice editor: DATA and knobs 2-4
    cmpl    mm_kind,%d0
    beqw    mm_e_sle
    moveq   #MM_RTG,%d0
    cmpl    mm_kind,%d0
    bnew    mm_e_nrtg
    movea.l %d2,%a0               | the retrig page: DATA only, as a list -
    moveq   #1,%d1                | it moves between the rows, or, pressed
    cmpl    %a0@(12),%d1          | (mm_key), changes the row's value
    beqs    mm_e_rdat
    movel   %a0@(12),%d3          | any other knob: the master FX (mfx_knob)
    bsr     mfx_knob
    tstl    %d0
    beqw    mm_e_done
    braw    mm_e_redraw
mm_e_rdat:
    pea     0x1
    pea     0x1
    movel   %d2,%sp@-
    jsr     0x4006f73a            | clicks
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    mm_e_done
    smi     %d1
    extbl   %d1
    addql   #1,%d1                | right: 1, left: 0
    tstl    rtg_edit
    bnes    mm_e_rval
    movel   %d1,rtg_row           | two rows: down or up
    braw    mm_e_redraw
mm_e_rval:
    tstl    rtg_row
    bnes    mm_e_rfx
    movel   %d1,rtg_latch         | right: Latch, left: Momentary
    moveq   #-1,%d1
    movel   %d1,rtg_lstep
    braw    mm_e_redraw
mm_e_rfx:
    tstl    %d1                   | right: on, left: off
    beqs    mm_e_rfs
    tstl    rtg_fx
    bnes    mm_e_rfs
    moveq   #12,%d0               | coming on: the returns were not recorded
mm_e_rfz:
    bsr     rtg_zero
    addql   #1,%d0
    cmpil   #16,%d0
    bcss    mm_e_rfz
    moveq   #1,%d1
mm_e_rfs:
    movel   %d1,rtg_fx
    braw    mm_e_redraw
mm_e_sle:
    movea.l %d2,%a0
    movel   %a0@(12),%d3          | the knob
    moveq   #1,%d0                | DATA and zoom: a click a step
    cmpil   #2,%d3
    beqs    mes_acc
    cmpil   #3,%d3
    bnes    mes_c
mes_acc:
    moveq   #8,%d0                | the moves: faster turns go further
mes_c:
    movel   %d0,%sp@-
    pea     0x1
    movel   %d2,%sp@-
    jsr     0x4006f73a
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    mm_e_done
    movel   %d3,%d1
    jsr     sle_knob
    braw    mm_e_redraw
mm_e_sys:
    movel   sys_pg,%d1            | right: the next page, left: back
    tstl    %d0
    bmis    mm_e_sl
    cmpil   #1,%d1
    bges    mm_e_sd
    addql   #1,%d1
    bras    mm_e_sd
mm_e_sl:
    subql   #1,%d1
    bpls    mm_e_sd
    moveq   #0,%d1
mm_e_sd:
    movel   %d1,sys_pg
    braw    mm_e_redraw
mm_e_nrtg:
    movel   %d2,%sp@-
    jsr     0x4006f6ce
    addql   #4,%sp
    tstb    %d0
    bnes    mm_e_ours
    movel   %d2,%sp@-
    pea     %a2@(4)
    jsr     0x4006fb90
    addql   #8,%sp
    braw    mm_e_out
mm_e_ours:
    pea     0x1
    pea     0x1
    movel   %d2,%sp@-
    jsr     0x4006f73a            | clicks, no acceleration
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    mm_e_done
    lea.l   mm_track,%a0
    movel   %a0@,%d1
    lea.l   mm_kind,%a1
    movel   %a1@,%d3
    cmpil   #MM_SYS,%d3
    beqw    mm_e_sys              | the System page: turning pages
    cmpil   #2,%d3
    beqw    mm_e_os
    tstl    %d3
    bnes    mm_e_slice
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d1:l:4),%d3
    addl    %d0,%d3
    bges    mm_e_lo
    moveq   #0,%d3
mm_e_lo:
    cmpil   #MM_MODES-1,%d3
    bles    mm_e_hi
    moveq   #MM_MODES-1,%d3
mm_e_hi:
    cmpl    %a0@(0,%d1:l:4),%d3
    beqw    mm_e_done             | already at the end
    movel   %d1,%d0
    movel   %d3,%d1
    bsr     mode_set
    braw    mm_e_redraw
mm_e_slice:
    lea.l   sl_cfg,%a0
    movel   %a0@(0,%d1:l:4),%d3
    addl    %d0,%d3
    bges    mm_e_slo
    moveq   #0,%d3
mm_e_slo:
    cmpil   #5,%d3
    bles    mm_e_shi
    moveq   #5,%d3
mm_e_shi:
    cmpl    %a0@(0,%d1:l:4),%d3
    beqs    mm_e_done
    movel   %d3,%a0@(0,%d1:l:4)
    lea.l   sl_key,%a0            | slice_watch rebuilds the table
    clrl    %a0@(0,%d1:l:4)
    movel   %d1,%d0
    jsr     state_store
    lea.l   track_hash,%a0        | persist it with the name token
    movel   %d1,%d0
    movel   %a0@(0,%d0:l:4),%d1
    beqs    mm_e_redraw
    jsr     name_store
    bras    mm_e_redraw
mm_e_os:
    | an option list: mm_desc = {values, count, then two strings per option}
    lea.l   mm_desc,%a1
    movea.l %a1@,%a1
    movea.l %a1@,%a0              | this mode's option per track
    movel   %a1@(4),%d2           | how many (the event is no longer needed)
    movel   %a0@(0,%d1:l:4),%d3
    addl    %d0,%d3
    bges    mm_e_olo
    moveq   #0,%d3
mm_e_olo:
    cmpl    %d2,%d3
    bcss    mm_e_ohi
    movel   %d2,%d3
    subql   #1,%d3
mm_e_ohi:
    cmpl    %a0@(0,%d1:l:4),%d3
    beqw    mm_e_done
    movel   %d3,%a0@(0,%d1:l:4)
    movel   %d1,%d0
    jsr     state_store
    lea.l   track_hash,%a0        | persist it with the name token
    movel   %d1,%d0
    movel   %a0@(0,%d0:l:4),%d1
    beqs    mm_e_redraw
    jsr     name_store
mm_e_redraw:
    movel   %a2,%sp@-
    jsr     0x40076082            | redraw
    addql   #4,%sp
mm_e_done:
    moveq   #1,%d0
mm_e_out:
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
    rts

| ---- d0 = track, d1 = mode: set it and persist it in the name token ----
mode_set:
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    movel   %d0,%d2
    movel   %d1,%d3
    lea.l   loop_mode,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    movel   %d2,%d0
    jsr     state_store
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d1
    beqs    ms_out                | no sample on this track yet
    movel   %d2,%d0
    jsr     name_store
ms_out:
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    rts

| ---- draw: the machine page's own layout ----
| (this, ctx). As 0x400a24ca: the left 64x64 is lit, a rounded box cleared in
| it, the text drawn, and the whole square inverted at the end - a lit rounded
| panel with dark text. Seven markers at x = 0x50 + 7i, y 8..12, the current
| one filled, exactly where the machine page draws its six. Names in the 5x9
| font (0x40ea14cc): the widest, "Granular", is 8 characters.
MM_FONT  = 0x40ea14cc
MM_MODES = 7
mm_render:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d6/%a2,%sp@
    movel   %sp@(32),%d2          | ctx
    moveq   #MM_SYS,%d0
    cmpl    mm_kind,%d0
    bnes    mm_r_nsys
    bsr     sys_render            | the System page: the whole screen
    braw    mm_r_end
mm_r_nsys:
    moveq   #MM_RTG,%d0
    cmpl    mm_kind,%d0
    bnes    mm_r_nrtg
    jsr     rtg_render            | the retrig page: the whole screen
    braw    mm_r_end
mm_r_nrtg:
    moveq   #MM_SLE,%d0
    cmpl    mm_kind,%d0
    bnes    mm_r_std
    jsr     sle_render            | the slice editor: the whole screen
    braw    mm_r_end
mm_r_std:
    pea     0x1
    pea     0x3f
    pea     0x3f
    clrl    %sp@-
    clrl    %sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    clrl    %sp@-
    pea     0x3f
    pea     0x3f
    clrl    %sp@-
    clrl    %sp@-
    movel   %d2,%sp@-
    jsr     0x40070f6e
    lea.l   %sp@(24),%sp
    lea.l   mm_track,%a0
    movel   %a0@,%d1
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d1:l:4),%d3   | current mode
    cmpil   #MM_MODES,%d3
    bcss    mm_r_ok
    moveq   #0,%d3
mm_r_ok:
    lea.l   mm_kind,%a0
    movel   %a0@,%d0
    cmpil   #2,%d0
    beqw    mm_r_os
    tstl    %d0
    bnew    mm_r_slice
    pea     mm_caption
    pea     0x40124b58            | "%s"
    pea     0x2
    pea     0x12
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    lea.l   mm_names,%a0
    movel   %a0@(0,%d3:l:4),%sp@-
    pea     0x40124b58
    pea     0x2
    pea     0x22
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    moveq   #MM_MODES,%d6
    braw    mm_r_marks
mm_r_slice:
    | "16 slices" over "Equal" / "Transient"
    lea.l   mm_track,%a0
    movel   %a0@,%d1
    lea.l   sl_cfg,%a0
    movel   %a0@(0,%d1:l:4),%d3
    cmpil   #5,%d3
    blss    mm_r_sok
    moveq   #1,%d3
mm_r_sok:
    movel   %d3,%d1               | count = 8 << (option % 3); options
    cmpil   #3,%d1                | 3..5 are 0..2 with transients on
    bcss    mm_r_smod
    subql   #3,%d1
mm_r_smod:
    moveq   #8,%d0
    lsll    %d1,%d0
    movel   %d0,%sp@-
    pea     mm_fmt_slices
    pea     0x2
    pea     0x12
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    pea     msg_equal
    cmpil   #3,%d3
    bcss    mm_r_seq
    addql   #4,%sp
    pea     msg_trans
mm_r_seq:
    pea     0x40124b58
    pea     0x2
    pea     0x22
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    moveq   #6,%d6
    braw    mm_r_marks
mm_r_os:
    | an option list: two lines per option, from mm_desc
    lea.l   mm_desc,%a2
    movea.l %a2@,%a2
    lea.l   mm_track,%a0
    movel   %a0@,%d1
    movea.l %a2@,%a0
    movel   %a0@(0,%d1:l:4),%d3
    movel   %a2@(4),%d6           | how many
    cmpl    %d6,%d3
    bcss    mm_r_ook
    moveq   #0,%d3
mm_r_ook:
    movel   %d3,%d0
    lsll    #3,%d0
    movel   %a2@(8,%d0:l),%sp@-
    pea     0x40124b58
    pea     0x2
    pea     0x12
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    movel   %d3,%d0
    lsll    #3,%d0
    movel   %a2@(12,%d0:l),%sp@-
    pea     0x40124b58
    pea     0x2
    pea     0x22
    pea     0x20
    pea     MM_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
mm_r_marks:
    moveq   #0,%d4                | marker index
    movel   %d6,%d0               | right edges from 122 - 7*(n-1), so any
    subql   #1,%d0                | count up to 8 ends at the same place
    movel   %d0,%d5
    lsll    #3,%d5
    subl    %d0,%d5
    negl    %d5
    addil   #122,%d5
mm_r_mk:
    pea     0x1
    pea     0xc
    movel   %d5,%sp@-
    pea     0x8
    movel   %d5,%d0
    subql   #4,%d0
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    cmpl    %d3,%d4
    bnes    mm_r_out
    jsr     0x40070efc            | the current one, filled
    bras    mm_r_mn
mm_r_out:
    jsr     0x40070c4e            | the others, outlined
mm_r_mn:
    lea.l   %sp@(24),%sp
    addql   #7,%d5
    addql   #1,%d4
    cmpl    %d6,%d4
    bcss    mm_r_mk
    pea     -1                    | invert the panel
    pea     0x3f
    pea     0x3f
    clrl    %sp@-
    clrl    %sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
mm_r_end:
    moveml  %sp@,%d2-%d6/%a2
    lea.l   %sp@(24),%sp
    rts

    .align 4
mm_obj:        .long 0          | the menu page while it is up
mm_track:      .long 0          | the track it edits
mm_names:      .long msg_oneshot, msg_loop, msg_slice, msg_gran, msg_strch, msg_pluck, msg_wave
mm_kind:       .long 0          | 0 = mode menu, 1 = slice menu, 3 = System
mm_kind_req:   .long 0
mm_opened:     .long 0          | the last open request brought a menu up
mm_desc:       .long 0          | the option list on screen (kind 2)
| Each mode's option list: {per-track values, how many, then line 1 and
| line 2 of every option}. Indexed by mode; 0 = the mode has none here
| (Slice has its own menu, Granular will get one of its own).
opt_menus:     .long om_os, om_lp, 0, 0, om_st, om_pk, 0
om_os:         .long os_opt, 7
               .long msg_oneshot, msg_normal, msg_oneshot, msg_lofi
               .long msg_oneshot, s_tape, msg_oneshot, s_vinyl
               .long s_stutter, s_18, s_stutter, s_116, s_stutter, s_132
om_lp:         .long lp_opt, 6
               .long msg_loop, s_fwd, msg_loop, s_pingpong, msg_loop, s_xfade
               .long s_sync, s_1bar, s_sync, s_2bars, s_sync, s_4bars
om_st:         .long st_opt, 7
               .long msg_strch, s_fwd, msg_strch, s_rev, s_once, s_fwd
               .long s_once, s_rev, s_sync, s_1bar, s_sync, s_2bars
               .long s_sync, s_4bars
om_pk:         .long pk_opt, 4
               .long s_exciter, s_sample, s_exciter, s_noise
               .long s_exciter, s_click, msg_pluck, s_drum
s_tape:        .asciz "Tape"
s_vinyl:       .asciz "Vinyl"
s_stutter:     .asciz "Stutter"
s_18:          .asciz "1/8"
s_116:         .asciz "1/16"
s_132:         .asciz "1/32"
s_fwd:         .asciz "Forward"
s_rev:         .asciz "Reverse"
s_pingpong:    .asciz "Ping-pong"
s_xfade:       .asciz "Crossfade"
s_once:        .asciz "Once"
s_sync:        .asciz "Sync"
s_1bar:        .asciz "1 bar"
s_2bars:       .asciz "2 bars"
s_4bars:       .asciz "4 bars"
s_exciter:     .asciz "Exciter"
s_sample:      .asciz "Sample"
s_noise:       .asciz "Noise"
s_click:       .asciz "Click"
s_drum:        .asciz "Drum"
    .align 4
mm_caption:    .asciz "Mode"
mm_fmt_slices: .asciz "%d slices"
msg_normal:    .asciz "Normal"
msg_equal:     .asciz "Equal"
msg_trans:     .asciz "Transient"
msg_fxoff:     .asciz "Master FX\noff"
    .align 4
mm_vt   = UI_BUF+0x718          | the page's vtable group (MM_VT_LEN), rebuilt
                                | from stock on every open - in the region
                                | since samplerHY, after sl_tbl

| ---- put a text popup on screen -----------------------------------------
| Transcribed from 0x4000d750 ("Lock mem full!"), which is the one popup site
| that needs no caller context: it reaches the view stack itself through
| 0x400d0974 -> 0x400060d8. Only the text differs.
|   0x400f980c  String(this, cstr, tag)   - a 4-byte String at fp-12
|   0x400747c0  Popup(mem, String)
|   0x400fbf40  the reference-holder's vtable
|   0x4007700e  present(target, &{popup,holder}, 0)
|   0x400cf23c  release the holder      0x400f7d5c  destroy the String
| The layout is kept identical to the original: String at fp-12 (4 bytes),
| the {popup, holder} pair at fp-8/fp-4.
show_popup:
    linkw   %fp,#-28
    moveml  %d2-%d3/%a2,%sp@
    movel   0x40fe4178,%d0
    beqw    sp_out                | popup machinery not up yet
    lea.l   0x400802e0,%a2        | operator new
    movel   %fp,%d2
    addil   #-12,%d2
    pea     %fp@(-13)
    movel   %fp@(8),%sp@-         | our text
    movel   %d2,%sp@-
    jsr     0x400f980c
    lea.l   %sp@(12),%sp
    pea     0x9c
    jsr     %a2@
    addql   #4,%sp
    movel   %d0,%d3
    movel   %d2,%sp@-
    movel   %d3,%sp@-
    jsr     0x400747c0
    addql   #8,%sp
    movel   popup_mult,%d0        | a longer stay: the fields Popup's init sets
    beqs    sp_std                | from its multiplier (0x40074676): +0x6c = N,
    movea.l %d3,%a0               | +0x60 (the ticks left, 0x400749b4 counts it
    movel   %d0,%a0@(0x6c)        | down and closes at 0) and +0x64 = 60 * N
    movel   %d0,%d1
    lsll    #6,%d0
    lsll    #2,%d1
    subl    %d1,%d0
    movel   %d0,%a0@(0x60)
    movel   %d0,%a0@(0x64)
sp_std:
    movel   %d3,%fp@(-8)
    clrl    %fp@(-4)
    pea     0x10
    jsr     %a2@
    addql   #4,%sp
    movea.l %d0,%a0
    moveq   #1,%d0
    movel   %d0,%a0@(4)
    movel   #0x400fbf40,%a0@
    movel   %d0,%a0@(8)
    movel   %d3,%a0@(12)
    movel   %a0,%fp@(-4)
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8
    addql   #4,%sp
    clrl    %sp@-
    pea     %fp@(-8)
    movel   %d0,%sp@-
    jsr     0x4007700e
    lea.l   %sp@(12),%sp
    pea     %fp@(-4)
    jsr     0x400cf23c
    addql   #4,%sp
    movel   %d2,%sp@-
    jsr     0x400f7d5c
    addql   #4,%sp
sp_out:
    moveml  %fp@(-28),%d2-%d3/%a2
    unlk    %fp
    rts

    .balign 4
popup_mult:    .long 0   | show_popup: 0 = the stock stay, else N times it
track_held:    .long 0
kh_eaten:      .long 0   | a Preset press swallowed by the chord
kh_eaten3:     .long 0   | a resample test press swallowed by the chord
kh_eaten4:     .long 0   | a Retrig press swallowed by the chord
kh_eaten5:     .long 0   | a Return press swallowed by Track + Return
kh_eaten2:     .long 0   | an options-menu press swallowed by the chord
loop_mode:     .long 0,0,0,0,0,0,0   | per track, 1 = loop; one-shot is default
msg_loop:      .asciz "Loop"
msg_slice:     .asciz "Slice"
msg_gran:      .asciz "Granular"
msg_strch:     .asciz "Stretch"
msg_pluck:     .asciz "Pluck"
msg_wave:      .asciz "Wave"
msg_lofi:      .asciz "Lo-fi"
    .align 2
mod_held:      .long 0   | the attack modifier is down: Decay is Attack
str_attack:    .asciz "Attack"
    .align 2
str_atk:       .asciz "ATK"
str_gfilter:   .asciz "Filter"
str_gflt:      .asciz "FLT"
str_greso:     .asciz "Resonance"
str_gres:      .asciz "RES"
msg_oneshot:   .asciz "One shot"
    .align 2
| ================= end of the loop / one-shot gesture =====================

| ---- install or restore our four parameter labels -------------------------
| param_table's name/category/short pointers are GLOBAL to a param id, so our
| four ids cannot simply be renamed: 0x2e is also Kick Color, 0x3e is Perc
| Shape, and so on. They are therefore swapped in and out as the selection
| moves, which is why every caller below decides first whether the thing being
| drawn belongs to the Sampler.
| d1 = 1 installs our labels (+4 in each name_swap row), 0 restores the stock
| ones (+16). Clobbers d0/d1/a0/a1.
apply_names:
    lea.l   name_swap,%a1
    tstl    %d1
    beqs    an_loop
    lea.l   ui_gran,%a1           | our labels: the selected track's mode picks
    movel   %a1@,%d0              | the set - 1 granular, 2 stretch
    lea.l   name_swap,%a1
    tstl    %d0
    beqs    an_loop
    lea.l   gran_swap,%a1
    cmpil   #1,%d0
    beqs    an_loop
    lea.l   strch_swap,%a1
    cmpil   #2,%d0
    beqs    an_loop
    lea.l   pluck_swap,%a1
    cmpil   #3,%d0
    beqs    an_loop
    lea.l   wave_swap,%a1
    cmpil   #4,%d0
    beqs    an_loop
    lea.l   lofi_swap,%a1
    cmpil   #5,%d0
    beqs    an_loop
    lea.l   tv_swap,%a1
an_loop:
    movel   %a1@,%d0              | entry byte offset, -1 terminates
    bmis    an_done
    lea.l   param_table,%a0
    addl    %d0,%a0
    tstl    %d1
    beqs    an_stock
    movel   %a1@(4),%d0
    movel   %d0,%a0@(44)
    movel   %a1@(8),%d0
    movel   %d0,%a0@(48)
    movel   %a1@(12),%d0
    movel   %d0,%a0@(52)
    bras    an_next
an_stock:
    movel   %a1@(16),%d0
    movel   %d0,%a0@(44)
    movel   %a1@(20),%d0
    movel   %d0,%a0@(48)
    movel   %a1@(24),%d0
    movel   %d0,%a0@(52)
an_next:
    lea.l   %a1@(28),%a1
    bras    an_loop
an_done:
    | Start and End show two decimals while our labels are up, so the fine steps
    | fine_hook makes are visible. The display calls the invoker at record+0x20
    | of the parameter's 100-byte UI record (0x40a71754 + id*100) as
    | (record+0x14, value, buf): 0x400456c8 prints value>>8, 0x4004a440 prints
    | value/256 as "%d.%02d". Both records are filled at boot from the same
    | stock formatter (0x40a70708), which is what is put back for Kick Color
    | and Perc Shape.
    movel   #0x400456c8,%d0
    tstl    %d1
    beqs    an_fmt
    movel   #0x4004a440,%d0
an_fmt:
    movel   %d0,0x40a7296c        | id 0x2e: Start
    movel   %d0,0x40a72fac        | id 0x3e: End
    | ...and the page's own renderer, which is what draws Pitch's decimals in
    | the small font. Before drawing a value as a plain string the page calls
    | track-handle slot 0x40 (0x4000a66a): if the record's function object at
    | +0x24 is set (manager at +0x2c non-zero) its invoker at +0x30 draws the
    | value instead. Pitch's is 0x4004dcca; ours are empty. Install fine_draw
    | using Pitch's storage and manager words - the manager only runs if the
    | object is copied or destroyed, and these records never are - and clear
    | the manager again to hand Kick Color / Perc Shape back their plain draw.
    tstl    %d1
    beqs    an_rclr
    movel   #fine_draw,%d0
    movel   %d0,0x40a7297c        | invokers first: the manager is the flag
    movel   %d0,0x40a72fbc
    movel   0x40a727e0,%d0        | Pitch's record + 0x24 / 0x28
    movel   %d0,0x40a72970
    movel   %d0,0x40a72fb0
    movel   0x40a727e4,%d0
    movel   %d0,0x40a72974
    movel   %d0,0x40a72fb4
    movel   0x40a727e8,%d0        | Pitch's manager, last
    movel   %d0,0x40a72978
    movel   %d0,0x40a72fb8
    rts
an_rclr:
    clrl    0x40a72978
    clrl    0x40a72fb8
    rts

| ---- draw Start/End like Pitch: big whole digits, a small decimal --------
| Invoked as (functor, value, ctx, 0x60, y, flag) - the arguments 0x4000a66a
| passes on from the page. Transcribed from Pitch's renderer 0x4004dcca, which
| fixes the layout: digit width w = 0x40072272(bigFont, 0); digits at x = 71,
| 72+w and 73+2w; the decimal at 72 + width("999"), in the small font; every
| glyph drawn by 0x40071c10(ctx, font, x, y, 0, 0, template, format, arg).
| Pitch's leftmost slot carries its sign; ours carries the hundreds digit.
| Value is 0..32512: whole part value>>8, tenths ((value&255)*10)>>8, which
| moves on every eighth-step fine_hook makes.
FD_BIG   = 0x40ea14dc
FD_SMALL = 0x40ea14cc
fine_draw:
    linkw   %fp,#-56
    moveml  %d2-%d7/%a2-%a5,%sp@
    movel   %fp@(16),%d2          | ctx
    movel   %fp@(24),%d3          | y
    lea.l   0x400720f8,%a3        | font -> handle
    lea.l   0x40071c10,%a2        | draw
    clrl    %sp@-
    pea     FD_BIG
    jsr     0x40072272
    addql   #8,%sp
    movel   %d0,%d5               | w
    movel   %fp,%d4
    subql   #4,%d4                | a 4-byte String at fp-4, tag byte at fp-5
    pea     %fp@(-5)
    pea     0x4012771e            | "999"
    movel   %d4,%sp@-
    jsr     0x400f980c
    pea     FD_BIG
    jsr     %a3@
    movel   %d4,%sp@-
    pea     0x3
    movel   %d0,%sp@-
    jsr     0x40072102            | width of "999"
    lea.l   %sp@(28),%sp
    movel   %d0,%d6
    addil   #72,%d6               | x of the decimal
    movel   %d4,%sp@-
    jsr     0x400f7d5c
    addql   #4,%sp
    movel   %fp@(12),%d7          | value
    bges    fd_pos
    moveq   #0,%d7
fd_pos:
    movel   %d7,%d0
    andil   #0xff,%d0
    movel   %d0,%d1
    lsll    #2,%d1
    addl    %d0,%d1
    addl    %d1,%d1               | * 10
    lsrl    #8,%d1
    movea.l %d1,%a5               | tenths
    lsrl    #8,%d7                | whole part, 0..127
    moveq   #100,%d1
    movel   %d7,%d0
    divul   %d1,%d0               | hundreds
    beqs    fd_tens
    movel   %d0,%d4
    pea     FD_BIG
    jsr     %a3@
    addql   #4,%sp
    movel   %d4,%sp@-
    pea     0x4012a9ea            | "%d"
    pea     0x4012772e            | "X"
    clrl    %sp@-
    clrl    %sp@-
    movel   %d3,%sp@-
    pea     71
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     %a2@
    lea.l   %sp@(36),%sp
fd_tens:
    cmpil   #10,%d7
    bcss    fd_ones
    moveq   #10,%d1
    movel   %d7,%d0
    divul   %d1,%d0               | whole / 10
    movel   %d0,%d4
    divul   %d1,%d4
    mulul   %d1,%d4
    subl    %d4,%d0               | % 10: the tens digit
    movel   %d0,%d4
    pea     FD_BIG
    jsr     %a3@
    addql   #4,%sp
    movel   %d4,%sp@-
    pea     0x4012a9ea
    pea     0x4012772e
    clrl    %sp@-
    clrl    %sp@-
    movel   %d3,%sp@-
    movel   %d5,%d1
    addil   #72,%d1
    movel   %d1,%sp@-
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     %a2@
    lea.l   %sp@(36),%sp
fd_ones:
    moveq   #10,%d1
    movel   %d7,%d0
    divul   %d1,%d0
    mulul   %d1,%d0
    movel   %d7,%d4
    subl    %d0,%d4               | whole % 10
    pea     FD_BIG
    jsr     %a3@
    addql   #4,%sp
    movel   %d4,%sp@-
    pea     0x4012a9ea
    pea     0x4012772e
    clrl    %sp@-
    clrl    %sp@-
    movel   %d3,%sp@-
    movel   %d5,%d1
    addl    %d1,%d1
    addil   #73,%d1
    movel   %d1,%sp@-
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     %a2@
    lea.l   %sp@(36),%sp
    pea     FD_SMALL              | the decimal, small
    jsr     %a3@
    addql   #4,%sp
    movel   %a5,%sp@-
    pea     0x4012b9e9            | ".%d"
    pea     0x4012772d            | ".X"
    clrl    %sp@-
    clrl    %sp@-
    movel   %d3,%sp@-
    movel   %d6,%sp@-
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     %a2@
    lea.l   %sp@(36),%sp
    moveml  %fp@(-56),%d2-%d7/%a2-%a5
    unlk    %fp
    rts

| ---- finer Start/End: speed-sensitive knob steps -------------------------
| Replaces slot 0x14 of the track-handle vtable (0x400fd134), 0x4000c264: the
| "new value = current + delta" step every knob turn goes through (via
| 0x4000b7d6), and the one place the stock firmware already special-cases a
| parameter - Pitch gets tenths of a semitone there. The knob hands it deltas
| in whole steps of 256; on a Sampler track, Start (0x2e) and End (0x3e)
| rescale a small delta to delta*|delta|/2048: one step per turn event becomes
| 32 (an eighth), two become 128, four 512, and from eight up (2048) it is
| left alone - so a slow turn is fine and a fast one still sweeps.
|   args: sp@(4) this, sp@(8) id, sp@(12) current, sp@(16) delta
fine_hook:
    movel   %sp@(8),%d0
    cmpil   #0x2e,%d0
    beqs    fh_ours
    cmpil   #0x3e,%d0
    beqs    fh_ours
fh_go:
    jmp     0x4000c264
fh_ours:
    movea.l %sp@(4),%a0           | the track handle; +4 is its track object,
    movel   %a0@(4),%d0           | as the stock setter 0x4000ba7a reads it
    beqs    fh_go
    movea.l %d0,%a0
    movea.l %a0@,%a1
    movea.l %a1@(40),%a1          | vtable[40]: the sound
    movel   %d0,%sp@-
    jsr     %a1@
    addql   #4,%sp
    tstl    %d0
    beqs    fh_go
    movea.l %d0,%a0
    mvzb    %a0@(38),%d0
    cmpil   #6,%d0
    bnes    fh_go                 | Kick Color / Perc Shape: untouched
    movel   %sp@(16),%d0
    movel   %d0,%d1
    bpls    fh_abs
    negl    %d1
fh_abs:
    cmpil   #2048,%d1
    bges    fh_go
    mulsl   %d1,%d0
    asrl    #8,%d0
    asrl    #3,%d0                | delta * |delta| / 2048, sign kept
    movel   %d0,%sp@(16)
    bras    fh_go

descr_b_hook:
    movel   %sp@(4),%d0
    | Keep the global labels in step with the track being drawn. descr_hook only
    | runs when the parameter page is REBUILT, so a project that loads with a
    | Sampler track already selected kept the stock labels until the machine was
    | changed and changed back - the LFO destination list showed "Kick Color"
    | and friends. This lookup is reached from the pad menu's LED painter, which
    | repaints every frame while that list is on screen (proven: it is what
    | lights the destination LED), so the labels now follow the selection with
    | no rebuild.
    moveq   #0,%d1
    cmpil   #6,%d0
    bnes    dbh_names
    moveq   #1,%d1
dbh_names:
    movel   %d0,%sp@-             | apply_names clobbers d0
    bsr     apply_names
    movel   %sp@+,%d0             | sp restored: dbh_pass re-reads the argument
    cmpil   #6,%d0
    bnes    dbh_pass
    | sampler_descr is built on the AUDIO thread by sampler_pre; until that has
    | run it is 76 zero bytes, and a search would match id 0 at position 0 and
    | light a dial at random. %a1 is caller-saved, so borrowing it is free, and
    | tstb's result survives into the branch.
    lea.l   descr_done,%a1
    tstb    %a1@
    beqs    dbh_pass
    lea.l   mod_held,%a1
    tstl    %a1@
    bnes    dbh_atk
    movel   #sampler_descr,%d0
    rts
dbh_atk:
    movel   #sampler_descr_atk,%d0
    rts
dbh_pass:
    jmp     table_lookup_b_fixed            | table_lookup_b_fixed, Kick alias untouched

| ============================================================================
| ==============  eMMC SAMPLE LOADER + PRESET-BROWSER LOADING  ===============
|
| Filesystem (all verified on hardware):
|   readBlocks  0x4008b24a(block, bytes, dest) -> 0 ok
|   inode table blocks 1,835,088 .. 1,851,472, 128-byte records
|               +0 flags (0x00020001 = file) +4 size +12 hash +36 chunks +40 chunk0
|   data        block = 1,851,472 + chunk*32, 16 KiB chunks
|   file        64-byte header (+4 datalen, +8 rate) then BE 16-bit mono 48 kHz
|
| The preset browser already lists the sample files. Selecting one runs
|     400a659e  jsr 0x4007cdd4      getEntry(&handle, dir, index)   <- SUCCEEDS
|     400a6732  jsr 0x400a51fa      parse it as a preset            <- FAILS
|     400a674e  beqs ok   else -> "Error loading\npreset" (0x401302b2)
| The probe confirmed the handle comes back VALID, carrying the file's
| {entry id, hash, size} - everything the loader needs. So:
|   * getentry_hook remembers the hash and size of whatever was selected
|   * preset_fail_hook wraps the parse; when it fails we load the sample
|     ourselves and swap the popup text
|   * the pea at 0x400a6752 now points at msg_buf instead of the fixed string
| The parse is still allowed to fail, so the firmware never tries to apply a
| sample to a track as if it were a preset.
| ============================================================================

    TABLE_BLOCK = 1835088
    TABLE_END   = 1851472
    DATA_BASE   = 1851472
    WANT_HASH   = 0x6809683d       | default: "Cymatics - Frozen Keys One Shot - C"
    MAX_FILE    = 0x1800000        | 24 MiB - a sanity bound, not a buffer size

| ---- the dedicated 64 MiB sample region ----
| 0x4a800000..0x4e800000 is the pool Model:Samples uses for its 64 MB of sample
| memory. Cycles registers a 4 MiB region at 0x4a400000 and nothing above it;
| Samples registers that same region 64 MiB higher, at 0x4e400000, with its pool
| in between. Verified on hardware: 1,024 signatures every 64 KiB survived
| repeated sample loads, playback and browsing untouched.
|
| Using it directly replaces the whole segmented loader - no operator new, no
| segment table, no per-sample allocation, and the render indexes one flat
| array. It also lifts the ceiling from the 16.2 MiB buddy heap (shared with the
| entire firmware) to 64 MiB that nothing else claims.
    REGION_BASE = 0x4a800000
    REGION_END  = 0x4e800000
    TBL_BUF     = 0x4a800000      | 64 KiB inode-table page
    PCM_BASE    = 0x4a810000      | the sample file image
    MAX_TRK     = 6
    MAX_SLOT    = 64
    PEND_NOFADE = 0x10000         | track_pend: a pattern's own sample, no fade
    PEND_SILENT = 0x1ffff         | track_pend: silence at the next note
    PL_NFAIL    = 16              | the preloader's missing-file memory
    PCM_MAX     = 0x03fe0000      | what is left of the region, 16-byte aligned
    PCM_DATA    = PCM_BASE + 64   | past the 64-byte file header
    DLY2_BASE   = REGION_END - 0x1C000 | Pluck in stereo: the side's six strings
    NAME_BASE   = DLY2_BASE - 0x800 | each slot's file name, 32 bytes a slot
    PATH_BUF    = NAME_BASE - 0x100 | scratch for the file system's full path
    RTG_BASE    = PATH_BUF - 16*131072*2 | retrig histories (rtg_*), 4 MiB
    UI_BUF      = RTG_BASE - 0x800 | the waveform popup's columns (wf_mn..)
                                  | and, at +0x400, the slice tables (sl_tbl)
    MK_BASE     = UI_BUF - 0x2300 | manual slices: 64 x {hash, n, 32 starts,
                                  | changed}
    PCM_TOP     = MK_BASE         | samples and takes stay below this
    PCM_CACHED  = 0x4C000000      | from here up the data cache holds it (ACR1,
                                  | set in boot_extra_hook): files go here
                                  | first. Below, the 16 MiB block shared with
                                  | the audio output and the eMMC bounce
                                  | buffer (0x4a3ed080 / 0x4a3ed480) cannot be
                                  | cached, so the rest stays uncached
    DLY_BASE    = REGION_END - 0x10000 | Pluck: six 8 KiB delay lines, which the
                                  | loader must never reach - it bounds against
                                  | this, not REGION_END

| ---- resident-sample slots -------------------------------------------
| ensure_loaded(d0 = hash) -> d0 = slot index, or -1.
| A hash already resident returns its slot - two tracks, or two patterns, on
| the same file share one copy. Otherwise the file goes into the lowest gap of
| the region that holds it (find_gap); when there is none, or no free slot,
| samples are evicted (evict_one) until there is: first what nothing in the
| project uses, then files only other patterns use (they reload from disk),
| and last recordings only other patterns use. Never anything a track plays
| or is about to play, nor anything the current pattern names - the pattern
| on screen always plays. pd_mode 1 (the preloader) evicts only the unused.
| el_frag is set when evicting everything allowed still left no gap - the
| caller then compacts (rebuild_slots) and retries.
ensure_loaded:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    clrl    el_frag
    movel   %d0,%d2
    beqw    el_none
    moveq   #0,%d3
el_find:
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d3:l:4),%d0
    cmpl    %d2,%d0
    beqw    el_hit
    addql   #1,%d3
    cmpil   #MAX_SLOT,%d3
    bcss    el_find
    movel   %d2,%d0               | a recording, or a cleared track: never on
    andil   #0xffffff00,%d0       | disk, so do not go looking for it
    cmpil   #RS_HASH,%d0
    beqw    el_none
    tstl    rs_state              | never load over a recording in progress
    bnew    el_none
    tstl    rs_pending
    bnew    el_none
    tstl    rs_sv_state           | nor while a save reads the take
    bnew    el_none
    moveq   #-1,%d0
    movel   %d0,el_slot
el_idx:
    bsr     free_slot
    movel   %d0,%d3
    bpls    el_load
    bsr     evict_one             | no free slot: make one
    tstl    %d0
    bnew    el_idx
    moveq   #5,%d0                | no room
    movel   %d0,fail_why
    braw    el_none
el_load:
    lea.l   want_hash,%a0
    movel   %d2,%a0@
    lea.l   el_slot,%a0           | pick_dest must not hand this one out
    movel   %d3,%a0@
    jsr     load_at               | calls pick_dest once it knows the size
    tstl    %d0
    beqw    el_none
    movel   want_dest,%d4
    lea.l   slot_hash,%a0
    movel   %d2,%a0@(0,%d3:l:4)
    lea.l   slot_base,%a0
    movel   %d4,%a0@(0,%d3:l:4)
    lea.l   out_count,%a0
    movel   %a0@,%d0
    lea.l   slot_count,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    movel   out_bytes,%d0
    addil   #15,%d0
    andil   #0xfffffff0,%d0
    lea.l   slot_size,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_tpat,%a0
    moveq   #-1,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_nino,%a0         | its name comes later, from nm_step
    movel   want_ino,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_nisz,%a0
    movel   want_isz,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_nfsz,%a0
    clrl    %a0@(0,%d3:l:4)
    lea.l   slot_npth,%a0
    moveq   #-2,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    movel   %d3,%d0
    bsr     nm_clear
    lea.l   slot_soff,%a0
    clrl    %a0@(0,%d3:l:4)
    lea.l   slot_pgain,%a0        | a saved take carries its playback gain
    clrl    %a0@(0,%d3:l:4)       | in its header: "RSG1" at +0x18, gain at
    movea.l %d4,%a1               | +0x1c (Q12); anything else plays as is
    movel   %a1@(0x18),%d0
    cmpil   #RS_GMAGIC,%d0
    bnes    el_ng
    movel   %a1@(0x1c),%d0
    movel   %d0,%a0@(0,%d3:l:4)
    | Stereo (bit 0 of +0x20): the data is the mid plane then the side, each
    | datalen/2. Only when all of it was read - a trimmed one plays its mid.
    movel   %a1@(0x20),%d0
    btst    #0,%d0
    beqs    el_ng
    movel   %a1@(4),%d0           | data bytes
    movel   out_count,%d1         | samples held: all of them?
    addl    %d1,%d1
    cmpl    %d0,%d1
    bcss    el_half
    lsrl    #1,%d0                | one plane: the side's offset
    lea.l   slot_soff,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    lsrl    #1,%d0                | frames
    lea.l   slot_count,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    bras    el_ng
el_half:
    lsrl    #2,%d0                | trimmed: at most the mid plane, as mono
    lea.l   slot_count,%a0
    cmpl    %a0@(0,%d3:l:4),%d0
    bccs    el_ng
    movel   %d0,%a0@(0,%d3:l:4)
el_ng:
    bsr     top_calc              | alloc_top: the end of the highest slot
    movea.l %d4,%a1               | Transfer's stereo: byte +1 of the header
    moveq   #0,%d0
    moveb   %a1@(1),%d0
    moveq   #1,%d1
    cmpl    %d1,%d0
    bnes    el_nst
    bsr     el_deint
el_nst:
    movel   %d3,%d0               | a stereo file with a silent side is mono
    bsr     sx_quiet_slot
el_hit:
    movel   %d3,%d0
    bras    el_exit
el_none:
    moveq   #-1,%d0
el_exit:
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    rts

| free_slot -> d0 = an empty slot index, or -1. Clobbers a0.
free_slot:
    moveq   #0,%d0
fs_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d0:l:4)
    beqs    fs_out
    addql   #1,%d0
    cmpil   #MAX_SLOT,%d0
    bcss    fs_l
    moveq   #-1,%d0
fs_out:
    rts

| top_calc: alloc_top <- the end of the highest occupied slot (PCM_BASE when
| none) - where a recording starts. Keeps d1-d7.
top_calc:
    lea.l   %sp@(-12),%sp
    moveml  %d1-%d3,%sp@
    movel   #PCM_BASE,%d1
    moveq   #0,%d2
tc_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    tc_n
    lea.l   slot_base,%a0
    movel   %a0@(0,%d2:l:4),%d0
    lea.l   slot_size,%a0
    addl    %a0@(0,%d2:l:4),%d0
    cmpl    %d1,%d0
    blss    tc_n
    movel   %d0,%d1
tc_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    tc_l
    movel   %d1,alloc_top
    moveml  %sp@,%d1-%d3
    lea.l   %sp@(12),%sp
    rts

| find_gap(d0 = bytes) -> d0 = the lowest 16-aligned address where that many
| bytes overlap no slot and stay under PCM_TOP, or 0; el_lim <- where that gap
| ends. The cached part of the region (PCM_CACHED up) is searched first, and
| only then all of it. Keeps d1-d7.
find_gap:
    lea.l   %sp@(-24),%sp
    moveml  %d1-%d6,%sp@
    movel   %d0,%d5               | bytes
    movel   #PCM_CACHED,%d6       | the first pass's floor
fg_pass:
    movel   %d6,%d1               | candidate
fg_again:
    moveq   #0,%d2
fg_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    fg_n
    lea.l   slot_base,%a0
    movel   %a0@(0,%d2:l:4),%d3   | its start
    lea.l   slot_size,%a0
    movel   %a0@(0,%d2:l:4),%d4
    addl    %d3,%d4               | its end
    cmpl    %d1,%d4               | ends at or below the candidate: clear
    blss    fg_n
    movel   %d1,%d0
    addl    %d5,%d0
    cmpl    %d3,%d0               | the candidate ends at or below its start
    blss    fg_n
    addil   #15,%d4               | overlap: try just past it
    andil   #0xfffffff0,%d4
    movel   %d4,%d1
    bras    fg_again
fg_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    fg_l
    movel   %d1,%d0
    addl    %d5,%d0
    cmpil   #PCM_TOP,%d0
    bhis    fg_none
    tstl    pd_mode               | the preloader leaves room for recording
    beqs    fg_top
    cmpil   #PCM_TOP-PL_RESERVE,%d0
    bhis    fg_none
fg_top:
    movel   #PCM_TOP,%d3          | the gap's end: the lowest start above it
    moveq   #0,%d2
fg_e:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    fg_en
    lea.l   slot_base,%a0
    movel   %a0@(0,%d2:l:4),%d4
    cmpl    %d1,%d4
    blss    fg_en
    cmpl    %d3,%d4
    bccs    fg_en
    movel   %d4,%d3
fg_en:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    fg_e
    movel   %d3,el_lim
    movel   %d1,%d0
    bras    fg_out
fg_none:
    cmpil   #PCM_BASE,%d6         | the cached part is full: all of it
    beqs    fg_nf
    movel   #PCM_BASE,%d6
    braw    fg_pass
fg_nf:
    moveq   #0,%d0
fg_out:
    moveml  %sp@,%d1-%d6
    lea.l   %sp@(24),%sp
    rts

| pick_dest(d0 = bytes) -> d0 = where load_at should put the file, or 0 (and
| el_frag set: evicting all that pd_mode allows left no gap). From load_at,
| once the file's size is known. Keeps d1-d7.
pick_dest:
    movel   %d2,%sp@-
    movel   %d0,%d2
pd_try:
    movel   %d2,%d0
    bsr     find_gap
    tstl    %d0
    bnes    pd_out
    bsr     evict_one
    tstl    %d0
    bnes    pd_try
    moveq   #1,%d0
    movel   %d0,el_frag
    moveq   #0,%d0
pd_out:
    movel   %sp@+,%d2
    rts

| evict_one -> d0 = 1 if a slot was emptied. The candidate with the lowest
| slot_level (the largest of those, to free the most), never level 3, and
| in pd_mode 1 only level 0. Keeps d1-d7.
evict_one:
    lea.l   %sp@(-24),%sp
    moveml  %d1-%d6,%sp@
    moveq   #-1,%d4               | best slot
    moveq   #3,%d5                | its level (3 = none yet)
    moveq   #0,%d6                | its size
    moveq   #0,%d2
eo_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    eo_n
    cmpl    el_slot,%d2           | the one being loaded into
    beqs    eo_n
    movel   %d2,%d0
    bsr     slot_level
    cmpl    %d5,%d0
    bhis    eo_n                  | worse than the best
    bcss    eo_take               | better
    lea.l   slot_size,%a0         | as good: the bigger
    cmpl    %a0@(0,%d2:l:4),%d6
    bccs    eo_n
eo_take:
    cmpil   #3,%d0
    bccs    eo_n
    movel   %d0,%d5
    movel   %d2,%d4
    lea.l   slot_size,%a0
    movel   %a0@(0,%d2:l:4),%d6
eo_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    eo_l
    tstl    %d4
    bmis    eo_no
    tstl    pd_mode
    beqs    eo_go
    tstl    %d5                   | the preloader frees only the unused
    bnes    eo_no
eo_go:
    movel   %d4,%d0
    bsr     slot_drop
    bsr     top_calc
    moveq   #1,%d0
    bras    eo_out
eo_no:
    moveq   #0,%d0
eo_out:
    moveml  %sp@,%d1-%d6
    lea.l   %sp@(24),%sp
    rts

| slot_drop(d0 = slot): empty it. Keeps d0-d7.
slot_drop:
    movel   %d1,%sp@-
    lea.l   slot_hash,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_base,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_count,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_size,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_soff,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_pgain,%a0
    clrl    %a0@(0,%d0:l:4)
    lea.l   slot_tpat,%a0
    moveq   #-1,%d1
    movel   %d1,%a0@(0,%d0:l:4)
    lea.l   slot_nino,%a0
    clrl    %a0@(0,%d0:l:4)
    bsr     nm_clear
    movel   %sp@+,%d1
    rts

| slot_level(d0 = slot) -> d0: 3 in use - a track's slot or pending slot,
| the hash a track of the current pattern wants, a recording's or a save's
| slot; 2 a recording its own pattern's track still names; 1 a file some
| other pattern's Sampler track names; 0 nothing wants it. Keeps d1-d7.
slot_level:
    lea.l   %sp@(-20),%sp
    moveml  %d1-%d4/%a2,%sp@
    movel   %d0,%d2
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d2:l:4),%d3
    tstl    rs_state              | the recording's slot
    bnes    sl_rs
    tstl    rs_pending
    beqs    sl_nrs
sl_rs:
    cmpl    rs_slot,%d2
    beqw    sl_3
sl_nrs:
    tstl    rs_sv_state           | the save's
    beqs    sl_nsv
    cmpl    rs_sv_slot,%d2
    beqw    sl_3
sl_nsv:
    moveq   #0,%d1
sl_t:
    lea.l   track_slot,%a0
    cmpl    %a0@(0,%d1:l:4),%d2
    beqw    sl_3
    lea.l   track_pend,%a0
    movel   %a0@(0,%d1:l:4),%d0
    extl    %d0                   | the slot is the low word
    cmpl    %d0,%d2
    beqw    sl_3
    lea.l   track_hash,%a0
    cmpl    %a0@(0,%d1:l:4),%d3
    beqw    sl_3
    addql   #1,%d1
    cmpil   #MAX_TRK,%d1
    bcss    sl_t
    movel   %d3,%d0
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    bnes    sl_file
    lea.l   slot_tpat,%a0         | a recording: does its track still name
    movel   %a0@(0,%d2:l:4),%d0   | what it stands in for?
    bmis    sl_0
    lea.l   slot_ttrk,%a0
    movel   %a0@(0,%d2:l:4),%d1
    bsr     snd_tok
    lea.l   slot_ttok,%a0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnes    sl_0
    tstl    %d0
    beqs    sl_0
    moveq   #2,%d0
    bras    sl_out
sl_file:
    movel   %d3,%d0
    bsr     proj_has
    tstl    %d0
    beqs    sl_0
    moveq   #1,%d0
    bras    sl_out
sl_3:
    moveq   #3,%d0
    bras    sl_out
sl_0:
    moveq   #0,%d0
sl_out:
    moveml  %sp@,%d1-%d4/%a2
    lea.l   %sp@(20),%sp
    rts

| ---- the project's patterns ------------------------------------------------
| All 96 patterns sit in RAM: pattern n at PAT_BASE + n * PAT_SIZE, its kit at
| KIT_BASE + n * KIT_SIZE (the pairs the UI builds at 0x4002017c; the kits
| begin exactly where the 96th pattern ends). A kit holds the six track sounds
| at +28 + t * 100 (0x40054bfa: the trig takes kit + 0x1c + t * 100) and the
| 64-preset pool from +694. *CUR_PAT / *CUR_KIT are the playing pair. kit_ok
| is 1 once sound_obj(t) - which our name tokens are written through - has
| been seen to be exactly the current kit's track sound for all six tracks; 0
| if not, and then nothing here reads a kit (the current pattern alone is
| known, as before); -1 until checked.
PAT_BASE = 0x406FA040
PAT_SIZE = 30710
KIT_BASE = 0x409C9C80
KIT_SIZE = 7094
KIT_SND  = 28
SND_SIZE = 100
KIT_POOL = 694                    | the 64-sound pool (0x40054c06: +0x2b4 + 2)
KIT_NSND = 70                     | sounds a kit names: 6 tracks, 64 pool
NPAT     = 96
CUR_PAT  = 0x40a7887c
CUR_KIT  = 0x40a78888

| cur_pat -> d0 = the playing pattern's index, or -1. Keeps d1-d7.
cur_pat:
    movel   %d1,%sp@-
    movel   CUR_PAT,%d0
    subil   #PAT_BASE,%d0
    bmis    cp_no
    movel   #PAT_SIZE,%d1
    divul   %d1,%d0
    cmpil   #NPAT,%d0
    bccs    cp_no
    mulul   %d0,%d1               | exactly on a pattern?
    addil   #PAT_BASE,%d1
    cmpl    CUR_PAT,%d1
    beqs    cp_out
cp_no:
    moveq   #-1,%d0
cp_out:
    movel   %sp@+,%d1
    rts

| kit_check: sets kit_ok (see above) the first time sound objects exist. UI
| side. Keeps d2-d7.
kit_check:
    tstl    kit_ok
    bpls    kc_out
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d3/%a2,%sp@
    bsr     cur_pat
    tstl    %d0
    bmis    kc_bad
    movel   #KIT_SIZE,%d1
    mulul   %d1,%d0
    addil   #KIT_BASE,%d0
    cmpl    CUR_KIT,%d0
    bnes    kc_bad
    movel   %d0,%d3
    addil   #KIT_SND,%d3          | track 0's sound
    moveq   #0,%d2
kc_l:
    movel   %d2,%d0
    jsr     sound_obj
    tstl    %d0
    beqs    kc_later              | not up yet: check again next time
    cmpl    %d3,%d0
    bnes    kc_bad
    addil   #SND_SIZE,%d3
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    kc_l
    moveq   #1,%d0
    movel   %d0,kit_ok
    bras    kc_done
kc_bad:
    clrl    kit_ok
kc_done:
kc_later:
    moveml  %sp@,%d2-%d3/%a2
    lea.l   %sp@(12),%sp
kc_out:
    rts

| snd_tok(d0 = pattern, d1 = track) -> d0 = the hash that pattern's track
| names, if it is a Sampler with an "SMP" token, else 0 (and 0 unless
| kit_ok). Keeps d1-d7.
snd_tok:
    lea.l   %sp@(-8),%sp
    moveml  %d1-%d2,%sp@
    moveq   #1,%d2
    cmpl    kit_ok,%d2
    bnes    stk_0
    cmpil   #NPAT,%d0
    bccs    stk_0
    cmpil   #MAX_TRK,%d1
    bccs    stk_0
    movel   #KIT_SIZE,%d2
    mulul   %d2,%d0
    addil   #KIT_BASE+KIT_SND,%d0
    moveq   #SND_SIZE,%d2
    mulul   %d1,%d2
    addl    %d2,%d0
    movea.l %d0,%a0
    bsr     tok_of
    bras    stk_out
stk_0:
    moveq   #0,%d0
stk_out:
    moveml  %sp@,%d1-%d2
    lea.l   %sp@(8),%sp
    rts

| tok_of(a0 = a sound) -> d0 = the hash its "SMP" token names when it is a
| Sampler (machine byte +38 = 6), else 0 - name_probe's parse. Clobbers a0;
| keeps d1-d7.
tok_of:
    lea.l   %sp@(-12),%sp
    moveml  %d1-%d3,%sp@
    moveq   #0,%d3
    mvzb    %a0@(38),%d0
    cmpil   #6,%d0
    bnes    to_no
    mvzb    %a0@(4),%d0
    cmpil   #83,%d0               | 'S'
    bnes    to_no
    mvzb    %a0@(5),%d0
    cmpil   #77,%d0               | 'M'
    bnes    to_no
    mvzb    %a0@(6),%d0
    cmpil   #80,%d0               | 'P'
    bnes    to_no
    lea.l   %a0@(7),%a0
    moveq   #7,%d2
to_h:
    mvzb    %a0@+,%d0
    subil   #48,%d0               | '0'..'9'
    bmis    to_no
    cmpil   #10,%d0
    bcss    to_acc
    subql   #7,%d0                | 'A'..'F'
    cmpil   #10,%d0
    bcss    to_no
    cmpil   #16,%d0
    bccs    to_no
to_acc:
    lsll    #4,%d3
    orl     %d0,%d3
    subql   #1,%d2
    bpls    to_h
    movel   %d3,%d0
    bras    to_out
to_no:
    moveq   #0,%d0
to_out:
    moveml  %sp@,%d1-%d3
    lea.l   %sp@(12),%sp
    rts

| proj_has(d0 = hash) -> d0 = 1 if some pattern's Sampler track names it.
| 0 unless kit_ok. Keeps d1-d7.
proj_has:
    lea.l   %sp@(-16),%sp
    moveml  %d1-%d2/%d4/%a2,%sp@
    movel   %d0,%d4
    beqs    ph_no
    moveq   #1,%d0
    cmpl    kit_ok,%d0
    bnes    ph_no
    movel   #KIT_BASE,%d1
ph_p:
    moveq   #0,%d2
ph_t:
    bsr     kit_off
    movea.l %d1,%a0
    adda.l  %d0,%a0
    bsr     tok_of
    cmpl    %d4,%d0
    beqs    ph_yes
    addql   #1,%d2
    cmpil   #KIT_NSND,%d2
    bcss    ph_t
    addil   #KIT_SIZE,%d1
    cmpil   #KIT_BASE+NPAT*KIT_SIZE,%d1
    bcss    ph_p
ph_no:
    moveq   #0,%d0
    bras    ph_out
ph_yes:
    moveq   #1,%d0
ph_out:
    moveml  %sp@,%d1-%d2/%d4/%a2
    lea.l   %sp@(16),%sp
    rts

| kit_off(d2 = a kit's sound index: 0-5 its tracks, 6-69 its pool) -> d0 =
| that sound's offset in the kit. Keeps d1-d7.
kit_off:
    moveq   #SND_SIZE,%d0
    mulul   %d2,%d0
    cmpil   #MAX_TRK,%d2
    bcss    ko_t
    addil   #KIT_POOL-MAX_TRK*SND_SIZE,%d0
    rts
ko_t:
    addil   #KIT_SND,%d0
    rts

| el_deint (d3 = slot, d4 = the file image): a stereo file as Transfer writes
| it - header byte +1 = 1, data L,R interleaved, 4 bytes a frame - becomes our
| two planes: mid (L+R)/2 over the first half, side (L-R)/2 over the second.
| One forward pass writes the mid in place (frame i's mid lands at 2i bytes,
| never ahead of the pair it reads at 4i) and the side into the free space
| above the file, which is then copied down behind the mid. Without that much
| free space it keeps the mid alone, as mono. d3 must stay the slot
| throughout. Keeps d2-d4.
el_deint:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d6/%a2,%sp@
    movea.l %d4,%a2
    movel   %a2@(4),%d2
    lsrl    #2,%d2                | frames, by the header
    movel   out_count,%d0
    lsrl    #1,%d0                | frames actually read
    cmpl    %d2,%d0
    bccs    ed_n
    movel   %d0,%d2
ed_n:
    tstl    %d2
    beqw    ed_out
    lea.l   %a2@(64),%a0          | the pairs
    movea.l %a0,%a1               | the mid, written behind them
    movel   %d2,%d0
    lsll    #2,%d0
    movel   %a0,%d6
    addl    %d0,%d6               | the side's scratch: past the whole file
    addil   #15,%d6
    andil   #0xfffffff0,%d6
    movel   %d2,%d0
    addl    %d0,%d0
    addl    %d6,%d0
    cmpl    el_lim,%d0            | inside the file's own gap
    blss    ed_scr
    movel   alloc_top,%d6         | else above every slot (this one included)
    addil   #15,%d6
    andil   #0xfffffff0,%d6
    movel   %d2,%d0
    addl    %d0,%d0
    addl    %d6,%d0
    cmpil   #PCM_TOP,%d0
    bhis    ed_mono
ed_scr:
    movea.l %d6,%a2
    movel   %d2,%d5
ed_l:
    mvsw    %a0@+,%d0             | L
    mvsw    %a0@+,%d1             | R
    movel   %d0,%d4               | (d4 is ours until the moveml restores it)
    addl    %d1,%d4
    asrl    #1,%d4
    movew   %d4,%a1@+             | mid
    subl    %d1,%d0
    asrl    #1,%d0
    movew   %d0,%a2@+             | side, for now above the file
    subql   #1,%d5
    bnes    ed_l
    movea.l %d6,%a0               | a1 is where the side plane begins
    movel   %d2,%d5
ed_c:
    movew   %a0@+,%a1@+
    subql   #1,%d5
    bnes    ed_c
    movel   %d2,%d0
    addl    %d0,%d0
    lea.l   slot_soff,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    bras    ed_cnt
ed_mono:
    movel   %d2,%d5               | no room for the side: the mid alone
ed_ml:
    mvsw    %a0@+,%d0
    mvsw    %a0@+,%d1
    addl    %d1,%d0
    asrl    #1,%d0
    movew   %d0,%a1@+
    subql   #1,%d5
    bnes    ed_ml
ed_cnt:
    lea.l   slot_count,%a0
    movel   %d2,%a0@(0,%d3:l:4)
ed_out:
    moveml  %sp@,%d2-%d6/%a2
    lea.l   %sp@(24),%sp
    rts

| sx_quiet_slot(d0 = slot): a stereo slot whose side plane never exceeds
| +-SX_QUIET (-84 dBFS) - a mono source saved or recorded as stereo, where
| (L-R)/2 is only rounding - loses its side offset, so it plays and saves as
| mono and skips the side's whole chain. The space is reclaimed by the next
| rebuild (rs_keep moves one plane). UI side. Keeps d2-d7.
SX_QUIET = 2
sx_quiet_slot:
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d0:l:4),%d1
    beqs    sxq_out
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    lea.l   slot_base,%a1
    movea.l %a1@(0,%d0:l:4),%a1
    lea.l   %a1@(64),%a1
    adda.l  %d1,%a1               | the side plane
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d2
    beqs    sxq_mono
sxq_l:
    mvsw    %a1@+,%d1
    bpls    sxq_p
    negl    %d1
sxq_p:
    moveq   #SX_QUIET,%d3
    cmpl    %d3,%d1
    bgts    sxq_loud
    subql   #1,%d2
    bnes    sxq_l
sxq_mono:
    lea.l   slot_soff,%a0
    clrl    %a0@(0,%d0:l:4)
sxq_loud:
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
sxq_out:
    rts

| Compaction, the last resort when the free space is only in pieces: drop
| every file, pack the wanted recordings down (rs_keep) and reload what the
| tracks of the pattern on screen want; the preloader brings the rest back.
| Every track is silent until the caller re-points it (refresh_tracks).
rebuild_slots:
    lea.l   rs_state,%a0          | not while a recording owns the free space
    tstl    %a0@
    bnew    rb_busy
    lea.l   rs_pending,%a0
    tstl    %a0@
    bnew    rb_busy
    tstl    rs_sv_state
    bnew    rb_busy
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    moveq   #0,%d2                | every track silent while samples move;
    moveq   #-1,%d0               | the caller re-points them (refresh_tracks)
rb_sil:
    lea.l   track_slot,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   track_pend,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    rb_sil
    jsr     rs_keep               | recordings first, packed down to PCM_BASE
    moveq   #0,%d2
rb_clr:
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    beqs    rb_kept               | a recording rs_keep kept: leave it
    movel   %d2,%d0
    bsr     slot_drop
rb_kept:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    rb_clr
    lea.l   alloc_top,%a0
    lea.l   rs_top,%a1            | above the recordings rs_keep packed
    movel   %a1@,%d0
    movel   %d0,%a0@
    moveq   #0,%d2
rb_trk:
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    beqs    rb_next
    jsr     ensure_loaded
rb_next:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    rb_trk
    moveq   #1,%d0                | other patterns' samples reload over time
    movel   %d0,pl_dirty
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
rb_busy:
    rts

| Re-point every track at its slot. track_slot is what the audio path reads,
| so it is written last and set to -1 while a sample is in flight.
refresh_tracks:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    moveq   #0,%d2
rt_l:
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    beqs    rt_none
    jsr     ensure_loaded
    bras    rt_set
rt_none:
    moveq   #-1,%d0
rt_set:
    lea.l   track_slot,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    rt_l
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
    rts

| ---- load the sample whose hash is in want_hash to want_dest ----------
| d0 = 1 ok / 0 fail. Sets out_bytes (what was read) and leaves the file image
| at want_dest, header included. Split out of the old load_by_hash so several
| samples can be resident at once, each at its own address.
load_at:
    lea.l   %sp@(-32),%sp
    moveml  %d2-%d7/%a2-%a3,%sp@
    lea.l   fail_why,%a0
    clrl    %a0@
    movea.l #TBL_BUF,%a3
    lea.l   want_hash,%a0
    movel   %a0@,%d2
    beqw    lb_fail

    movel   #TABLE_BLOCK,%d7
lb_page:
    movel   #TABLE_END,%d0
    cmpl    %d7,%d0
    blsw    lb_nf
    movel   %a3,%sp@-
    pea     65536
    movel   %d7,%sp@-
    jsr     0x4008b24a
    lea.l   %sp@(12),%sp
    tstl    %d0
    bnew    lb_rderr
    movea.l %a3,%a2
    movel   #512,%d3
lb_rec:
    movel   %a2@,%d0
    cmpil   #0x00020001,%d0
    bnes    lb_next
    movel   %a2@(12),%d0
    cmpl    %d2,%d0
    bnes    lb_next
    movel   %a2@(36),%d4
    movel   %a2@(40),%d5
    braw    lb_found
lb_next:
    lea.l   %a2@(128),%a2
    subql   #1,%d3
    tstl    %d3
    bnew    lb_rec
    addil   #128,%d7
    braw    lb_page

lb_found:
    | Its inode, as the file system numbers them - the record's position in
    | the table (0x4007e764 reads inode n from byte n * 128), not its +16 -
    | and its size: nm_step names it. d7 is this 64 KiB page's first block.
    movel   %d7,%d0
    subil   #TABLE_BLOCK,%d0
    lsll    #2,%d0                | 512 records a page, 128 blocks a page
    movel   %a2,%d1
    subil   #TBL_BUF,%d1
    lsrl    #7,%d1
    addl    %d1,%d0
    movel   %d0,want_ino
    movel   %a2@(4),%d0
    movel   %d0,want_isz
    movel   %d4,%d3
    lsll    #8,%d3
    lsll    #6,%d3                | bytes = chunks * 16384
    movel   %d3,%d0
    bsr     pick_dest             | a gap for it, evicting as allowed
    tstl    %d0
    bnes    lb_fits
    moveq   #5,%d0                | no room in the region
    braw    lb_why
lb_fits:
    movel   %d0,want_dest
    movel   %d0,%d4               | write pointer
    movel   %d5,%d7
    lsll    #5,%d7
    addil   #DATA_BASE,%d7        | first block
    movel   %d3,%d5               | bytes still wanted
    lea.l   out_bytes,%a0
    movel   %d3,%a0@
lb_piece:
    tstl    %d5
    beqs    lb_read_done
    moveal  #65536,%a2
    cmpl    %d5,%a2
    blss    lb_go
    moveal  %d5,%a2
lb_go:
    movel   %d4,%sp@-
    movel   %a2,%sp@-
    movel   %d7,%sp@-
    jsr     0x4008b24a
    lea.l   %sp@(12),%sp
    tstl    %d0
    bnew    lb_rderr
    addl    %a2,%d4
    subl    %a2,%d5
    movel   %a2,%d0
    lsrl    #8,%d0
    lsrl    #1,%d0
    addl    %d0,%d7
    bras    lb_piece
lb_read_done:
    lea.l   want_dest,%a0
    movea.l %a0@,%a2              | validate the header where we put it
    movel   %a2@(8),%d0
    cmpil   #48000,%d0
    bnew    lb_fmt
    movel   %a2@(4),%d0
    beqw    lb_fmt
    lsrl    #1,%d0                | samples the file claims
    movel   %d3,%d1
    subil   #64,%d1
    lsrl    #1,%d1                | samples we actually hold
    cmpl    %d0,%d1
    bccs    lb_cnt
    movel   %d1,%d0
lb_cnt:
    lea.l   out_count,%a0
    movel   %d0,%a0@
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(32),%sp
    moveq   #1,%d0
    rts

lb_nf:
    moveq   #1,%d0
    braw    lb_why
lb_rderr:
    lea.l   err_blk,%a0           | remember what failed, for the popup
    movel   %d7,%a0@
    lea.l   err_len,%a0
    movel   %a2,%a0@
    moveq   #3,%d0
    braw    lb_why
lb_fmt:
    moveq   #4,%d0
lb_why:
    lea.l   fail_why,%a0
    movel   %d0,%a0@
lb_fail:
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(32),%sp
    moveq   #0,%d0
    rts

| ---- live pad: load the default sample once, so something plays on boot ----
pad_load_hook:
    | Empty, permanently. A probe here loads samples itself, which both causes
    | the first-hit pause and hides whether the real loader ran.
    linkw   %fp,#-104             | REPLAY the two overwritten instructions
    moveq   #127,%d0
    jmp     0x40081724

| ---- is the Sampler machine on any track? d0 = 1 / 0 ----
| Lifted verbatim from sampler_voice63's refresh_flags, which ran safely on the
| trigger path. NOTE the indirection: `this` is the track-object ADDRESS (d6)
| and the vtable is *trackObj. An earlier version dereferenced once too many
| (obj = *trackObj, vtable = *obj) and faulted at the vcall.
any_sampler:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a3,%sp@
    lea.l   as_found,%a2
    clrl    %a2@
    jsr     0x400cf866
    tstl    %d0
    beqs    as_done
    movel   %d0,%d2
    moveq   #0,%d3
as_loop:
    movel   %d3,%d4
    moveq   #68,%d5
    mulsl   %d5,%d4
    movel   %d2,%d6
    addil   #212,%d6
    addl    %d4,%d6               | d6 = trackObj
    movea.l %d6,%a2
    movel   %a2@,%d7              | vtable
    beqs    as_next
    movea.l %d7,%a3
    movel   %d6,%sp@-             | this = trackObj
    movea.l %a3@(40),%a3
    movel   %a3,%d7
    beqs    as_pop
    jsr     %a3@
    addql   #4,%sp
    tstl    %d0
    beqs    as_next
    movea.l %d0,%a2
    moveb   %a2@(38),%d0          | machine index
    andil   #0xff,%d0
    cmpil   #6,%d0
    bnes    as_next
    lea.l   as_found,%a2
    moveq   #1,%d0
    movel   %d0,%a2@
    bras    as_next
as_pop:
    addql   #4,%sp
as_next:
    addql   #1,%d3
    moveq   #6,%d0
    cmpl    %d3,%d0
    bccs    as_loop
as_done:
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(40),%sp
    lea.l   as_found,%a0          | a0 is saved by the caller
    movel   %a0@,%d0
    rts

| ---- d0 = track index  ->  d0 = runtime sound object, or 0 --------------
| The walk is any_sampler's as_loop body verbatim (proven on hardware in
| samplerBB): owner(n) = singleton + 212 + n*68, then vtable slot 40.
| Both halves are confirmed against the firmware's own derivation at
| 0x40023f0a:  0x40009c1a(0x4000eb9c(singleton), idx)
|   0x4000eb9c(x) = x + 116          (address arithmetic, not a load)
|   0x40009c1a(b,i) = b + i*68 + 0x60   (=96; brief-extension disp is HEX)
| giving singleton + 212 + i*68, clamped to 0..5 - the six tracks.
sound_obj:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d5/%a2-%a3,%sp@
    movel   %d0,%d3
    cmpil   #MAX_TRK,%d3
    bccs    so_none
    jsr     0x400cf866
    tstl    %d0
    beqs    so_none
    movel   %d0,%d2
    movel   %d3,%d4
    moveq   #68,%d5
    mulsl   %d5,%d4
    movel   %d2,%d5
    addil   #212,%d5
    addl    %d4,%d5               | d5 = trackObj
    movea.l %d5,%a2
    movel   %a2@,%d4              | vtable
    beqs    so_none
    movea.l %d4,%a3
    movel   %d5,%sp@-             | this = trackObj
    movea.l %a3@(40),%a3
    movel   %a3,%d4
    beqs    so_pop
    jsr     %a3@
    addql   #4,%sp
    bras    so_out
so_pop:
    addql   #4,%sp
so_none:
    moveq   #0,%d0
so_out:
    moveml  %sp@,%d2-%d5/%a2-%a3
    lea.l   %sp@(24),%sp
    rts

| ---- d0 = track, d1 = hash: stamp the sound NAME with our token ----------
| The 16 bytes at runtimeSound+4 are the preset name. The kit serialiser
| 0x4005afa0 copies them to soundStorage+12 wholesale and unconditionally
| (memcpy(storage+12, runtime+4, 16)), so anything we leave here is saved
| with the project and restored with it. We write it as printable text -
| "SMP" + 8 hex digits - so the track legibly shows which sample it holds
| and persistence can be confirmed by eye.
| Plain stores only: no firmware call, so this is safe on the preset path
| (samplerBK froze by calling into the sound layer from right here).
name_store:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a2,%sp@
    movel   %d1,%d3               | hash
    movel   %d0,%d5               | track, needed for the mode byte below
    jsr     sound_obj             | d0 still = track
    tstl    %d0
    beqw    ns_st_done
    movea.l %d0,%a2
    addql   #4,%a2                | the name field
    moveq   #83,%d4
    moveb   %d4,%a2@+             | 'S'
    moveq   #77,%d4
    moveb   %d4,%a2@+             | 'M'
    moveq   #80,%d4
    moveb   %d4,%a2@+             | 'P'
    moveq   #7,%d2                | 8 nibbles, most significant first
ns_hx:
    movel   %d2,%d1
    addl    %d1,%d1
    addl    %d1,%d1               | d1 = d2 * 4
    movel   %d3,%d4
    lsrl    %d1,%d4
    andil   #15,%d4
    cmpil   #10,%d4
    bccs    ns_af
    addil   #48,%d4               | '0'
    bras    ns_put
ns_af:
    addil   #55,%d4               | 'A' - 10
ns_put:
    moveb   %d4,%a2@+
    subql   #1,%d2
    bpls    ns_hx
    | Byte 11 carries the playback mode: 'L' = loop, 0 = one-shot. A project
    | saved before this existed has 0 here and reads back as one-shot, which is
    | the default we want - nothing to migrate.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d5:l:4),%d4
    beqs    ns_mode               | One shot: 0 (its option is in byte 13)
ns_notos:
    cmpil   #1,%d4
    bnes    ns_slice
    moveq   #76,%d4               | 'L' loop
    bras    ns_mode
ns_slice:
    cmpil   #2,%d4
    bnes    ns_gran
    moveq   #83,%d4               | 'S' slice
    bras    ns_mode
ns_gran:
    cmpil   #3,%d4
    bnes    ns_strch
    moveq   #71,%d4               | 'G' granular
    bras    ns_mode
ns_strch:
    cmpil   #4,%d4
    bnes    ns_pluck
    moveq   #84,%d4               | 'T' stretch ('S' is slice)
    bras    ns_mode
ns_pluck:
    cmpil   #5,%d4
    bnes    ns_wave
    moveq   #80,%d4               | 'P' pluck
    bras    ns_mode
ns_wave:
    moveq   #87,%d4               | 'W' wavetable
ns_mode:
    moveb   %d4,%a2@+
    | Byte 12: the slice option, 'A' + 0..5. A project saved before this has 0
    | there, which name_probe reads as the default, 16 equal slices.
    lea.l   sl_cfg,%a0
    movel   %a0@(0,%d5:l:4),%d4
    addil   #65,%d4
    moveb   %d4,%a2@+
    | Byte 13: the current mode's option, 'A' + n, or 0 if it has none.
    | Granular packs its three: 'A' + (shape | direction << 2 | freeze << 4).
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d5:l:4),%d4
    cmpil   #3,%d4
    bnes    ns_ngr
    lea.l   gr_dir,%a0
    movel   %a0@(0,%d5:l:4),%d4
    lsll    #2,%d4
    lea.l   gr_shape,%a0
    orl     %a0@(0,%d5:l:4),%d4
    lea.l   gr_frz,%a0
    tstl    %a0@(0,%d5:l:4)
    beqs    ns_gr1
    oril    #16,%d4
ns_gr1:
    addil   #65,%d4
    bras    ns_opt
ns_ngr:
    cmpil   #6,%d4
    bhis    ns_noopt
    lea.l   opt_menus,%a0
    movel   %a0@(0,%d4:l:4),%d4
    beqs    ns_noopt
    movea.l %d4,%a0
    movea.l %a0@,%a0
    movel   %a0@(0,%d5:l:4),%d4
    addil   #65,%d4
    bras    ns_opt
ns_noopt:
    moveq   #0,%d4
ns_opt:
    moveb   %d4,%a2@+
    moveq   #0,%d4                | pad the remaining 2 of the 16 bytes
    moveq   #1,%d2
ns_pad:
    moveb   %d4,%a2@+
    subql   #1,%d2
    bpls    ns_pad
ns_st_done:
    moveml  %sp@,%d2-%d5/%a2
    lea.l   %sp@(20),%sp
    rts

| ---- the Sample machine's modes and options, packed into the sound ---------
| The name token keeps only the CURRENT mode's option, and is written only once
| a sample is assigned. So every mode's option also goes, packed into one long,
| into the sound's parameter words k=26/27 (sound +72/+74): no param_table entry
| names them, so nothing but us reads or writes them, the 66-byte audio mirror
| carries them harmlessly, and snd_save_post / snd_load_post keep them in
| record slots 28/29 (+84..+87). They travel with the sound wherever it goes.
| The layout is st_fields: {table, -, -, largest value} per setting, packed
| as one mixed-radix number (the product of the ranges is 213,373,440, under
| 2^28) with ST_TAG in bits 28-31. Anything without the tag - every older
| record, including samplerGI's bit-field layout, whose bits 28-30 could never
| read 7 - is "none": the settings go to their defaults and name_probe reads
| the token as it always did.
| samplerIS widened sl_cfg to 0..6 (MAN), which moves every later field's
| place value, so the layout got a new tag: ST_TAG_OLD words decode with the
| old range (0..5). The product is now 248,935,680, still under 2^28, and 7
| in bits 28-31 is no more possible in samplerGI's layout than 15 was.
ST_TAG     = 0x70000000
ST_TAG_OLD = 0xF0000000
ST_TAGMASK = 0xF0000000
ST_DEFAULT = ST_TAG + 35280       | the tag and sl_cfg = 1 (16 equal slices):
                                  | its place value is 7*5*2*7*3*6*4 = 35280
    .align 4
st_fields:
    .long loop_mode, 0,  7, 6     | One shot .. Wavetable
    .long fx_sel,    3,  7, 4     | Filter Lo-fi Tape Vinyl None
    .long chn_sel,   6,  1, 1     | Mono Stereo
    .long stu_sel,   7,  7, 6     | OFF 1/4 1/8 1/16 1/32 8T 16T
    .long lp_type,   10, 3, 2     | Forward Reverse Ping-pong
    .long lp_xfd,    12, 7, 5     | OFF 10 25 50 100 250 ms
    .long lp_sync,   15, 3, 3     | OFF 1 2 4 bars
st_f_slc:
    .long sl_cfg,    17, 7, 6     | Equal / Transient x 8 16 32, Manual
    .long st_opt,    20, 7, 6     | Stretch's seven
    .long pk_mode,   23, 1, 1     | Synth Drum
    .long pk_exc,    24, 3, 2     | Sample Noise Click
    .long gr_shape,  26, 3, 3
    .long gr_dir,    28, 3, 2
    .long gr_frz,    30, 1, 1
st_fields_end:
    .long 0
| sa_no: what goes back to its default when a sound has no usable state (the
| mode, slices and granular settings still come from the name token)
st_reset:
    .long fx_sel, chn_sel, stu_sel, lp_type, lp_xfd, lp_sync, st_opt
    .long pk_mode, pk_exc, 0

| sl_cfg (0..5, the slice tables' own encoding) <-> the menu's two rows,
| Mode (sl_md, Equal/Transient) and Slices (sl_ct, 8/16/32). d2 = track.
opt_derive:                       | sl_cfg -> sl_md, sl_ct
    lea.l   sl_cfg,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #6,%d0
    bnes    od_ae
    moveq   #2,%d1                | MAN (SLC keeps its value)
    lea.l   sl_md,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    rts
od_ae:
    moveq   #0,%d1
    cmpil   #3,%d0
    bcss    od_e
    moveq   #1,%d1
    subql   #3,%d0
od_e:
    lea.l   sl_md,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    lea.l   sl_ct,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    rts
opt_mc2cfg:                       | sl_md, sl_ct -> sl_cfg
    lea.l   sl_md,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpil   #2,%d0
    bnes    omc_ae
    moveq   #6,%d0                | MAN: markers, seeded from what it had
    lea.l   sl_cfg,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d2,%d0
    jmp     sle_seed
omc_ae:
    movel   %d0,%d1
    addl    %d0,%d0
    addl    %d1,%d0               | x3
    lea.l   sl_ct,%a0
    addl    %a0@(0,%d2:l:4),%d0
    lea.l   sl_cfg,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    rts

| d0 = track. Packs the tables and writes them to that track's sound.
| Preserves every register but d0.
state_store:
    lea.l   %sp@(-24),%sp
    moveml  %d1-%d3/%a0-%a2,%sp@
    movel   %d0,%d2
    jsr     sound_obj
    tstl    %d0
    beqw    ss_out
    movea.l %d0,%a2
    lea.l   st_fields_end,%a1     | last field first: acc = acc * range + value
    moveq   #0,%d3
ss_f:
    lea.l   %a1@(-16),%a1
    movel   %a1@(12),%d0
    addql   #1,%d0                | the field's range
    mulul   %d0,%d3
    movea.l %a1@,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpl    %a1@(12),%d0          | out of range can only be a bug: store 0
    blss    ss_v
    moveq   #0,%d0
ss_v:
    addl    %d0,%d3
    cmpal   #st_fields,%a1
    bhis    ss_f
    orl     #ST_TAG,%d3
    movel   %d3,%a2@(72)
ss_out:
    moveml  %sp@,%d1-%d3/%a0-%a2
    lea.l   %sp@(24),%sp
    rts

| d2 = track, a2 = its sound. If the sound holds a valid packed state, set the
| tables from it and return d0 = 1; otherwise d0 = 0 and nothing changes. Any
| field out of range makes the whole word invalid. d1/a0/a1 are scratch.
| st_apply_c: st_apply, only when sound+72 differs from what was last decoded
| for this track (name_probe calls it every tick for every Sampler track).
st_apply_c:
    movel   %a2@(72),%d0
    lea.l   st_cache,%a0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnes    sac_new
    lea.l   st_cres,%a0
    movel   %a0@(0,%d2:l:4),%d0
    rts
sac_new:
    movel   %d0,%a0@(0,%d2:l:4)
    bsr     st_apply
    lea.l   st_cres,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    rts
st_apply:
    lea.l   %sp@(-8),%sp
    moveml  %d3-%d4,%sp@
    movel   %a2@(72),%d3
    movel   %d3,%d0
    andil   #ST_TAGMASK,%d0
    moveq   #0,%d4                | this layout
    cmpil   #ST_TAG,%d0
    beqs    sa_ok
    moveq   #1,%d4                | samplerIR's and before: sl_cfg 0..5
    cmpil   #ST_TAG_OLD,%d0
    bnew    sa_no                 | no state, or one in an older layout
sa_ok:
    andil   #~ST_TAGMASK,%d3
    lea.l   st_fields,%a1         | first field first: value = acc % range
sa_set:
    movel   %a1@,%d0
    beqs    sa_der
    movel   %a1@(12),%d1
    addql   #1,%d1
    tstl    %d4
    beqs    sa_rng
    cmpal   #st_f_slc,%a1
    bnes    sa_rng
    moveq   #6,%d1
sa_rng:
    movel   %d3,%d0
    divul   %d1,%d0               | acc / range
    movel   %d0,%sp@-
    mulul   %d1,%d0
    subl    %d3,%d0
    negl    %d0                   | acc % range
    movea.l %a1@,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %sp@+,%d3
    lea.l   %a1@(16),%a1
    bras    sa_set
sa_der:
    bsr     opt_derive            | the slice menu's two rows, from sl_cfg
    moveq   #1,%d0
    moveml  %sp@,%d3-%d4
    lea.l   %sp@(8),%sp
    rts
sa_no:
    lea.l   st_reset,%a1          | Effect, Channels, Stutter, the Loop, Pluck
sa_r:                             | and Stretch settings: their defaults
    movel   %a1@+,%d0
    beqs    sa_re
    movea.l %d0,%a0
    clrl    %a0@(0,%d2:l:4)
    bras    sa_r
sa_re:
    moveq   #0,%d0
    moveml  %sp@,%d3-%d4
    lea.l   %sp@(8),%sp
    rts

| take_for(d0 = token, d1 = track) -> d0 = the recording that stands in for
| that token on that track of the playing pattern (a slot whose owner is
| exactly that), else the token. Keeps d1-d7.
take_for:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d5,%sp@
    movel   %d0,%d5
    bsr     cur_pat
    movel   %d0,%d4
    bmis    tf_tok
    moveq   #0,%d2
tf_l:
    lea.l   slot_tpat,%a0
    cmpl    %a0@(0,%d2:l:4),%d4
    bnes    tf_n
    lea.l   slot_ttrk,%a0
    cmpl    %a0@(0,%d2:l:4),%d1
    bnes    tf_n
    lea.l   slot_ttok,%a0
    cmpl    %a0@(0,%d2:l:4),%d5
    bnes    tf_n
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bnes    tf_out
tf_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    tf_l
tf_tok:
    movel   %d5,%d0
tf_out:
    moveml  %sp@,%d2-%d5
    lea.l   %sp@(16),%sp
    rts

| ---- read the tokens back and re-point any track that changed -----------
| Runs on the pad path. After a project load the sound names have been
| repopulated from storage, so a track whose token no longer matches
| track_hash is one the project just handed us: adopt it and reload.
name_probe:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d5/%a2-%a3,%sp@
    bsr     kit_check             | the kit layout, once sounds exist
    moveq   #0,%d5                | dirty
    moveq   #0,%d2                | track
    lea.l   tok_seen,%a0
    clrl    %a0@
np_l:
    movel   %d2,%d0
    jsr     sound_obj
    tstl    %d0
    beqw    np_next
    movea.l %d0,%a2
    moveb   %a2@(38),%d0          | machine index
    andil   #0xff,%d0
    cmpil   #6,%d0
    bnew    np_nosmp              | only the Sampler carries a token
    bsr     st_apply_c            | the packed state, when the sound has one
    lea.l   st_ok,%a0
    movel   %d0,%a0@
    lea.l   %a2@(4),%a3
    moveb   %a3@(0),%d0
    andil   #0xff,%d0
    cmpil   #83,%d0
    bnew    np_notok
    moveb   %a3@(1),%d0
    andil   #0xff,%d0
    cmpil   #77,%d0
    bnew    np_notok
    moveb   %a3@(2),%d0
    andil   #0xff,%d0
    cmpil   #80,%d0
    bnew    np_notok
    moveq   #0,%d3                | hash
    moveq   #0,%d4                | digit
np_hx:
    moveb   %a3@(3,%d4:l),%d0
    andil   #0xff,%d0
    cmpil   #48,%d0
    bcsw    np_notok              | not hex: ignore the whole token
    cmpil   #58,%d0
    bccs    np_al
    subil   #48,%d0
    bras    np_acc
np_al:
    cmpil   #65,%d0
    bcsw    np_notok
    cmpil   #71,%d0
    bccw    np_notok
    subil   #55,%d0
np_acc:
    lsll    #4,%d3
    orl     %d0,%d3
    addql   #1,%d4
    cmpil   #8,%d4
    bcss    np_hx
    tstl    %d3
    beqw    np_notok
    | byte 11 is the playback mode, written by name_store - unless the packed
    | state has already set mode and options, in which case only the hash is
    | taken from the token
    lea.l   st_ok,%a0
    tstl    %a0@
    bnew    np_nopt
    moveb   %a3@(11),%d0
    andil   #0xff,%d0
    moveq   #0,%d1
    cmpil   #76,%d0               | 'L' loop
    bnes    np_slice
    moveq   #1,%d1
    bras    np_mode
np_slice:
    cmpil   #83,%d0               | 'S' slice
    bnes    np_gran
    moveq   #2,%d1
    bras    np_mode
np_gran:
    cmpil   #71,%d0               | 'G' granular
    bnes    np_strch
    moveq   #3,%d1
    bras    np_mode
np_strch:
    cmpil   #84,%d0               | 'T' stretch
    bnes    np_pluck
    moveq   #4,%d1
    bras    np_mode
np_pluck:
    cmpil   #80,%d0               | 'P' pluck
    bnes    np_wave
    moveq   #5,%d1
    bras    np_mode
np_wave:
    cmpil   #87,%d0               | 'W' wavetable
    bnes    np_lofi
    moveq   #6,%d1
np_lofi:
np_mode:
    lea.l   loop_mode,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    moveq   #0,%d1                | 'F': One shot (mode 0 above) with Lo-fi
    cmpil   #70,%d0
    bnes    np_nolf
    moveq   #1,%d1
np_nolf:
    lea.l   os_opt,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    moveb   %a3@(12),%d0          | byte 12: the slice option, 'A'..'G'
    andil   #0xff,%d0
    subil   #65,%d0
    cmpil   #6,%d0
    blss    np_slc
    moveq   #1,%d0                | anything else: 16 equal slices
np_slc:
    lea.l   sl_cfg,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    | byte 13: the mode's option ('A' + n). Absent - a project saved before
    | options - leaves the mode's option alone, bar samplerEV's 'F' above.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d2:l:4),%d1
    cmpil   #3,%d1
    bnes    np_ngr
    moveb   %a3@(13),%d0          | granular: shape | direction << 2 | freeze << 4
    andil   #0xff,%d0
    subil   #65,%d0
    cmpil   #31,%d0
    bhis    np_nopt
    movel   %d0,%d1
    andil   #3,%d1
    lea.l   gr_shape,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    movel   %d0,%d1
    lsrl    #2,%d1
    andil   #3,%d1
    cmpil   #2,%d1
    blss    np_gdir
    moveq   #0,%d1
np_gdir:
    lea.l   gr_dir,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    lsrl    #4,%d0
    andil   #1,%d0
    lea.l   gr_frz,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    bras    np_nopt
np_ngr:
    cmpil   #6,%d1
    bhis    np_nopt
    lea.l   opt_menus,%a0
    movel   %a0@(0,%d1:l:4),%d1
    beqs    np_nopt
    movea.l %d1,%a1
    moveb   %a3@(13),%d0
    andil   #0xff,%d0
    subil   #65,%d0
    cmpl    %a1@(4),%d0
    bccs    np_nopt
    movea.l %a1@,%a0
    movel   %d0,%a0@(0,%d2:l:4)
np_nopt:
    lea.l   tok_seen,%a0          | a real token, whether or not it changed
    addql   #1,%a0@
np_take:                          | a recording made on this track in this
    movel   %d3,%d0               | pattern stands in for what its token names
    movel   %d2,%d1
    bsr     take_for
    movel   %d0,%d3
np_adopt:
    lea.l   track_hash,%a0        | per pattern: whatever the pattern on screen
    cmpl    %a0@(0,%d2:l:4),%d3   | names is what the track plays - load_pending
    beqw    np_next               | resolves it (already what we are playing)
    movel   %d3,%a0@(0,%d2:l:4)
    lea.l   track_tried,%a0       | a new chance for a hash that failed before
    clrl    %a0@(0,%d2:l:4)
    moveq   #1,%d0
    movel   %d0,pl_dirty
    moveq   #1,%d5
    bras    np_next
np_notok:                         | a Sampler with no token: no sample - unless
    moveq   #0,%d3                | a recording was made on it here
    bras    np_take
np_nosmp:                         | not a Sampler in this pattern: nothing
    moveq   #0,%d3
    bras    np_adopt
np_next:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcsw    np_l
np_done:                          | loading is load_pending's job now
    moveml  %sp@,%d2-%d5/%a2-%a3
    lea.l   %sp@(24),%sp
    lea.l   tok_seen,%a0          | d0 = how many tracks carried a token
    movel   %a0@,%d0
    rts

| ---- load EVERY pending sample, now, in this call -----------------------
| samplerBX loaded one per tick, on the assumption that the Timer at
| 0x400ff9cc slot 10 is periodic. It is not. Its callback feeds the pad/voice
| trigger path, so it ticks on input, not on a clock: the user watched TK crawl
| 05 -> 33 across a whole session, and with the sequencer running for minutes a
| second sample would not load until a pad was pressed. The handful of ticks
| that do happen must therefore do all the work, which is why samplerBW worked.
| track_tried holds the hash last attempted per track, so a sample whose file
| is missing is tried once and then left alone, while a NEW hash (a fresh
| selection) always retries because tried != hash again.
| d0 = 1 if anything was loaded, else 0. d4 survives ensure_loaded, which saves
| %d2-%d4/%a2.
load_pending:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d5/%a2-%a3,%sp@
    moveq   #0,%d4                | loaded anything?
    moveq   #0,%d2
lp_l:
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d3
    bnes    lp_h
    lea.l   track_slot,%a0        | no sample wanted: what it plays now goes
    tstl    %a0@(0,%d2:l:4)       | silent at its next note
    bpls    lp_sil
    lea.l   track_pend,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    lp_next
    extl    %d0
    bmiw    lp_next
lp_sil:
    lea.l   track_pend,%a0
    movel   #PEND_SILENT,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    braw    lp_next
lp_h:
    lea.l   track_pend,%a0        | what it will play next: the pending slot,
    movel   %a0@(0,%d2:l:4),%d0   | else its slot
    bmis    lp_cur
    extl    %d0
    bras    lp_have
lp_cur:
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
lp_have:
    tstl    %d0
    bmis    lp_want
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d0:l:4),%d3
    beqw    lp_next               | that already is it
lp_want:
    lea.l   track_tried,%a0
    cmpl    %a0@(0,%d2:l:4),%d3
    beqw    lp_next               | tried this exact hash already, it failed
    movel   %d3,%d0
    jsr     ensure_loaded
    tstl    %d0
    bpls    lp_got
    tstl    el_frag               | room only in pieces: compact and retry
    beqs    lp_fail
    jsr     rebuild_slots
    jsr     refresh_tracks
    moveq   #1,%d4
    braw    lp_next
lp_fail:
    lea.l   track_tried,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    lea.l   track_pend,%a0        | not this pattern's sample, then silence
    movel   #PEND_SILENT,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    bras    lp_next
lp_got:
    oril    #PEND_NOFADE,%d0      | the pattern's own sample: taken up at the
    lea.l   track_pend,%a0        | track's next note (or once idle), no fade
    movel   %d0,%a0@(0,%d2:l:4)
    moveq   #1,%d4                | keep going - there may be no next tick
lp_next:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcsw    lp_l
    movel   %d4,%d0
lp_out:
    moveml  %sp@,%d2-%d5/%a2-%a3
    lea.l   %sp@(24),%sp
    rts

| ---- the preloader: every sample the project's patterns name, in RAM ----
| One file per UI tick while pl_dirty (set at boot, when a pattern or project
| brings new tokens, and after a rebuild), so a pattern change finds its
| samples already resident. It only takes free space - pd_mode 1 evicts
| nothing any pattern uses - and leaves PL_RESERVE at the top for recording.
| A file it cannot find is remembered in pl_fail and not retried; running out
| of room stops it until something changes.
PL_RESERVE = 0x01000000           | 16 MiB kept free for takes
pl_step:
    tstl    pl_dirty
    beqw    pls_out
    moveq   #1,%d0
    cmpl    kit_ok,%d0
    bnew    pls_out
    tstl    rs_state
    bnew    pls_out
    tstl    rs_pending
    bnew    pls_out
    tstl    rs_sv_state
    bnew    pls_out
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    movel   #KIT_BASE,%d4
pls_p:
    moveq   #0,%d2
pls_t:
    bsr     kit_off
    movea.l %d4,%a0
    adda.l  %d0,%a0
    bsr     tok_of
    movel   %d0,%d3
    beqs    pls_n
    andil   #0xffffff00,%d0       | recordings and cleared tracks: not files
    cmpil   #RS_HASH,%d0
    beqs    pls_n
    moveq   #0,%d0                | resident?
pls_r:
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d0:l:4),%d3
    beqs    pls_n
    addql   #1,%d0
    cmpil   #MAX_SLOT,%d0
    bcss    pls_r
    moveq   #PL_NFAIL-1,%d0       | known missing?
pls_f:
    lea.l   pl_fail,%a0
    cmpl    %a0@(0,%d0:l:4),%d3
    beqs    pls_n
    subql   #1,%d0
    bpls    pls_f
    bras    pls_go
pls_n:
    addql   #1,%d2
    cmpil   #KIT_NSND,%d2
    bcsw    pls_t
    addil   #KIT_SIZE,%d4
    cmpil   #KIT_BASE+NPAT*KIT_SIZE,%d4
    bcsw    pls_p
    clrl    pl_dirty              | everything named is resident
    bras    pls_done
pls_go:
    moveq   #1,%d0
    movel   %d0,pd_mode
    movel   %d3,%d0
    jsr     ensure_loaded
    clrl    pd_mode
    tstl    %d0
    bpls    pls_done
    moveq   #5,%d0                | no room: stop until something changes
    cmpl    fail_why,%d0
    bnes    pls_miss
    clrl    pl_dirty
    bras    pls_done
pls_miss:
    movel   pl_fn,%d0             | missing or unreadable: skip it from now on
    lea.l   pl_fail,%a0
    movel   %d3,%a0@(0,%d0:l:4)
    addql   #1,%d0
    andil   #PL_NFAIL-1,%d0
    movel   %d0,pl_fn
pls_done:
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
pls_out:
    rts
    .balign 4
pl_dirty:  .long 1
pl_fn:     .long 0
pl_fail:   .space 4*PL_NFAIL

| ---- input-driven fallback: KeyboardView slot 2 ------------------------
| 0x400ff9cc is slot 2 of the SECONDARY vtable of the object at 0x400ff9b0,
| which multiply-inherits 10LedHandler and 12KeyboardView. This is the
| KeyboardView side, so it fires on pad/UI input, never on a clock - which is
| why it alone could not load at boot.
| It stays purely as a net for led_hook's IPL guard: if that ever declines,
| input still recovers the samples. Normally it finds nothing to do.
| Two arguments: the body reads %sp@(48) and %sp@(52) behind a 44-byte frame.
tick_hook:
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    jsr     0x4001a0d2
    addql   #8,%sp
    lea.l   %sp@(-48),%sp
    moveml  %d0-%d7/%a0-%a3,%sp@
    jsr     atk_watch
    jsr     name_probe
    jsr     load_pending
    jsr     pl_step
    jsr     nm_step
    jsr     nm_tick
    jsr     sys_tick
    jsr     rs_watch
    moveml  %sp@,%d0-%d7/%a0-%a3
    lea.l   %sp@(48),%sp
    rts

| ---- the clock: LedHandler's empty virtual ------------------------
| Our working hook turned out to be KeyboardView slot 2 (the object at
| 0x400ff9b0 multiply-inherits LedHandler and 12KeyboardView), which is why it
| is input-driven. The LedHandler side is the one that ought to tick: LEDs
| animate with no input at all.
| 0x400d7648 is LedHandler's default for that virtual and it is literally `rts`
| - five vtables share it. Replacing it with a counting no-op therefore cannot
| change any behaviour, whatever those five classes turn out to be, and does not
| need forwarding because there is nothing to forward to.
| COUNT ONLY for now. No filesystem work here until the popup shows this is
| periodic AND we know the context, because a blocking read in the wrong context
| would hang rather than merely glitch.
| ---- persist Attack (parameter k=23) through the sound record -----------
| A sound is a fixed 100-byte record: magic, version, 16-byte name, then 32
| parameter slots at +28..+91. The save maps 23 of them through a table at
| 0x4010ee4c; k=23 has no slot, and that table CANNOT be extended, because its
| 24th entry is physically the first entry of the inverse table at 0x4010eea8
| that the loader uses - the two overlap at the same address.
|
| So neither map is touched. One spare slot is carried explicitly instead:
| storage+76 (slot 24). The load loop only walks slots 0..23, so nothing else
| reads it, and the save's own memset of +28..+91 means every record ever
| written has zero there - old projects load with Attack 0, which is its
| default. The v0->v1 and v1->v2 migrations copy +28..+91 verbatim, so older
| records keep it too.
|
| Deliberately NOT slot 18, which is the other free one: the loader's map sends
| slot 18 to parameter 0, so anything stored there would also land on k=0.
|
| All three functions begin with the same 8 bytes
|     lea %sp@(-12),%sp ; moveml %a2-%a4,%sp@
| so each hook replays those and jumps into the body, having first pushed its
| own epilogue as the return address. The body's own rts then lands there with
| the arguments still on the stack.
snd_save2_hook:
    movel   %sp@(8),%sp@-         | runtime
    movel   %sp@(8),%sp@-         | storage
    pea     snd_save_post
    lea.l   %sp@(-12),%sp
    moveml  %a2-%a4,%sp@
    jmp     0x4005afa8

snd_save1_hook:
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    pea     snd_save_post
    lea.l   %sp@(-12),%sp
    moveml  %a2-%a4,%sp@
    jmp     0x4005b05c

    | sp@(0) = storage, sp@(4) = runtime. d0 carries the function's result and
    | must survive; d1/a0/a1 are scratch.
snd_save_post:
    movea.l %sp@(0),%a0
    movea.l %sp@(4),%a1
    movew   %a1@(66),%d1
    movew   %d1,%a0@(76)
    movel   %d0,%sp@              | storage pointer is in a0 now: its stack
    mvsw    %a1@(68),%d0          | slot holds d0 meanwhile. Filter is stored
    movel   #32512,%d1            | inverted, so the zero every older record
    subl    %d0,%d1               | has there reads back wide open
    movew   %d1,%a0@(78)
    movew   %a1@(70),%d1          | Resonance: zero is its default anyway
    movew   %d1,%a0@(80)
    | Destinations. The save sends a destination (a parameter index) through
    | the same 23-entry map as the values, so Attack/Filter/Res (23/24/25) read
    | past its end and came back as indices 0/1/2 - Filter as LFO Speed. The
    | stock bytes are left as they are; slot 27 (+82, +83) carries ours, and
    | snd_load_post puts them back. Zero, as in every older record, is "none".
    | +82: the LFO destination, param k=4, index in its high byte.
    | +83: the second destination field, runtime +0x58, saved at +0x5e.
    moveq   #0,%d0
    moveb   %a1@(28),%d0
    bsr     dst_ours
    moveb   %d0,%a0@(82)
    movel   %a1@(0x58),%d0
    bsr     dst_ours
    moveb   %d0,%a0@(83)
    movel   %a1@(72),%d1          | the Sample machine's packed state (k=26/27,
    movel   %d1,%a0@(84)          | see state_store) -> slots 28 and 29
    movel   %sp@,%d0
    addql   #8,%sp
    rts

| d0 = the index if it is one of ours (23..25), otherwise 0. d1 is scratch.
dst_ours:
    movel   %d0,%d1
    subil   #23,%d1
    cmpil   #2,%d1
    blss    do_keep
    moveq   #0,%d0
do_keep:
    rts

    | the loader takes its arguments the other way round: runtime first
snd_load_hook:
    movel   %sp@(8),%sp@-         | storage
    movel   %sp@(8),%sp@-         | runtime
    pea     snd_load_post
    lea.l   %sp@(-12),%sp
    moveml  %a2-%a4,%sp@
    jmp     0x4005aed4

snd_load_post:
    movea.l %sp@(0),%a1           | runtime
    movea.l %sp@(4),%a0           | storage
    movew   %a0@(76),%d1
    movew   %d1,%a1@(66)
    movel   %d0,%sp@              | as in snd_save_post: d0 survives
    mvsw    %a0@(78),%d0
    movel   #32512,%d1
    subl    %d0,%d1
    movew   %d1,%a1@(68)
    movew   %a0@(80),%d1
    movew   %d1,%a1@(70)
    moveq   #0,%d0                | our destinations, if saved (snd_save_post)
    moveb   %a0@(82),%d0
    bsr     dst_ours
    tstl    %d0
    beqs    lp_d2
    lsll    #8,%d0
    movew   %d0,%a1@(28)          | as the loader writes it: index << 8
lp_d2:
    moveq   #0,%d0
    moveb   %a0@(83),%d0
    bsr     dst_ours
    tstl    %d0
    beqs    lp_done
    movel   %d0,%a1@(0x58)
lp_done:
    movel   %a0@(84),%d1          | packed state; zero in older records, which
    movel   %d1,%a1@(72)          | then fall back to the name token
    movel   %sp@,%d0
    addql   #8,%sp
    rts

| ---- attack ramp, applied where every machine passes ---------------------
| 0x400a967a is the amp envelope stage: it MACs an envelope over 32 output
| samples, and all six machines call it. Wrapping its six CALL SITES rather
| than the function itself, because its first two instructions are 8 bytes and
| a 6-byte jmp would split the second one - and from inside it there is no
| clean way to get control back after the envelope has been applied.
| Applying the ramp here also puts it after decimation and after the stock
| envelope, which is where an attack belongs.
|   args: sp@(4) = outBuf, sp@(8) = voice
amp_hook:
    tstl    sle_run               | the slice editor tapping: its track skips
    beqs    ah_env                | this envelope too (Amp Decay itself is
    movel   sle_trk,%d0           | 0x400a9252's, held in sampler_render)
    lea.l   voice_ptr,%a0
    movel   %a0@(0,%d0:l:4),%d0
    cmpl    %sp@(8),%d0
    beqs    ah_noenv
ah_env:
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    jsr     0x400a967a
    addql   #8,%sp
ah_noenv:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d5/%a2-%a3,%sp@
    movea.l %sp@(28),%a2          | outBuf
    movel   %sp@(32),%d2          | voice
    lea.l   voice_ptr,%a3         | which track is this voice?
    moveq   #0,%d3
ah_find:
    cmpl    %a3@(0,%d3:l:4),%d2
    beqs    ah_found
    addql   #1,%d3
    cmpil   #MAX_TRK,%d3
    bcss    ah_find
    braw    ah_out                | a voice we have never seen: leave it alone
ah_found:
    lea.l   atk_step,%a3
    movel   %a3@(0,%d3:l:4),%d4
    beqs    ah_flt                | attack 0: full level from the first sample
    lea.l   atk_gain,%a3
    movel   %a3@(0,%d3:l:4),%d5
    cmpil   #16777216,%d5
    bccs    ah_flt                | already fully open
    moveq   #31,%d2               | 32 samples, as the stage itself writes
ah_loop:
    movel   %a2@,%d0
    asrl    #8,%d0
    asrl    #8,%d0                | >>16: the product then fits in 32 bits
    movel   %d5,%d1
    lsrl    #8,%d1                | Q24 gain -> Q16
    mulsl   %d1,%d0
    movel   %d0,%a2@+
    addl    %d4,%d5
    cmpil   #16777216,%d5
    bcss    ah_next
    movel   #16777216,%d5
ah_next:
    subql   #1,%d2
    bpls    ah_loop
    lea.l   atk_gain,%a3
    movel   %d5,%a3@(0,%d3:l:4)
ah_flt:
    tstl    sx_inside             | a stereo track's side: gain only - and
    beqs    ah_mid                | kept, dry, for rs_trk to capture while
    tstl    rs_state              | this track is being recorded
    beqw    ah_pg
    cmpl    rs_src,%d3
    bnew    ah_pg
    movea.l %sp@(28),%a0
    lea.l   sx_cap,%a1
    moveq   #31,%d0
ah_cp:
    movel   %a0@+,%a1@+
    subql   #1,%d0
    bpls    ah_cp
    braw    ah_pg
ah_mid:
    movel   %d3,%sp@-             | then Filter/Res, stock machines only
    movel   %sp@(32),%sp@-        | outBuf again: the attack loop moved a2
    bsr     gflt_run
    addql   #8,%sp
    movel   %d3,%sp@-             | resampling: this track, dry
    movel   %sp@(32),%sp@-
    bsr     rs_trk
    addql   #8,%sp
ah_pg:
    lea.l   trk_mach,%a0          | Sampler tracks only: a track switched away
    moveq   #6,%d0                | keeps its track_slot, and a Kick must not
    cmpl    %a0@(0,%d3:l:4),%d0   | take on a take's gain (up to 16x)
    bnew    ah_ng
    lea.l   track_slot,%a0        | a take plays with its own gain - in RAM,
    movel   %a0@(0,%d3:l:4),%d0   | or saved and loaded back (the gain rides
    bmis    ah_ng                 | in the file's header, see rs_save_do)
    lea.l   slot_pgain,%a0
    movel   %a0@(0,%d0:l:4),%d4
    beqs    ah_ng
    cmpil   #4096,%d4             | unity: nothing to do
    beqs    ah_ng
    movea.l %sp@(28),%a2
    moveq   #31,%d2
ah_g:
    movel   %a2@,%d0              | y = (x >> 17) x gain (Q12), then << 5
    asrl    #8,%d0
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %d4,%d0
    cmpil   #0x03ffffff,%d0       | saturate the << 5
    bles    ah_g1
    movel   #0x03ffffff,%d0
ah_g1:
    cmpil   #-0x03ffffff,%d0
    bges    ah_g2
    movel   #-0x03ffffff,%d0
ah_g2:
    asll    #5,%d0
    movel   %d0,%a2@+
    subql   #1,%d2
    bpls    ah_g
ah_ng:
    | ---- the track's gain: MUT fades it out from the handover's block on,
    | and a take that has just landed fades in from 0 (sp_pgo) - 64 samples
    | each way, so the two crossfade instead of cutting. gv_gain is Q15. The
    | side of a stereo track (sx_inside) follows the same ramp without
    | advancing it; the mid, which comes after, keeps it.
    lea.l   gv_gain,%a0
    movel   %a0@(0,%d3:l:4),%d4
    movel   #32768,%d5            | target: open...
    movel   rs_silence,%d0
    orl     mute_sil,%d0
    btst    %d3,%d0
    beqs    ah_gt
    moveq   #0,%d5                | ...or MUT's silence, or muted by hand
ah_gt:
    cmpl    %d5,%d4
    bnes    ah_ramp
    tstl    %d4                   | steady: open costs nothing, silence zeroes
    bnes    ah_out
    movea.l %sp@(28),%a2
    moveq   #31,%d0
ah_z:
    clrl    %a2@+
    subql   #1,%d0
    bpls    ah_z
    bras    ah_out
ah_ramp:
    movea.l %sp@(28),%a2
    moveq   #31,%d2
ah_rl:
    cmpl    %d5,%d4               | step 512 towards the target
    beqs    ah_rs
    bgts    ah_rd
    addil   #512,%d4
    bras    ah_rs
ah_rd:
    subil   #512,%d4
ah_rs:
    movel   %a2@,%d0
    asrl    #8,%d0
    asrl    #7,%d0
    mulsl   %d4,%d0
    movel   %d0,%a2@+
    subql   #1,%d2
    bpls    ah_rl
    tstl    sx_inside
    bnes    ah_out
    lea.l   gv_gain,%a0
    movel   %d4,%a0@(0,%d3:l:4)
ah_out:
    moveml  %sp@,%d2-%d5/%a2-%a3
    lea.l   %sp@(24),%sp
    rts

| ======================= Transfer identity: CYC / SMP ======================
| Elektron Transfer decides what a device can do from its identity reply
| (message 0x01): a product number, the list of message types it answers, and
| a name. The two firmwares' dispatch tables (the factory switch at 0x4009247c)
| map every type to the same handler - the sample file-system commands
| 0x10-0x12, 0x20-0x23, 0x30/0x32/0x36 and 0x40-0x42/0x46 included - and differ
| only in what they ADVERTISE. So SMP answers as a Model:Samples does:
|   product 25 (not 27), its 35-entry list (from the Samples image at
|   0x4010da48), and "Model Samples".
| id_mode is set from the Transfer row in the device config menu and starts at
| CYC on every boot. Takes effect the next time Transfer asks - reconnect it.
|
| id_hook replaces 0x40084b8e..0x40084bdc of the reply builder (from
| `pea 0x22` to the list copy): the same instructions with the count and the
| list chosen by id_mode, and the name copied into id_namebuf, which the
| `pea "Model Cycles"` at 0x40084be0 now points at. a4/a5/d6/d7 are loaded by
| this very block, so they are free as scratch until then.
id_hook:
    movea.l %a0,%a5               | 0x400845de, the allocator (lea'd above)
    lea.l   id_n_cyc,%a4
    moveq   #0x22,%d6
    tstl    id_mode
    beqs    ih_n
    lea.l   id_n_smp,%a4
    moveq   #0x24,%d6
ih_n:
    lea.l   id_namebuf,%a1
ih_c:
    moveb   %a4@+,%d7
    moveb   %d7,%a1@+
    bnes    ih_c
    movel   %d6,%sp@-             | as `pea 0x22`: the list's length
    movel   %a5,%fp@(-96)
    clrl    %fp@(-36)
    clrl    %fp@(-32)
    clrl    %fp@(-28)
    jsr     %a5@
    lea.l   0x400e9c0a,%a4
    movel   %fp,%d6
    addil   #-44,%d6
    movel   %fp,%d7
    addil   #-68,%d7
    lea.l   0x400f980c,%a5
    movel   %d0,%sp@-
    movea.l %d0,%a1
    tstl    id_mode
    bnes    ih_smp
    pea     0x40112d62            | Cycles' own list
    lea.l   %a1@(34),%a1
    pea     0x40112d40
    bras    ih_cp
ih_smp:
    pea     id_smp_list+36
    lea.l   %a1@(36),%a1
    pea     id_smp_list
ih_cp:
    movel   %a1,%fp@(-28)
    movel   %d0,%fp@(-36)
    jsr     %a4@
    jmp     0x40084bde

| replaces `moveq #27,%d1 ; lea %sp@(40),%sp` at 0x40084c14: the product
id_hook2:
    moveq   #27,%d1
    tstl    id_mode
    beqs    ih2
    moveq   #25,%d1
ih2:
    lea.l   %sp@(40),%sp
    jmp     0x40084c1a

| ============== Retrig: beat-repeat on the tracks' output ====================
| Track + Retrig opens a full-screen page (the machine-page page, kind MM_RTG).
| While it is up the track pads choose the tracks it acts on (all, to start)
| and trig keys 1..16 repeat them: step 1 the shortest slice, step 16 a bar.
| Momentary (held; the newest held step wins, and letting it go falls back to
| the one still held) or Latch (a press starts or switches, the same step
| again stops). The options are a list: DATA moves between Mode and FX
| returns (delay and reverb repeated too), its press edits the row (turn to
| change, press again to leave). Track, Retrig or Return closes it.
|
| The audio: every block, after the voices and before the mixer (sx_gain),
| each track's channel - and the side of a stereo Sampler track - goes into a
| 2.7 s history (RTG_N samples, 16-bit), and at the mixer's L and R passes
| (sx_mix) the delay and reverb returns too. A repeat is grid-locked: the
| audio clock 0x8000184c counts 2 x tempo a block with tempo in 1/120 BPM, so
| a quarter note is 21,600,000 of its units at any tempo; the grid starts at
| step 1's time (0x40a78628, taken when the step counter 0x40a78840 turns to
| 1) and a step's slice runs from the last grid line of its length before
| the press. Its first pass is still being heard; after that it repeats,
| each cycle faded in and out over up to RTG_R samples, and live and repeat
| cross over in 64 samples - on a press, a release, a pad, or before one
| repeat gives way to another. The slice is kept from being overwritten
| while it repeats. A slice longer than the history (a bar below ~88 BPM)
| is halved until it fits, keeping the grid.
RTG_N      = 131072
RTG_MASK   = RTG_N-1
RTG_NS     = 16                   | streams: 6 tracks, 6 sides, 4 FX returns
RTG_R      = 32                   | the per-cycle fade, samples at most
RTG_REDRAW = 150                  | blocks: the page ten times a second
RTG_STEP   = 1024                 | wet ramp: 64 samples end to end, Q16
RTG_QN     = 21600000             | a quarter note on the audio clock

| rtg_open: from Track + Retrig. The histories start silent; every track on.
rtg_open:
    tstl    mm_obj
    bnew    rgo_out               | a page is up already
    clrl    rtg_on
    movea.l #RTG_BASE,%a0         | silence the histories (4 MiB)
    movel   #RTG_NS*RTG_N/8-1,%d0
    moveq   #0,%d1
rgo_z:
    movel   %d1,%a0@+
    movel   %d1,%a0@+
    movel   %d1,%a0@+
    movel   %d1,%a0@+
    subql   #1,%d0
    bpls    rgo_z
    lea.l   rtg_held,%a0
    moveq   #15,%d0
rgo_h:
    clrl    %a0@+
    subql   #1,%d0
    bpls    rgo_h
    moveq   #-1,%d0               | the pads' tracks are kept, as the master
    movel   %d0,rtg_lstep         | FX are (all six from power-on)
    clrl    rtg_row
    clrl    rtg_edit
    clrl    rtg_pat
    movel   CUR_PAT,%d0
    movel   %d0,rtg_pat0
    clrl    mfx_mt                | the master FX carry on as they were: they
                                  | outlive the page (Return turns them off)
    moveq   #MM_SYS+1,%d0         | MM_RTG
    jsr     mm_open
    tstl    mm_opened
    beqs    rgo_out
    bsr     rtg_topnow            | the page, as the view stack's top
    movel   %d0,rtg_topv
    movel   blk_clk,%d0
    movel   %d0,sys_last
    moveq   #1,%d0
    movel   %d0,rtg_on
rgo_out:
    rts

| pad_hook: the pad-event method 0x4001d180 (this, event), entered here. With
| the retrig page up a press (type +16 = 1) of pad id +20 - a track through
| the stock map 0x401001d0 - toggles that track; every pad event is taken
| (1, as the stock method answers). Otherwise the method runs as always.
pad_hook:
    tstl    rtg_on
    beqs    pdh_stock
    movea.l %sp@(8),%a0
    moveq   #1,%d0
    cmpl    %a0@(16),%d0
    bnes    pdh_used               | not a press
    movel   %a0@(20),%d0
    cmpil   #7,%d0
    bccs    pdh_used
    lea.l   0x401001d0,%a1
    movel   %a1@(0,%d0:l:4),%d0
    cmpil   #5,%d0
    bhis    pdh_used
    movel   rtg_sel,%d1
    btst    %d0,%d1
    bnes    pdh_off
    movel   %d0,%sp@-             | coming on: its history (and its side's)
    bsr     rtg_zero              | was not being recorded - silence it first
    movel   %sp@,%d0
    addql   #6,%d0
    bsr     rtg_zero
    movel   %sp@+,%d0
    movel   rtg_sel,%d1
pdh_off:
    bchg    %d0,%d1
    movel   %d1,rtg_sel
pdh_used:
    moveq   #1,%d0
    rts
pdh_stock:
    linkw   %fp,#-68              | the two instructions the jump replaced
    moveml  %d2-%d7/%a2-%a5,%sp@
    jmp     0x4001d188

| rtg_zero (d0 = stream): its history silenced, 256 KiB. UI side, before the
| stream is recorded again. Keeps d0, d2-d7.
rtg_zero:
    movel   %d0,%d1
    lsll    #8,%d1
    lsll    #8,%d1
    lsll    #2,%d1                | x RTG_N x 2 bytes
    addil   #RTG_BASE,%d1
    movea.l %d1,%a0
    movel   #RTG_N*2/16-1,%d1
    movel   %d2,%sp@-
    moveq   #0,%d2
rgz_l:
    movel   %d2,%a0@+
    movel   %d2,%a0@+
    movel   %d2,%a0@+
    movel   %d2,%a0@+
    subql   #1,%d1
    bpls    rgz_l
    movel   %sp@+,%d2
    rts

| rtg_topnow -> d0 = the view on top of the root view stack (its list node
| +8), or 0 - as gm_top finds it. Clobbers d0/d1/a0/a1.
rtg_topnow:
    jsr     0x400d0974
    movel   %d0,%sp@-
    jsr     0x400060d8            | the root view manager
    addql   #4,%sp
    movea.l %d0,%a1
    lea.l   %a1@(0x14),%a1        | the sentinel
    movea.l %a1@(4),%a0           | the last node: the top view
    cmpal   %a1,%a0
    beqs    rtn_no
    movel   %a0@(8),%d0
    rts
rtn_no:
    moveq   #0,%d0
    rts

| rtg_want -> d0 = the step the UI asks for (-1 none). Keeps d2-d7.
rtg_want:
    moveq   #-1,%d0
    tstl    rtg_on
    beqs    rgw_out
    tstl    rtg_latch
    beqs    rgw_mom
    movel   rtg_lstep,%d0
    rts
rgw_mom:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    moveq   #0,%d4                | the newest press so far
    moveq   #0,%d1
    lea.l   rtg_held,%a0
rgw_l:
    movel   %a0@(0,%d1:l:4),%d2
    cmpl    %d4,%d2
    blss    rgw_n
    movel   %d2,%d4
    movel   %d1,%d0
rgw_n:
    addql   #1,%d1
    cmpil   #16,%d1
    bcss    rgw_l
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
rgw_out:
    rts

| rtg_audio: from sx_gain, once a block, every track rendered, before the mix.
| Keeps every register.
rtg_audio:
    lea.l   %sp@(-60),%sp
    moveml  %d0-%d7/%a0-%a6,%sp@
    | step 1's time, each time the pattern comes round
    movel   0x40a78840,%d0
    movel   rtg_pstep,%d1
    movel   %d0,rtg_pstep
    cmpil   #1,%d0
    bnes    rga_nb
    cmpil   #1,%d1
    beqs    rga_nb
    moveq   #1,%d1
    cmpl    0x40a7883c,%d1
    bnes    rga_nb
    movel   0x40a78628,%d0
    movel   %d0,rtg_bar
rga_nb:
    | any stream still audibly repeating?
    moveq   #0,%d7
    lea.l   rtg_wet,%a0
    moveq   #RTG_NS-1,%d0
rga_w:
    orl     %a0@+,%d7
    subql   #1,%d0
    bpls    rga_w
    lea.l   mfx_wet,%a0           | ...or a master FX still fading out
    moveq   #11,%d0
rga_wm:
    orl     %a0@+,%d7
    subql   #1,%d0
    bpls    rga_wm
    tstl    rtg_on
    bnes    rga_on
    tstl    %d7
    bnew    rga_on
    moveq   #-1,%d0               | page closed and all faded: nothing to do
    movel   %d0,rtg_act
    clrl    rtg_lv
    braw    rga_out
rga_on:
    bsr     rtg_want
    movel   %d0,%d3               | the step asked for
    movel   %d3,rtg_des
    tstl    rtg_lv
    beqs    rga_inst
    cmpl    rtg_act,%d3
    beqw    rga_blk                | the same repeat
    tstl    %d7
    bnew    rga_blk                | fade the old one out first
rga_inst:
    clrl    rtg_lv                | install the one asked for
    movel   %d3,rtg_act
    tstl    %d3
    bmiw    rga_blk
    movel   0x40149310,%d5        | tempo
    beqw    rga_blk
    lea.l   rtg_divs,%a0
    movel   %a0@(0,%d3:l:4),%d4   | D, clock units
rga_fit:
    movel   %d4,%d0
    lsll    #4,%d0
    divul   %d5,%d0               | L = D x 16 / tempo, samples
    cmpil   #RTG_N-4096,%d0
    blss    rga_fits
    lsrl    #1,%d4
    bras    rga_fit
rga_fits:
    tstl    %d0
    beqw    rga_blk
    movel   %d0,rtg_len
    movel   0x8000184c,%d0        | how far past its last grid line
    subl    rtg_bar,%d0
    movel   %d0,%d1
    divul   %d4,%d1
    mulul   %d4,%d1
    subl    %d1,%d0
    lsll    #4,%d0
    divul   %d5,%d0               | in samples
    movel   blk_clk,%d1
    lsll    #5,%d1
    subl    %d0,%d1
    movel   %d1,rtg_lst
    moveq   #1,%d0
    movel   %d0,rtg_lv
rga_blk:
    | this block's positions in the slice, and the per-cycle fade
    tstl    rtg_lv
    beqw    rga_str
    movel   blk_clk,%d0
    lsll    #5,%d0
    subl    rtg_lst,%d0           | elapsed since the slice began
    movel   %d0,rtg_e0
    movel   rtg_len,%d4
    movel   %d0,%d1
    divul   %d4,%d1
    mulul   %d4,%d1
    subl    %d1,%d0               | the position in the slice
    movel   %d4,%d5
    lsrl    #2,%d5
    moveq   #RTG_R,%d1
    cmpl    %d1,%d5
    blss    rga_r
    movel   %d1,%d5
rga_r:
    tstl    %d5
    bnes    rga_r1
    moveq   #1,%d5
rga_r1:
    movel   #65536,%d6
    divul   %d5,%d6               | 1/R, Q16
    lea.l   rtg_pos,%a0
    lea.l   rtg_env,%a1
    moveq   #31,%d7
rga_pl:
    movel   %d0,%a0@+
    movel   %d0,%d1
    mulul   %d6,%d1               | fade in
    movel   %d4,%d2
    subl    %d0,%d2
    mulul   %d6,%d2               | fade out
    cmpl    %d1,%d2
    bccs    rga_pm
    movel   %d2,%d1
rga_pm:
    cmpil   #65536,%d1
    blss    rga_pe
    movel   #65536,%d1
rga_pe:
    movel   %d1,%a1@+
    addql   #1,%d0
    cmpl    %d4,%d0
    bcss    rga_pn
    moveq   #0,%d0
rga_pn:
    subql   #1,%d7
    bpls    rga_pl
rga_str:
    bsr     mfx_block             | the master FX's shared Tape and Gate
    | the six tracks and the sides of the stereo ones. A track the pads have
    | turned off is not even recorded - it cannot be repeated, and its
    | history costs uncached writes every block - once its repeat has faded;
    | pad_hook clears the history when it comes back on.
    moveq   #0,%d2
rga_tl:
    movel   rtg_sel,%d0
    btst    %d2,%d0
    bnes    rga_do
    lea.l   rtg_wet,%a0
    tstl    %a0@(0,%d2:l:4)
    bnes    rga_do                | still fading out
    tstl    %a0@(24,%d2:l:4)      | ...or its side
    bnes    rga_do
    lea.l   mfx_wet,%a0           | ...or its master FX, or its side's
    tstl    %a0@(0,%d2:l:4)
    bnes    rga_do
    tstl    %a0@(24,%d2:l:4)
    beqw    rga_ns
rga_do:
    moveq   #0,%d3                | the target: repeating, and this track on
    tstl    rtg_lv
    beqs    rga_tt
    movel   rtg_des,%d0
    cmpl    rtg_act,%d0
    bnes    rga_tt
    movel   rtg_sel,%d0
    btst    %d2,%d0
    beqs    rga_tt
    moveq   #1,%d3
rga_tt:
    movel   %d2,%d0
    lsll    #7,%d0
    addil   #0x80001858,%d0
    movea.l %d0,%a2
    movel   %d2,%d0
    bsr     rtg_stream
    movel   %d2,%d0               | then the master FX, after the repeats
    bsr     mfx_stream
    lea.l   sx_on,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    rga_ns
    movel   %d2,%d0
    lsll    #7,%d0
    addil   #sx_side,%d0
    movea.l %d0,%a2
    movel   %d2,%d0
    addql   #6,%d0
    bsr     rtg_stream
    movel   %d2,%d0
    addql   #6,%d0
    bsr     mfx_stream
rga_ns:
    addql   #1,%d2
    cmpil   #6,%d2
    bcsw    rga_tl
rga_out:
    moveml  %sp@,%d0-%d7/%a0-%a6
    lea.l   %sp@(60),%sp
    rts

| rtg_fxpass(d0 = 0 the L pass, 1 the R): the delay and reverb returns (channels
| 6 and 7) as that pass hears them. Keeps every register.
rtg_fxpass:
    lea.l   %sp@(-60),%sp
    moveml  %d0-%d7/%a0-%a6,%sp@
    movel   %d0,%d4
    tstl    rtg_on
    beqs    rgf_idle
    tstl    rtg_fx                | FX RETURNS off: not recorded either (the
    bnes    rgf_go                | history is cleared when it comes on)
rgf_idle:
    lea.l   rtg_wet+48,%a0        | only while a return still fades
    movel   %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@,%d0
    beqs    rgf_out
rgf_go:
    moveq   #0,%d3
    tstl    rtg_lv
    beqs    rgf_t
    movel   rtg_des,%d0
    cmpl    rtg_act,%d0
    bnes    rgf_t
    tstl    rtg_fx
    beqs    rgf_t
    moveq   #1,%d3
rgf_t:
    moveq   #12,%d2               | streams 12/13 the L pass, 14/15 the R
    addl    %d4,%d2
    addl    %d4,%d2
    movea.l #0x80001858+6*128,%a2
    movel   %d2,%d0
    bsr     rtg_stream
    movea.l #0x80001858+7*128,%a2
    movel   %d2,%d0
    addql   #1,%d0
    bsr     rtg_stream
rgf_out:
    moveml  %sp@,%d0-%d7/%a0-%a6
    lea.l   %sp@(60),%sp
    rts

| rtg_stream(a2 = 32 samples of a channel, d0 = stream, d3 = target 0/1):
| record them into the stream's history, and give back live, or the repeat
| crossed into it by the stream's wet. Keeps d2-d7, a2.
rtg_stream:
    lea.l   %sp@(-36),%sp
    moveml  %d2-%d7/%a2-%a4,%sp@
    movel   %d0,%d1
    moveq   #18,%d4               | RTG_N x 2 bytes a stream
    lsll    %d4,%d1
    addil   #RTG_BASE,%d1
    movea.l %d1,%a3               | the history
    lea.l   rtg_wet,%a0
    lea.l   %a0@(0,%d0:l:4),%a4
    movel   %a4@,%d5              | wet, Q16
    movel   blk_clk,%d6
    lsll    #5,%d6                | this sample's number
    moveq   #31,%d7
    tstl    rtg_lv
    beqw    rgs_plain
    lea.l   rtg_pos,%a0
    lea.l   rtg_env,%a1
    movel   rtg_e0,%d4            | elapsed in the slice
rgs_l:
    movel   %a2@,%d0              | live
    cmpl    rtg_len,%d4           | still its first pass: record
    bcss    rgs_w
    movel   %d4,%d1               | after it: not over the slice
    andil   #RTG_MASK,%d1
    cmpl    rtg_len,%d1
    bcss    rgs_nw
rgs_w:
    movel   %d0,%d1
    bsr     rtg_q16
    movel   %d6,%d2
    andil   #RTG_MASK,%d2
    addl    %d2,%d2
    movew   %d1,%a3@(0,%d2:l)
rgs_nw:
    movel   rtg_lst,%d1           | the repeat
    addl    %a0@+,%d1
    andil   #RTG_MASK,%d1
    addl    %d1,%d1
    mvsw    %a3@(0,%d1:l),%d1
    movel   %a1@+,%d2
    mulsl   %d2,%d1
    asrl    #1,%d1                | x << 15 at the fade
    tstl    %d3                   | the wet, toward the target
    beqs    rgs_dn
    addil   #RTG_STEP,%d5
    cmpil   #65536,%d5
    blss    rgs_wk
    movel   #65536,%d5
    bras    rgs_wk
rgs_dn:
    subil   #RTG_STEP,%d5
    bpls    rgs_wk
    moveq   #0,%d5
rgs_wk:
    asrl    #8,%d1                | live + (repeat - live) x wet
    movel   %d0,%d2
    asrl    #8,%d2
    subl    %d2,%d1
    asrl    #1,%d1                | the difference >> 9: x 128 fits
    movel   %d5,%d2
    lsrl    #8,%d2
    lsrl    #1,%d2                | wet, 0..128
    mulsl   %d2,%d1
    lsll    #2,%d1                | back to scale: << 9, / 128. samplerHK had
    addl    %d0,%d1               | >> 7 here - (repeat - live) / 256, unheard
    movel   %d1,%a2@+
    addql   #1,%d4
    addql   #1,%d6
    subql   #1,%d7
    bplw    rgs_l
    bras    rgs_end
rgs_plain:                        | no slice: record, and play live
    movel   %a2@+,%d1
    bsr     rtg_q16
    movel   %d6,%d2
    andil   #RTG_MASK,%d2
    addl    %d2,%d2
    movew   %d1,%a3@(0,%d2:l)
    addql   #1,%d6
    subql   #1,%d7
    bpls    rgs_plain
    moveq   #0,%d5
rgs_end:
    movel   %d5,%a4@
    moveml  %sp@,%d2-%d7/%a2-%a4
    lea.l   %sp@(36),%sp
    rts
| d1 (a channel sample, 16-bit << 15 scale) -> 16 bits, clamped. Keeps the rest.
rtg_q16:
    asrl    #8,%d1
    asrl    #7,%d1
    cmpil   #32767,%d1
    bles    rgq_h
    movel   #32767,%d1
rgq_h:
    cmpil   #-32767,%d1
    bges    rgq_o
    movel   #-32767,%d1
rgq_o:
    rts

| ================= master FX on the retrig page =================
| While the retrig page is up its knobs are effects on the tracks the pads
| have lit - each track's channel (and a stereo Sampler track's side), after
| the retrig repeats and before the mixer and the delay/reverb sends, so the
| sends hear them. Knob indices (event +12): 2 Drive, 3 Crush, 4 Rate, 6
| Filter, 7 Resonance, 10 Gate, 11 Tape stop (samplerID: Filter and
| Resonance). The effects outlive the page: closed (Track, Retrig, or Pattern
| for a pattern change) they carry on, and opening it again shows them as
| they are; Return turns them all off, each fading (mfx_wet, 64 samples).
| Filter: a 2-pole state-variable filter in its topology-preserving form
| (Zavalishin), stable at any cutoff and while it moves; LP below the centre
| of the knob (20 kHz -> 30 Hz), HP above it (20 Hz -> 10 kHz), off at 0.
| Resonance takes k = 2 (Q 0.5) down to 0.1 (Q 10). Per sample it runs on
| the EMAC in fractional mode, the signal at a quarter scale so resonance
| has headroom and saturates rather than wraps (modelled: stable and in
| range from 30 Hz to 20 kHz at full resonance, full-scale squares and
| noise). The coefficients come from the UI side when a knob moves - from
| g = tan(pi fc / 48000) (mfx_glp/mfx_ghp, Q24) with exact 64-bit integer
| arithmetic - into whichever of two sets the audio is not reading, and
| the pointer then flips.
MFX_SHOW = 1500                   | blocks: a knob's value shows for a second
MFX_STEP = 1024                   | wet ramp: 64 samples end to end, Q16

| mfx_knob (d3 = knob index, d2 = the encoder event) -> d0 = 1 if it did
| something (redraw). Keeps d2-d7.
mfx_knob:
    pea     4                     | clicks: 1 each slowly, 4 turned fast
    pea     1
    movel   %d2,%sp@-
    jsr     0x4006f73a
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    mfk_no
    cmpil   #6,%d3
    beqs    mfk_filt
    cmpil   #7,%d3
    beqw    mfk_res
    cmpil   #2,%d3
    beqw    mfk_drv
    cmpil   #3,%d3
    beqw    mfk_crs
    cmpil   #4,%d3
    beqw    mfk_rt
    cmpil   #10,%d3
    beqw    mfk_gate
    cmpil   #11,%d3
    beqw    mfk_tape
    cmpil   #5,%d3
    beqw    mfk_pump
    cmpil   #8,%d3
    beqw    mfk_ring
    cmpil   #9,%d3
    beqw    mfk_noise
    cmpil   #12,%d3
    beqw    mfk_vinyl
    cmpil   #13,%d3
    beqw    mfk_flg
mfk_no:
    moveq   #0,%d0
    rts
mfk_filt:
    addl    mfx_filt,%d0
    cmpil   #127,%d0
    bles    mfk_f1
    moveq   #127,%d0
mfk_f1:
    cmpil   #-127,%d0
    bges    mfk_f2
    moveq   #-127,%d0
mfk_f2:
    movel   %d0,mfx_filt
    bsr     mfx_coef
    lea.l   mfx_s_foff,%a0        | "FILTER OFF", "FILTER LP n", "FILTER HP n"
    movel   mfx_filt,%d0
    beqw    mfk_say0
    lea.l   mfx_s_flp,%a0
    tstl    %d0
    bpls    mfk_hp
    negl    %d0
    bras    mfk_say
mfk_hp:
    lea.l   mfx_s_fhp,%a0
    bras    mfk_say
mfk_res:
    addl    mfx_res,%d0
    bpls    mfk_r1
    moveq   #0,%d0
mfk_r1:
    cmpil   #127,%d0
    bles    mfk_r2
    moveq   #127,%d0
mfk_r2:
    movel   %d0,mfx_res
    bsr     mfx_coef
    lea.l   mfx_s_res,%a0
    movel   mfx_res,%d0
mfk_say:
    bsr     mfx_say
    bsr     mfx_act_upd
    moveq   #1,%d0
    rts
| d0 += the knob's current value, clamped to 0..127 -> d0
mfk_clamp:
    tstl    %d0
    bpls    mfk_c1
    moveq   #0,%d0
mfk_c1:
    cmpil   #127,%d0
    bles    mfk_c2
    moveq   #127,%d0
mfk_c2:
    rts
mfk_drv:                          | Drive: gain and its level compensation
    addl    mfx_drv,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_drv
    lea.l   mfx_dg_t,%a0
    mvzw    %a0@(0,%d0:l:2),%d1
    movel   %d1,mfx_dg
    lea.l   mfx_dp_t,%a0
    mvzw    %a0@(0,%d0:l:2),%d1
    movel   %d1,mfx_dp
    lea.l   mfx_s_drv,%a0
    braw    mfk_say
mfk_crs:                          | Crush: bits = 16 - 15 v / 127, as a mask
    addl    mfx_crs,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_crs
    moveq   #-1,%d1
    tstl    %d0
    beqs    mfk_cm
    moveq   #15,%d1
    mulul   %d1,%d0
    addil   #63,%d0
    moveq   #127,%d1
    divul   %d1,%d0               | bits removed from 16
    addil   #16,%d0               | ...and from 32: 16 + that
    moveq   #-1,%d1
    lsll    %d0,%d1
mfk_cm:
    movel   %d1,mfx_mask
    movel   mfx_crs,%d0           | shown as the bits kept
    moveq   #15,%d1
    mulul   %d1,%d0
    addil   #63,%d0
    moveq   #127,%d1
    divul   %d1,%d0
    moveq   #16,%d1
    subl    %d0,%d1
    movel   %d1,%d0
    lea.l   mfx_s_crs,%a0
    braw    mfk_say
mfk_rt:                           | Rate: the hold's step, shown in Hz
    addl    mfx_rt,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_rt
    lea.l   mfx_ri_t,%a0
    movel   %a0@(0,%d0:l:4),%d0
    movel   %d0,mfx_rinc
    movel   #48000,%d1
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #8,%d0
    lea.l   mfx_s_rt,%a0
    braw    mfk_say
mfk_gate:                         | Gate: one division per click
    moveq   #1,%d1
    tstl    %d0
    bpls    mfk_g1
    moveq   #-1,%d1
mfk_g1:
    addl    mfx_gate,%d1
    bpls    mfk_g2
    moveq   #0,%d1
mfk_g2:
    cmpil   #6,%d1
    bles    mfk_g3
    moveq   #6,%d1
mfk_g3:
    movel   %d1,mfx_gate
    lea.l   mfx_gnames,%a0
    movea.l %a0@(0,%d1:l:4),%a0
    moveq   #-1,%d0
    braw    mfk_say
mfk_tape:                         | Tape stop: the brake, 0..127
    addl    mfx_tape,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_tape
    lea.l   mfx_s_tape,%a0
    braw    mfk_say
| mfx_reset: Return on the retrig page - every effect off (they fade out,
| as when turned down) and a latched repeat stopped. UI side. Keeps d2-d7.
mfx_reset:
    clrl    mfx_filt
    bsr     mfx_coef              | the filter off
    clrl    mfx_res
    clrl    mfx_drv
    clrl    mfx_crs
    moveq   #-1,%d0
    movel   %d0,mfx_mask
    clrl    mfx_rt
    movel   #65536,%d0
    movel   %d0,mfx_rinc
    clrl    mfx_gate
    clrl    mfx_tape
    clrl    mfx_pump
    clrl    mfx_ring
    clrl    mfx_noise
    clrl    mfx_vinyl
    clrl    mfx_flg
    clrl    mfx_fmix
    bsr     mfx_act_upd
    moveq   #-1,%d0
    movel   %d0,rtg_lstep
    lea.l   mfx_s_rst,%a0
    moveq   #-1,%d0
    braw    mfx_say
mfk_pump:                         | Pump: depth 0..127
    addl    mfx_pump,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_pump
    lea.l   mfx_s_pump,%a0
    braw    mfk_say
mfk_ring:                         | Ring mod: the sine's frequency, in Hz
    addl    mfx_ring,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_ring
    beqs    mfk_r0
    lea.l   mfx_rinc_t,%a0
    movel   %a0@(0,%d0:l:4),%d0
    movel   %d0,mfx_rinc2
    movel   #48000,%d1            | Hz = step x 48000 / 2^32: the high word
    bsr     mul64u
    lea.l   mfx_s_ring,%a0
    braw    mfk_say
mfk_r0:
    lea.l   mfx_s_roff,%a0
    moveq   #-1,%d0
    braw    mfk_say
mfk_noise:                        | Noise riser: level (squared) and the
    addl    mfx_noise,%d0         | high-pass climbing with it
    bsr     mfk_clamp
    movel   %d0,mfx_noise
    lea.l   mfx_nhp_t,%a0
    mvzw    %a0@(0,%d0:l:2),%d1
    movel   %d1,mfx_na
    movel   %d0,%d1
    mulul   %d0,%d1
    movel   #32767,%d0
    mulul   %d0,%d1
    movel   #16129,%d0
    divul   %d0,%d1
    movel   %d1,mfx_nlev
    movel   mfx_noise,%d0
    lea.l   mfx_s_noise,%a0
    braw    mfk_say
mfk_vinyl:                        | Vinyl: Wear 0..127
    addl    mfx_vinyl,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_vinyl
    lea.l   mfx_s_vinyl,%a0
    braw    mfk_say
mfk_flg:                          | Flanger: depth 0..127 -> blend 0..64
    addl    mfx_flg,%d0
    bsr     mfk_clamp
    movel   %d0,mfx_flg
    movel   %d0,%d1
    lsll    #6,%d1
    moveq   #127,%d0
    divul   %d0,%d1
    movel   %d1,mfx_fmix
    movel   mfx_flg,%d0
    lea.l   mfx_s_flg,%a0
    braw    mfk_say
| mfx_act: any effect engaged - the streams fade in toward it
mfx_act_upd:
    movel   mfx_on,%d0
    orl     mfx_pump,%d0
    orl     mfx_ring,%d0
    orl     mfx_flg,%d0
    orl     mfx_drv,%d0
    orl     mfx_crs,%d0
    orl     mfx_rt,%d0
    orl     mfx_gate,%d0
    orl     mfx_tape,%d0
    movel   %d0,mfx_act
    rts

| mfx_block: once a block, before the streams, what they share: Tape stop's
| playhead - a lag behind live that grows by (1 - speed) a sample, the speed
| slewing toward the knob's (a full stop in ~0.45 s), the level following
| the speed - and the Gate's gain, open for the first half of each division
| on step 1's grid, ramping 64 samples at each edge. Into mfx_tt (per
| sample: position, fraction, the two weights) and mfx_gt, both by the
| stream loop's count (entry 31 is the first sample). Keeps d2-d7, a2-a6.
MFX_TSLEW = 3                     | speed, Q16, per sample
MFX_PK    = 0x10000000            | Pump: the key level that ducks fully
MFX_FMIN  = 15*256                | Flanger: the delay's least, Q8 (0.3 ms)
MFX_FSPAN = 273*256               | ...and its sweep (to ~6 ms)
MFX_TMAX  = (RTG_N-4096)*256      | the lag's limit, Q8: inside the history
mfx_block:
    lea.l   %sp@(-32),%sp
    moveml  %d2-%d7/%a2-%a3,%sp@
    | ---- Tape stop ----
    movel   mfx_tape,%d0
    orl     mfx_tact,%d0
    beqw    mfb_gate
    moveq   #1,%d0
    movel   %d0,mfx_tact
    movel   mfx_tape,%d0          | the target speed, Q16
    movel   #65536,%d7
    mulul   %d7,%d0
    moveq   #127,%d1
    divul   %d1,%d0
    subl    %d0,%d7
    movel   mfx_tspd,%d2          | speed
    movel   mfx_tlag,%d3          | lag, Q8
    movel   mfx_ttw,%d4           | tape vs live, Q16
    movel   blk_clk,%d5
    lsll    #5,%d5                | this block's first sample
    lea.l   mfx_tt+31*16,%a0
    moveq   #31,%d6
mfb_tl:
    cmpl    %d7,%d2               | the speed toward its target
    beqs    mfb_ts
    bgts    mfb_tdn
    addql   #MFX_TSLEW,%d2
    cmpl    %d7,%d2
    blss    mfb_ts
    movel   %d7,%d2
    bras    mfb_ts
mfb_tdn:
    subql   #MFX_TSLEW,%d2
    cmpl    %d7,%d2
    bges    mfb_ts
    movel   %d7,%d2
mfb_ts:
    movel   #65536,%d0            | the lag grows by 1 - speed
    subl    %d2,%d0
    lsrl    #8,%d0
    addl    %d0,%d3
    cmpil   #MFX_TMAX,%d3
    blss    mfb_tl2
    movel   #MFX_TMAX,%d3
    moveq   #0,%d2                | as far back as it goes: stopped
mfb_tl2:
    tstl    mfx_tape              | tape vs live toward the knob
    beqs    mfb_tw0
    addil   #1024,%d4
    cmpil   #65536,%d4
    blss    mfb_tw
    movel   #65536,%d4
    bras    mfb_tw
mfb_tw0:
    subil   #1024,%d4
    bpls    mfb_tw
    moveq   #0,%d4
mfb_tw:
    movel   %d5,%d0               | position: this sample less the lag
    movel   %d3,%d1
    lsrl    #8,%d1
    subl    %d1,%d0
    movel   %d0,%a0@
    movel   %d3,%d0
    andil   #255,%d0
    movel   %d0,%a0@(4)           | fraction, 0..255
    movel   %d4,%d0               | live's weight: 128 (1 - tw)
    lsrl    #8,%d0
    lsrl    #1,%d0
    movel   #128,%d1
    subl    %d0,%d1
    movel   %d1,%a0@(8)
    movel   %d2,%d1               | the tape's: tw x speed, 0..128
    lsrl    #8,%d1
    lsrl    #1,%d1
    mulul   %d1,%d0
    lsrl    #7,%d0
    movel   %d0,%a0@(12)
    lea.l   %a0@(-16),%a0
    addql   #1,%d5
    subql   #1,%d6
    bplw    mfb_tl
    movel   %d2,mfx_tspd
    movel   %d3,mfx_tlag
    movel   %d4,mfx_ttw
    tstl    mfx_tape              | back at 0 and faded to live: reset
    bnes    mfb_gate
    tstl    %d4
    bnes    mfb_gate
    clrl    mfx_tact
    clrl    mfx_tlag
    movel   #65536,%d0
    movel   %d0,mfx_tspd
mfb_gate:
    | ---- Gate ----
    movel   mfx_gate,%d0
    orl     mfx_gact,%d0
    beqw    mfb_pump              | (not the end: Pump, Ring and Noise follow)
    moveq   #1,%d0
    movel   %d0,mfx_gact
    movel   0x40149310,%d5        | tempo: clock units a sample = tempo / 16
    lsrl    #4,%d5
    moveq   #0,%d7                | D, the division; 0 = open
    movel   mfx_gate,%d0
    beqs    mfb_gd
    lea.l   mfx_gdiv,%a0
    movel   %a0@(0,%d0:l:4),%d7
mfb_gd:
    movel   0x8000184c,%d3        | where this block starts in the division
    subl    rtg_bar,%d3
    tstl    %d7
    beqs    mfb_g0
    movel   %d3,%d1
    divul   %d7,%d1
    mulul   %d7,%d1
    subl    %d1,%d3
mfb_g0:
    movel   mfx_gg,%d4            | the gain, Q16
    lea.l   mfx_gt+31*4,%a0
    moveq   #31,%d6
mfb_gl:
    movel   #-1024,%d1            | closed unless in the first half
    tstl    %d7
    beqs    mfb_gon
    movel   %d7,%d0
    lsrl    #1,%d0
    cmpl    %d0,%d3
    bccs    mfb_gs
mfb_gon:
    movel   #1024,%d1
mfb_gs:
    addl    %d1,%d4
    bpls    mfb_g1
    moveq   #0,%d4
mfb_g1:
    cmpil   #65536,%d4
    blss    mfb_g2
    movel   #65536,%d4
mfb_g2:
    movel   %d4,%a0@
    subql   #4,%a0
    addl    %d5,%d3               | on through the division
    tstl    %d7
    beqs    mfb_g3
    cmpl    %d7,%d3
    bcss    mfb_g3
    subl    %d7,%d3
mfb_g3:
    subql   #1,%d6
    bpls    mfb_gl
    movel   %d4,mfx_gg
    tstl    mfx_gate              | off and fully open again: done
    bnes    mfb_pump
    cmpil   #65536,%d4
    bnes    mfb_pump
    clrl    mfx_gact
mfb_pump:
    | ---- Pump: the lit tracks ducked by the tracks the pads have turned off
    | (their peak, instant attack, ~170 ms release), or with none turned off
    | a duck on every quarter note; the gain smoothed over ~1 ms ----
    movel   mfx_pump,%d0
    orl     mfx_pact,%d0
    beqw    mfb_ring
    moveq   #1,%d0
    movel   %d0,mfx_pact
    movel   mfx_pump,%d2          | depth, Q16
    movel   #65536,%d0
    mulul   %d0,%d2
    moveq   #127,%d0
    divul   %d0,%d2
    movel   mfx_penv,%d3          | the key's envelope
    movel   mfx_pg,%d4            | the smoothed gain, Q16
    movel   rtg_sel,%d5           | the key: the tracks turned off
    notl    %d5
    andil   #0x3f,%d5
    movel   0x40149310,%d0        | quarter notes: clock units a sample
    lsrl    #4,%d0
    movea.l %d0,%a3
    movel   0x8000184c,%d6        | ...and where this block starts in one
    subl    rtg_bar,%d6
    movel   %d6,%d1
    movel   #RTG_QN,%d0
    divul   %d0,%d1
    mulul   %d0,%d1
    subl    %d1,%d6
    movea.l #0x80001858,%a0       | the key tracks' channels, sample by sample
    lea.l   mfx_pt+31*4,%a2
    moveq   #31,%d7
mfb_pl:
    tstl    %d5
    beqs    mfb_pq
    bsr     mfb_keypk             | d0 = the key's peak this sample
    movel   %d3,%d1               | release, then the new peak if higher
    lsrl    #8,%d1
    lsrl    #5,%d1
    subl    %d1,%d3
    cmpl    %d0,%d3
    bccs    mfb_pd
    movel   %d0,%d3
    bras    mfb_pd
mfb_pq:
    movel   %d3,%d1               | quarter notes: full at each, then release
    lsrl    #8,%d1
    lsrl    #5,%d1
    subl    %d1,%d3
    addl    %a3,%d6
    cmpil   #RTG_QN,%d6
    bcss    mfb_pd
    subil   #RTG_QN,%d6
    movel   #MFX_PK,%d3
mfb_pd:
    movel   %d3,%d0               | duck = depth x min(env, K) / K
    cmpil   #MFX_PK,%d0
    blss    mfb_pe
    movel   #MFX_PK,%d0
mfb_pe:
    lsrl    #8,%d0
    lsrl    #4,%d0                | 0..65536
    movel   %d2,%d1
    lsrl    #1,%d1
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #7,%d0
    movel   #65536,%d1
    subl    %d0,%d1               | the gain
    subl    %d4,%d1
    asrl    #5,%d1
    addl    %d1,%d4               | smoothed
    movel   %d4,%a2@
    subql   #4,%a2
    addql   #4,%a0
    subql   #1,%d7
    bplw    mfb_pl
    movel   %d3,mfx_penv
    movel   %d4,mfx_pg
    tstl    mfx_pump              | off and back to unity: done
    bnes    mfb_ring
    cmpil   #65535,%d4
    blss    mfb_ring
    clrl    mfx_pact
    movel   #65536,%d0
    movel   %d0,mfx_pg
mfb_ring:
    | ---- Ring mod: the sine, interpolated, shared by every stream ----
    clrl    mfx_ract
    tstl    mfx_ring
    beqs    mfb_flg
    moveq   #1,%d0
    movel   %d0,mfx_ract
    movel   mfx_rph,%d2
    movel   mfx_rinc2,%d3
    lea.l   mfx_sin,%a3
    lea.l   mfx_rmt+31*4,%a2
    moveq   #31,%d7
mfb_rl:
    movel   %d2,%d0
    swap    %d0
    andil   #0xffff,%d0           | phase >> 16
    movel   %d0,%d1
    lsrl    #8,%d1                | the step
    andil   #255,%d0              | ...and between it and the next
    mvsw    %a3@(0,%d1:l:2),%d4
    mvsw    %a3@(2,%d1:l:2),%d5
    subl    %d4,%d5
    mulsl   %d0,%d5
    asrl    #8,%d5
    addl    %d4,%d5
    movel   %d5,%a2@
    subql   #4,%a2
    addl    %d3,%d2
    subql   #1,%d7
    bpls    mfb_rl
    movel   %d2,mfx_rph
mfb_flg:
    | ---- Flanger: a delay of 0.3 - 6 ms swept by a sine once a bar (tempo
    | x 3.1069 = the step, Q32), for each stream to read its own history at:
    | per sample the position (this sample less the delay) and the fraction ----
    clrl    mfx_fact
    tstl    mfx_flg
    beqw    mfb_out
    moveq   #1,%d0
    movel   %d0,mfx_fact
    movel   0x40149310,%d3        | once a bar: step = tempo x 2^32 / 1382400000
    movel   #31069,%d0
    mulul   %d0,%d3
    movel   #10000,%d0
    divul   %d0,%d3
    movel   mfx_fph,%d2
    movel   blk_clk,%d5
    lsll    #5,%d5
    lea.l   mfx_sin,%a3
    lea.l   mfx_ft+31*32,%a2
    moveq   #31,%d7
mfb_fl:
    movel   %d2,%d0               | the sine, as the ring mod reads it
    swap    %d0
    andil   #0xffff,%d0
    movel   %d0,%d1
    lsrl    #8,%d1
    andil   #255,%d0
    mvsw    %a3@(0,%d1:l:2),%d4
    mvsw    %a3@(2,%d1:l:2),%d6
    subl    %d4,%d6
    mulsl   %d0,%d6
    asrl    #8,%d6
    addl    %d4,%d6               | -32767..32767
    addil   #32768,%d6
    lsrl    #1,%d6                | 0..32767
    movel   #MFX_FSPAN,%d0
    mulul   %d0,%d6
    lsrl    #8,%d6
    lsrl    #7,%d6
    addil   #MFX_FMIN,%d6         | the delay, Q8 samples
    movel   %d5,%d0               | the position: this sample less the delay
    movel   %d6,%d1
    lsrl    #8,%d1
    subl    %d1,%d0
    movel   %d0,%d1
    andil   #RTG_MASK,%d0
    addl    %d0,%d0
    movel   %d0,%a2@              | ...as its byte in the history
    subql   #1,%d1
    andil   #RTG_MASK,%d1
    addl    %d1,%d1
    movel   %d1,%a2@(4)           | ...and the sample before's
    andil   #255,%d6
    movel   %d6,%a2@(8)           | fraction
    movel   mfx_fmix,%d0
    movel   %d0,%a2@(12)          | the blend, m
    movel   #128,%d1
    subl    %d0,%d1
    movel   %d1,%a2@(16)          | ...and 128 - m
    lea.l   %a2@(-32),%a2
    addql   #1,%d5
    addl    %d3,%d2
    subql   #1,%d7
    bplw    mfb_fl
    movel   %d2,mfx_fph
mfb_out:
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(32),%sp
    rts
| mfx_master - in place of `pea 4; pea 0x8000b990; jsr 0x400565c6` at
| 0x40056b38 (a `subql #8,%sp` keeps the `addql #8` after it balanced). The
| mixed stereo bus - 32 frames, L and R interleaved at 0x8000b990 - before
| 0x400565c6 takes it x4 (saturating) to the output's level: the Noise riser
| and Vinyl are added here, to both sides, so they sit on the whole mix and
| hear no track's level, mute, pan or sends (samplerIQ put them into one
| track, which went silent with it). Their tables are made here too, so they
| run whether or not anything else of the retrig engine does. Then the stock
| call. Keeps d2-d7 and a2-a6.
mfx_master:
    lea.l   %sp@(-28),%sp
    moveml  %d2-%d7/%a2,%sp@
    | ---- Noise riser: white noise through a climbing high-pass, for the
    | mix, after the tracks are summed ----
    | (and Vinyl's hiss and clicks, knob 12, added to the same)
    clrl    mfx_nact
    movel   mfx_noise,%d0
    orl     mfx_vinyl,%d0
    beqw    mfm_bus
    moveq   #1,%d0
    movel   %d0,mfx_nact
    tstl    mfx_noise
    bnes    mfm_nzr
    lea.l   mfx_nzt,%a0           | no riser: the table starts silent
    moveq   #31,%d0
mfm_nzc:
    clrl    %a0@+
    subql   #1,%d0
    bpls    mfm_nzc
    braw    mfm_vin
mfm_nzr:
    movel   mfx_nrng,%d2
    movel   mfx_nlp,%d3
    movel   mfx_na,%d4
    movel   mfx_nlev,%d5
    movel   #1664525,%d6
    lea.l   mfx_nzt,%a2
    moveq   #31,%d7
mfm_nl:
    mulsl   %d6,%d2
    addil   #1013904223,%d2
    movel   %d2,%d0
    swap    %d0
    extl    %d0                   | white, Q15
    movel   %d0,%d1               | lp += (x - lp) a
    subl    %d3,%d1
    asrl    #1,%d1
    mulsl   %d4,%d1
    asrl    #8,%d1
    asrl    #7,%d1
    addl    %d1,%d3
    subl    %d3,%d0               | hp = x - lp
    mulsl   %d5,%d0
    asrl    #8,%d0
    asrl    #7,%d0
    asll    #8,%d0
    asll    #6,%d0                | at the channel's scale, ~-6 dB peak
    movel   %d0,%a2@+
    subql   #1,%d7
    bpls    mfm_nl
    movel   %d2,mfx_nrng
    movel   %d3,mfx_nlp
mfm_vin:
    | ---- Vinyl: the Sampler's crackle and hiss (vinyl_apply's, at 48 kHz),
    | added into the same table - clicks at a chance of Wear^2/128 in 65536
    | a sample, each up to full scale x Wear and dying x 25/64 a sample, and
    | hiss up to +-512 of 16 bits. Continuous while on: a record playing ----
    movel   mfx_vinyl,%d5
    beqw    mfm_bus
    movel   %d5,%d6               | the click chance: Wear^2/128 in 65536 a
    mulul   %d5,%d6               | sample (~90 a second at full Wear)
    lsrl    #7,%d6
    movel   mfx_vrng,%d2
    movel   mfx_vclk,%d3          | the click dying away
    lea.l   mfx_nzt,%a2
    moveq   #31,%d7
mfm_vl:
    movel   #1664525,%d0
    mulsl   %d0,%d2
    addil   #1013904223,%d2
    movel   %d2,%d0               | a click? the top half under the chance
    clrw    %d0                   | (samplerIP cleared all of it: a click
    swap    %d0                   | every sample - the loud noise)
    cmpl    %d6,%d0
    bccs    mfm_vn
    movel   %d2,%d3               | its strength: the low half x Wear
    extl    %d3
    mulsl   %d5,%d3
    asrl    #7,%d3
mfm_vn:
    movel   %d2,%d0               | hiss: +-512 x Wear
    asrl    #8,%d0
    asrl    #8,%d0
    asrl    #6,%d0
    mulsl   %d5,%d0
    asrl    #7,%d0
    addl    %d3,%d0               | + the click
    asll    #8,%d0
    asll    #7,%d0                | at the channel's scale (16 bits << 15)
    addl    %d0,%a2@+
    moveq   #25,%d0               | the click x 25/64
    mulsl   %d0,%d3
    asrl    #6,%d3
    subql   #1,%d7
    bpls    mfm_vl
    movel   %d2,mfx_vrng
    movel   %d3,mfx_vclk
mfm_bus:
    tstl    mfx_nact
    beqs    mfm_x4
    lea.l   mfx_nzt,%a0
    movea.l #0x8000b990,%a1
    moveq   #31,%d7
mfm_bl:
    movel   %a0@+,%d0             | at the channels' scale; the bus is a
    asrl    #2,%d0                | quarter of the output until the x4
    movel   %a1@,%d1
    addl    %d0,%d1
    satsl   %d1
    movel   %d1,%a1@+             | L
    movel   %a1@,%d1
    addl    %d0,%d1
    satsl   %d1
    movel   %d1,%a1@+             | R
    subql   #1,%d7
    bpls    mfm_bl
mfm_x4:
    pea     4
    pea     0x8000b990
    jsr     0x400565c6
    addql   #8,%sp
    moveml  %sp@,%d2-%d7/%a2
    lea.l   %sp@(28),%sp
    rts

| mfb_keypk (a0 = track 0's channel at this sample, d5 = key tracks) -> d0 =
| the largest |sample| among them. Keeps d1-d7.
mfb_keypk:
    movel   %d1,%sp@-
    moveq   #0,%d0
    btst    #0,%d5
    beqs    mkp_1
    movel   %a0@,%d1
    bsr     mkp_m
mkp_1:
    btst    #1,%d5
    beqs    mkp_2
    movel   %a0@(128),%d1
    bsr     mkp_m
mkp_2:
    btst    #2,%d5
    beqs    mkp_3
    movel   %a0@(256),%d1
    bsr     mkp_m
mkp_3:
    btst    #3,%d5
    beqs    mkp_4
    movel   %a0@(384),%d1
    bsr     mkp_m
mkp_4:
    btst    #4,%d5
    beqs    mkp_5
    movel   %a0@(512),%d1
    bsr     mkp_m
mkp_5:
    btst    #5,%d5
    beqs    mkp_6
    movel   %a0@(640),%d1
    bsr     mkp_m
mkp_6:
    movel   %sp@+,%d1
    rts
mkp_m:                            | d0 = max(d0, |d1|)
    tstl    %d1
    bpls    mkp_p
    negl    %d1
mkp_p:
    cmpl    %d0,%d1
    blss    mkp_x
    movel   %d1,%d0
mkp_x:
    rts
mfk_say0:
    moveq   #-1,%d0
    braw    mfk_say

| mfx_say (a0 = label, d0 = value, or -1 for none): the bottom line's text,
| shown for MFX_SHOW blocks. Keeps d2-d7.
mfx_say:
    lea.l   mfx_mbuf,%a1
mfy_c:
    moveb   %a0@+,%d1
    beqs    mfy_v
    moveb   %d1,%a1@+
    bras    mfy_c
mfy_v:
    tstl    %d0
    bmis    mfy_e
    bsr     sys_dec
mfy_e:
    clrb    %a1@
    movel   blk_clk,%d0
    movel   %d0,mfx_mt
    rts

| mfx_coef: the filter's coefficients from mfx_filt / mfx_res into the set
| the audio is not reading, then flip mfx_cur; mfx_on follows the knob.
| UI side. Keeps d2-d7.
mfx_coef:
    lea.l   %sp@(-24),%sp
    moveml  %d2-%d7,%sp@
    movel   mfx_filt,%d0
    bnes    mfc_on
    clrl    mfx_on                | off: the streams fade out on the set they have
    braw    mfc_out
mfc_on:
    lea.l   mfx_glp,%a0
    moveq   #0,%d7                | 0 low-pass, 1 high-pass
    tstl    %d0
    bpls    mfc_hp
    negl    %d0
    bras    mfc_g
mfc_hp:
    lea.l   mfx_ghp,%a0
    moveq   #1,%d7
mfc_g:
    subql   #1,%d0
    movel   %a0@(0,%d0:l:4),%d2   | g, Q24
    movel   mfx_res,%d0           | k = 2 - 1.9 res/127, Q24
    movel   #31876710,%d1
    mulul   %d1,%d0
    moveq   #127,%d1
    divul   %d1,%d0
    movel   #33554432,%d3
    subl    %d0,%d3               | d3 = k
    movel   %d2,%d0               | den = 1 + g (g + k), Q24
    movel   %d2,%d1
    addl    %d3,%d1
    bsr     mul64u
    bsr     sh24
    addil   #16777216,%d0
    bsr     div55                 | a1 = 1 / den, Q31
    bsr     q31sat
    movel   %d0,%d4
    movel   %d2,%d1               | a2 = g a1
    bsr     mul64u
    bsr     sh24
    bsr     q31sat
    movel   %d0,%d5
    movel   %d2,%d1               | a3 = g a2
    bsr     mul64u
    bsr     sh24
    bsr     q31sat
    movel   %d0,%d6
    lea.l   mfx_cs0,%a0           | into the set not in use
    cmpal   mfx_cur,%a0
    bnes    mfc_w
    lea.l   mfx_cs1,%a0
mfc_w:
    movel   %d4,%a0@
    movel   %d5,%a0@(4)
    movel   %d6,%a0@(8)
    movel   %d3,%d0               | k/2, Q31
    lsll    #6,%d0
    bsr     q31sat
    movel   %d0,%a0@(12)
    movel   %a0,mfx_cur
    movel   %d7,mfx_hp
    moveq   #1,%d0
    movel   %d0,mfx_on
mfc_out:
    moveml  %sp@,%d2-%d7
    lea.l   %sp@(24),%sp
    rts
| d0 * d1 -> d0:d1 (high:low), unsigned. Keeps d2-d7.
mul64u:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d5,%sp@
    movel   %d0,%d2
    swap    %d2                   | ah
    movel   %d0,%d3               | al
    movel   %d1,%d4
    swap    %d4                   | bh
    movel   %d1,%d5               | bl
    movel   %d3,%d0
    mulu.w  %d5,%d0               | al bl
    movel   %d2,%d1
    mulu.w  %d5,%d1               | ah bl
    mulu.w  %d4,%d3               | al bh
    mulu.w  %d4,%d2               | ah bh
    movel   %d1,%d4
    swap    %d4
    clrw    %d4
    addl    %d4,%d0
    moveq   #0,%d5
    addxl   %d5,%d2
    movel   %d1,%d4
    clrw    %d4
    swap    %d4
    addl    %d4,%d2
    movel   %d3,%d4
    swap    %d4
    clrw    %d4
    addl    %d4,%d0
    moveq   #0,%d5
    addxl   %d5,%d2
    movel   %d3,%d4
    clrw    %d4
    swap    %d4
    addl    %d4,%d2
    movel   %d0,%d1               | low
    movel   %d2,%d0               | high
    moveml  %sp@,%d2-%d5
    lea.l   %sp@(16),%sp
    rts
| d0:d1 (high:low) >> 24 -> d0 (it fits). Clobbers d1.
sh24:
    lsll    #8,%d0
    swap    %d1                   | low >> 24: its top byte
    andil   #0xffff,%d1
    lsrl    #8,%d1
    orl     %d1,%d0
    rts
| d0 -> 2^55 / d0 (d0 >= 2^24, so the quotient fits). Keeps d2-d7.
div55:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    movel   %d0,%d4               | the divisor
    moveq   #0,%d1                | remainder
    moveq   #0,%d0                | quotient
    moveq   #55,%d2               | the numerator's bit
d55_l:
    addl    %d1,%d1
    cmpil   #55,%d2
    bnes    d55_n
    addql   #1,%d1
d55_n:
    addl    %d0,%d0
    cmpl    %d4,%d1
    bcss    d55_s
    subl    %d4,%d1
    addql   #1,%d0
d55_s:
    subql   #1,%d2
    bpls    d55_l
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
    rts
| d0 unsigned -> at most 0x7fffffff
q31sat:
    tstl    %d0
    bpls    q3_ok
    movel   #0x7fffffff,%d0
q3_ok:
    rts

| mfx_stream(a2 = 32 samples of a channel, d0 = stream: 0-5 a track, 6-11
| its side): the filter, crossed into the channel by the stream's wet, which
| ramps toward on (page up, filter on, the track's pad lit) or off. Keeps
| d2-d7, a2.
mfx_stream:
    lea.l   %sp@(-48),%sp
    moveml  %d2-%d7/%a2-%a6,%sp@
    movel   %d0,%d2
    movel   #-MFX_STEP,%d3        | the ramp's direction: on while any effect
    tstl    mfx_act               | is (page up or not) and the pad is lit
    beqs    mfs_t
    movel   %d2,%d0
    cmpil   #6,%d0
    bcss    mfs_k
    subql   #6,%d0
mfs_k:
    movel   rtg_sel,%d1
    btst    %d0,%d1
    beqs    mfs_t
    movel   #MFX_STEP,%d3
mfs_t:
    movel   %d3,mfx_stp
    lea.l   mfx_wet,%a0
    movel   %a0@(0,%d2:l:4),%d6   | wet, Q16
    bnes    mfs_go
    tstl    %d3
    bpls    mfs_go
    lea.l   mfx_s1,%a0            | dry and staying dry: from rest next time
    clrl    %a0@(0,%d2:l:4)
    lea.l   mfx_s2,%a0
    clrl    %a0@(0,%d2:l:4)
    braw    mfs_out
mfs_go:
    movel   %d2,mfx_si
    movel   %macsr,%d0            | fractional, saturating; put back after
    movel   %d0,mfx_msr
    movel   #0xa0,%macsr
    movea.l mfx_cur,%a0
    movea.l %a0@,%a3              | a1
    movea.l %a0@(4),%a4           | a2
    movea.l %a0@(8),%a5           | a3
    movea.l %a0@(12),%a6          | k/2
    lea.l   mfx_s1,%a0
    movel   %a0@(0,%d2:l:4),%d4   | ic1
    lea.l   mfx_s2,%a0
    movel   %a0@(0,%d2:l:4),%d5   | ic2
    tstl    mfx_on                | the filter off: from rest when it comes on
    bnes    mfs_fon
    moveq   #0,%d4
    moveq   #0,%d5
mfs_fon:
    movel   %d2,%d0               | this stream's history, for Tape stop
    moveq   #18,%d1
    lsll    %d1,%d0
    addil   #RTG_BASE,%d0
    movel   %d0,mfx_rb
    lea.l   mfx_rs,%a0            | this stream's Rate hold: phase, value
    movel   %d2,%d0
    lsll    #3,%d0
    adda.l  %d0,%a0
    movel   %a0,mfx_rsp
    pea     10923                 | 1/3, Q15 - and Drive's two, on the stack
    movel   mfx_dp,%sp@-          | sp@(4) the compensation, Q15
    movel   mfx_dg,%sp@-          | sp@ the gain, Q12
    moveq   #31,%d7
mfs_l:
    movel   %a2@,%d3              | x
    movel   %d3,%d0
    tstl    mfx_tact              | Tape stop: the history at the playhead,
    beqw    mfs_nt                | crossed with live
    lea.l   mfx_tt,%a0
    movel   %d7,%d1
    lsll    #4,%d1
    adda.l  %d1,%a0
    movea.l mfx_rb,%a1
    movel   %a0@,%d1
    andil   #RTG_MASK,%d1
    addl    %d1,%d1
    mvsw    %a1@(0,%d1:l),%d2     | at the position
    movel   %a0@,%d1
    subql   #1,%d1
    andil   #RTG_MASK,%d1
    addl    %d1,%d1
    mvsw    %a1@(0,%d1:l),%d0     | ...and the sample before it
    subl    %d2,%d0
    mulsl   %a0@(4),%d0
    asrl    #8,%d0
    addl    %d2,%d0
    asll    #8,%d0
    asll    #7,%d0                | the tape, at the channel's scale
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %a0@(12),%d0
    movel   %d3,%d1
    asrl    #8,%d1
    asrl    #1,%d1
    mulsl   %a0@(8),%d1
    addl    %d1,%d0
    lsll    #2,%d0
    movea.l mfx_rsp,%a0
mfs_nt:
    tstl    mfx_fact              | Flanger: the history at the swept delay,
    beqw    mfs_nf2               | blended in by the knob
    lea.l   mfx_ft,%a0            | (the block worked out the bytes, the
    movel   %d7,%d1               | fraction and both weights)
    lsll    #5,%d1
    adda.l  %d1,%a0
    movea.l mfx_rb,%a1
    movel   %a0@,%d1
    mvsw    %a1@(0,%d1:l),%d2     | at the position
    movel   %a0@(4),%d1
    mvsw    %a1@(0,%d1:l),%d1     | ...and the sample before it
    subl    %d2,%d1
    mulsl   %a0@(8),%d1
    asrl    #8,%d1
    addl    %d2,%d1               | the delayed sample D, 16 bits
    asll    #6,%d1                | out = ((y>>9)(128-m) + (D<<6) m) << 2:
    mulsl   %a0@(12),%d1          | y (1-m) + (D<<15) m, m = 0..64 of 128
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %a0@(16),%d0
    addl    %d1,%d0
    lsll    #2,%d0
    movea.l mfx_rsp,%a0
mfs_nf2:
    tstl    mfx_ract              | Ring mod: x the sine, before the filter
    beqs    mfs_nrm
    lea.l   mfx_rmt,%a1
    movel   %a1@(0,%d7:l:4),%d1
    asrl    #8,%d0
    asrl    #8,%d0
    mulsl   %d1,%d0
    addl    %d0,%d0
mfs_nrm:
    tstl    mfx_on
    beqw    mfs_x                 | no filter: y = x
    asrl    #2,%d0                | a quarter scale: headroom for resonance
    movea.l %d0,%a1               | xs
    subl    %d5,%d0
    satsl   %d0                   | v3 = xs - ic2
    macl    %a3,%d4,%acc0
    macl    %a4,%d0,%acc0
    movclrl %acc0,%d1             | v1 = a1 ic1 + a2 v3
    macl    %a4,%d4,%acc1
    macl    %a5,%d0,%acc1
    movclrl %acc1,%d0
    addl    %d5,%d0
    satsl   %d0                   | v2 = ic2 + a2 ic1 + a3 v3
    movel   %d1,%d2               | ic1 = 2 v1 - ic1
    addl    %d2,%d2
    satsl   %d2
    subl    %d4,%d2
    satsl   %d2
    movel   %d2,%d4
    movel   %d0,%d2               | ic2 = 2 v2 - ic2
    addl    %d2,%d2
    satsl   %d2
    subl    %d5,%d2
    satsl   %d2
    movel   %d2,%d5
    tstl    mfx_hp
    beqs    mfs_y                 | low-pass: v2
    macl    %a6,%d1,%acc2         | high-pass: xs - k v1 - v2
    movclrl %acc2,%d2
    addl    %d2,%d2
    satsl   %d2
    movel   %a1,%d1
    subl    %d2,%d1
    satsl   %d1
    subl    %d0,%d1
    satsl   %d1
    movel   %d1,%d0
mfs_y:
    cmpil   #0x1fffffff,%d0       | back to full scale, within it
    bles    mfs_c1
    movel   #0x1fffffff,%d0
mfs_c1:
    cmpil   #-0x20000000,%d0
    bges    mfs_c2
    movel   #-0x20000000,%d0
mfs_c2:
    asll    #2,%d0
mfs_x:
    tstl    mfx_drv               | Drive: u = s g, y = u - u^3/3 (|u| <= 1),
    beqs    mfs_nd                | x the compensation
    movel   %d0,%d1
    swap    %d1
    extl    %d1                   | s, Q15
    mulsl   %sp@,%d1
    asrl    #8,%d1
    asrl    #4,%d1
    cmpil   #32767,%d1
    bles    mfs_d1
    movel   #32767,%d1
mfs_d1:
    cmpil   #-32767,%d1
    bges    mfs_d2
    movel   #-32767,%d1
mfs_d2:
    movel   %d1,%d2
    mulsl   %d1,%d2
    asrl    #8,%d2
    asrl    #7,%d2                | u^2
    mulsl   %d1,%d2
    asrl    #8,%d2
    asrl    #7,%d2                | u^3
    mulsl   %sp@(8),%d2
    asrl    #8,%d2
    asrl    #7,%d2                | u^3 / 3
    subl    %d2,%d1
    mulsl   %sp@(4),%d1
    asrl    #8,%d1
    asrl    #7,%d1
    swap    %d1
    clrw    %d1
    movel   %d1,%d0
mfs_nd:
    andl    mfx_mask,%d0          | Crush (all ones when off)
    tstl    mfx_rt                | Rate: a new value each time the phase wraps
    beqs    mfs_nr
    movel   %a0@,%d1
    addl    mfx_rinc,%d1
    cmpil   #65536,%d1
    bcss    mfs_rh
    subil   #65536,%d1
    movel   %d0,%a0@(4)
mfs_rh:
    movel   %d1,%a0@
    movel   %a0@(4),%d0
mfs_nr:
    tstl    mfx_gact              | Gate
    beqs    mfs_ng
    lea.l   mfx_gt,%a1
    movel   %a1@(0,%d7:l:4),%d1
    lsrl    #8,%d1
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %d1,%d0
    addl    %d0,%d0
mfs_ng:
    tstl    mfx_pact              | Pump: the shared duck
    beqs    mfs_np
    lea.l   mfx_pt,%a1
    movel   %a1@(0,%d7:l:4),%d1
    lsrl    #8,%d1
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %d1,%d0
    addl    %d0,%d0
mfs_np:
    addl    mfx_stp,%d6           | the wet, toward its target
    bpls    mfs_w1
    moveq   #0,%d6
mfs_w1:
    cmpil   #65536,%d6
    blss    mfs_w2
    movel   #65536,%d6
mfs_w2:
    movel   %d6,%d2               | out = x (1 - w) + y w, w = 0..128
    lsrl    #8,%d2
    lsrl    #1,%d2
    asrl    #8,%d0
    asrl    #1,%d0
    mulsl   %d2,%d0
    movel   #128,%d1
    subl    %d2,%d1
    asrl    #8,%d3
    asrl    #1,%d3
    mulsl   %d1,%d3
    addl    %d3,%d0
    lsll    #2,%d0
    movel   %d0,%a2@+
    subql   #1,%d7
    bplw    mfs_l
    lea.l   %sp@(12),%sp          | Drive's constants
    movel   mfx_msr,%d0
    movel   %d0,%macsr
    movel   mfx_si,%d2
    lea.l   mfx_wet,%a0
    movel   %d6,%a0@(0,%d2:l:4)
    lea.l   mfx_s1,%a0
    movel   %d4,%a0@(0,%d2:l:4)
    lea.l   mfx_s2,%a0
    movel   %d5,%a0@(0,%d2:l:4)
mfs_out:
    moveml  %sp@,%d2-%d7/%a2-%a6
    lea.l   %sp@(48),%sp
    rts

mfx_s_foff:    .asciz "FILTER OFF"
mfx_s_flp:     .asciz "FILTER LP "
mfx_s_fhp:     .asciz "FILTER HP "
mfx_s_res:     .asciz "RESONANCE "
mfx_s_drv:     .asciz "DRIVE "
mfx_s_crs:     .asciz "CRUSH BITS "
mfx_s_rt:      .asciz "RATE HZ "
mfx_s_tape:    .asciz "TAPE STOP "
mfx_s_rst:     .asciz "FX RESET"
mfx_s_pump:    .asciz "PUMP "
mfx_s_ring:    .asciz "RING MOD HZ "
mfx_s_roff:    .asciz "RING MOD OFF"
mfx_s_noise:   .asciz "NOISE "
mfx_s_vinyl:   .asciz "VINYL "
mfx_s_flg:     .asciz "FLANGER "
mfx_g0:        .asciz "GATE OFF"
mfx_g1:        .asciz "GATE 1/4"
mfx_g2:        .asciz "GATE 1/8"
mfx_g3:        .asciz "GATE 1/8T"
mfx_g4:        .asciz "GATE 1/16"
mfx_g5:        .asciz "GATE 1/16T"
mfx_g6:        .asciz "GATE 1/32"
    .balign 4
mfx_filt:      .long 0            | -127 LP .. 0 off .. 127 HP
mfx_res:       .long 0            | 0..127
mfx_on:        .long 0            | the filter is engaged
mfx_hp:        .long 0            | 1: high-pass
mfx_act:       .long 0            | any effect engaged
mfx_drv:       .long 0            | Drive 0..127
mfx_dg:        .long 4096         | ...its gain, Q12
mfx_dp:        .long 32767        | ...and compensation, Q15
mfx_crs:       .long 0            | Crush 0..127
mfx_mask:      .long -1           | ...as a mask
mfx_rt:        .long 0            | Rate 0..127
mfx_rinc:      .long 65536        | ...the hold's step, Q16
mfx_rs:        .space 8*12        | per stream: Rate's phase and held value
mfx_rsp:       .long 0            | ...this stream's, in the loop
mfx_rb:        .long 0            | this stream's retrig history
mfx_gnames:    .long mfx_g0, mfx_g1, mfx_g2, mfx_g3, mfx_g4, mfx_g5, mfx_g6
mfx_gdiv:      .long 0, RTG_QN, RTG_QN/2, RTG_QN/3, RTG_QN/4, RTG_QN/6, RTG_QN/8
mfx_gate:      .long 0            | Gate: 0 off, 1..6 the division
mfx_gact:      .long 0            | ...running (until open again)
mfx_gg:        .long 65536        | ...its gain, Q16
mfx_gt:        .space 4*32        | ...per sample this block (by the count)
mfx_tape:      .long 0            | Tape stop 0..127
mfx_tact:      .long 0            | ...running (until back to live)
mfx_tspd:      .long 65536        | ...speed, Q16
mfx_tlag:      .long 0            | ...lag behind live, Q8
mfx_ttw:       .long 0            | ...tape vs live, Q16
mfx_tt:        .space 16*32       | ...per sample: position, fraction, weights
mfx_pump:      .long 0            | Pump depth 0..127
mfx_pact:      .long 0            | ...running (until back at unity)
mfx_penv:      .long 0            | ...the key's envelope
mfx_pg:        .long 65536        | ...the smoothed gain, Q16
mfx_pt:        .space 4*32        | ...per sample this block (by the count)
mfx_ring:      .long 0            | Ring mod 0..127 (0 off)
mfx_ract:      .long 0
mfx_rinc2:     .long 0            | ...its phase step, Q32
mfx_rph:       .long 0            | ...phase
mfx_rmt:       .space 4*32        | ...the sine per sample, Q15
mfx_noise:     .long 0            | Noise riser 0..127
mfx_nact:      .long 0
mfx_nzs:       .long 0            | ...the stream it goes into
mfx_na:        .long 0            | ...the high-pass's pole, Q16
mfx_nlev:      .long 0            | ...level, Q15
mfx_nrng:      .long 0x12345678   | ...noise state
mfx_nlp:       .long 0            | ...the high-pass's state
mfx_nzt:       .space 4*32        | ...per sample (and Vinyl's, added)
mfx_vinyl:     .long 0            | Vinyl Wear 0..127
mfx_vrng:      .long 0x2468ace1   | ...its noise
mfx_vclk:      .long 0            | ...the click dying away
mfx_flg:       .long 0            | Flanger depth 0..127
mfx_fmix:      .long 0            | ...as the blend, 0..64 of 128
mfx_fact:      .long 0
mfx_fph:       .long 0            | ...the sweep's phase, Q32
mfx_ft:        .space 32*32       | ...per sample: the two history bytes,
                                  | fraction, m and 128 - m
mfx_cur:       .long mfx_cs0      | the coefficient set the audio reads
mfx_cs0:       .long 0,0,0,0      | a1, a2, a3, k/2 - Q31
mfx_cs1:       .long 0,0,0,0
mfx_mt:        .long 0            | blk_clk when a knob last spoke
mfx_stp:       .long 0            | this stream's ramp step
mfx_si:        .long 0            | ...and its index
mfx_msr:       .long 0            | MACSR while the filter runs
mfx_wet:       .space 4*12        | per stream: dry 0 .. 65536 wet
mfx_s1:        .space 4*12        | per stream: the filter's two states
mfx_s2:        .space 4*12
mfx_mbuf:      .space 24          | the bottom line while a knob speaks
mfx_dg_t:   | Drive: gain 1..8, Q12
    .word 4096, 4322, 4548, 4773, 4999, 5225, 5451, 5676
    .word 5902, 6128, 6354, 6579, 6805, 7031, 7257, 7482
    .word 7708, 7934, 8160, 8386, 8611, 8837, 9063, 9289
    .word 9514, 9740, 9966, 10192, 10417, 10643, 10869, 11095
    .word 11320, 11546, 11772, 11998, 12223, 12449, 12675, 12901
    .word 13127, 13352, 13578, 13804, 14030, 14255, 14481, 14707
    .word 14933, 15158, 15384, 15610, 15836, 16061, 16287, 16513
    .word 16739, 16965, 17190, 17416, 17642, 17868, 18093, 18319
    .word 18545, 18771, 18996, 19222, 19448, 19674, 19899, 20125
    .word 20351, 20577, 20803, 21028, 21254, 21480, 21706, 21931
    .word 22157, 22383, 22609, 22834, 23060, 23286, 23512, 23737
    .word 23963, 24189, 24415, 24641, 24866, 25092, 25318, 25544
    .word 25769, 25995, 26221, 26447, 26672, 26898, 27124, 27350
    .word 27575, 27801, 28027, 28253, 28478, 28704, 28930, 29156
    .word 29382, 29607, 29833, 30059, 30285, 30510, 30736, 30962
    .word 31188, 31413, 31639, 31865, 32091, 32316, 32542, 32768
mfx_dp_t:   | Drive: level compensation 1/sqrt(gain), Q15
    .word 32767, 31900, 31098, 30353, 29660, 29012, 28405, 27834
    .word 27297, 26789, 26309, 25854, 25421, 25010, 24618, 24243
    .word 23886, 23543, 23216, 22901, 22599, 22308, 22029, 21759
    .word 21499, 21249, 21007, 20773, 20546, 20327, 20115, 19909
    .word 19710, 19516, 19328, 19146, 18968, 18795, 18627, 18463
    .word 18304, 18148, 17997, 17849, 17705, 17564, 17427, 17292
    .word 17161, 17033, 16907, 16785, 16665, 16547, 16432, 16319
    .word 16209, 16101, 15995, 15891, 15789, 15689, 15590, 15494
    .word 15399, 15307, 15215, 15126, 15038, 14951, 14866, 14782
    .word 14700, 14619, 14540, 14462, 14385, 14309, 14234, 14161
    .word 14088, 14017, 13947, 13878, 13810, 13743, 13676, 13611
    .word 13547, 13484, 13421, 13360, 13299, 13239, 13180, 13121
    .word 13064, 13007, 12951, 12895, 12841, 12787, 12733, 12681
    .word 12629, 12577, 12526, 12476, 12427, 12378, 12329, 12282
    .word 12234, 12188, 12141, 12096, 12051, 12006, 11962, 11918
    .word 11875, 11832, 11790, 11748, 11706, 11666, 11625, 11585
    .balign 4
mfx_ri_t:   | Rate: hold step per sample, Q16 (48 kHz -> 1 kHz)
    .long 65536, 63568, 61660, 59809, 58013, 56272, 54582, 52944
    .long 51354, 49812, 48317, 46866, 45459, 44094, 42771, 41487
    .long 40241, 39033, 37861, 36724, 35622, 34552, 33515, 32509
    .long 31533, 30586, 29668, 28777, 27913, 27075, 26263, 25474
    .long 24709, 23967, 23248, 22550, 21873, 21216, 20579, 19962
    .long 19362, 18781, 18217, 17670, 17140, 16625, 16126, 15642
    .long 15172, 14717, 14275, 13846, 13431, 13027, 12636, 12257
    .long 11889, 11532, 11186, 10850, 10524, 10208, 9902, 9605
    .long 9316, 9037, 8765, 8502, 8247, 7999, 7759, 7526
    .long 7300, 7081, 6868, 6662, 6462, 6268, 6080, 5898
    .long 5720, 5549, 5382, 5221, 5064, 4912, 4764, 4621
    .long 4483, 4348, 4217, 4091, 3968, 3849, 3733, 3621
    .long 3513, 3407, 3305, 3206, 3109, 3016, 2925, 2838
    .long 2752, 2670, 2590, 2512, 2436, 2363, 2292, 2224
    .long 2157, 2092, 2029, 1968, 1909, 1852, 1796, 1742
    .long 1690, 1639, 1590, 1542, 1496, 1451, 1408, 1365
    .balign 4
mfx_sin:   | sine, 256 steps and one over, Q15
    .word 0, 804, 1608, 2410, 3212, 4011, 4808, 5602
    .word 6393, 7179, 7962, 8739, 9512, 10278, 11039, 11793
    .word 12539, 13279, 14010, 14732, 15446, 16151, 16846, 17530
    .word 18204, 18868, 19519, 20159, 20787, 21403, 22005, 22594
    .word 23170, 23731, 24279, 24811, 25329, 25832, 26319, 26790
    .word 27245, 27683, 28105, 28510, 28898, 29268, 29621, 29956
    .word 30273, 30571, 30852, 31113, 31356, 31580, 31785, 31971
    .word 32137, 32285, 32412, 32521, 32609, 32678, 32728, 32757
    .word 32767, 32757, 32728, 32678, 32609, 32521, 32412, 32285
    .word 32137, 31971, 31785, 31580, 31356, 31113, 30852, 30571
    .word 30273, 29956, 29621, 29268, 28898, 28510, 28105, 27683
    .word 27245, 26790, 26319, 25832, 25329, 24811, 24279, 23731
    .word 23170, 22594, 22005, 21403, 20787, 20159, 19519, 18868
    .word 18204, 17530, 16846, 16151, 15446, 14732, 14010, 13279
    .word 12539, 11793, 11039, 10278, 9512, 8739, 7962, 7179
    .word 6393, 5602, 4808, 4011, 3212, 2410, 1608, 804
    .word 0, -804, -1608, -2410, -3212, -4011, -4808, -5602
    .word -6393, -7179, -7962, -8739, -9512, -10278, -11039, -11793
    .word -12539, -13279, -14010, -14732, -15446, -16151, -16846, -17530
    .word -18204, -18868, -19519, -20159, -20787, -21403, -22005, -22594
    .word -23170, -23731, -24279, -24811, -25329, -25832, -26319, -26790
    .word -27245, -27683, -28105, -28510, -28898, -29268, -29621, -29956
    .word -30273, -30571, -30852, -31113, -31356, -31580, -31785, -31971
    .word -32137, -32285, -32412, -32521, -32609, -32678, -32728, -32757
    .word -32767, -32757, -32728, -32678, -32609, -32521, -32412, -32285
    .word -32137, -31971, -31785, -31580, -31356, -31113, -30852, -30571
    .word -30273, -29956, -29621, -29268, -28898, -28510, -28105, -27683
    .word -27245, -26790, -26319, -25832, -25329, -24811, -24279, -23731
    .word -23170, -22594, -22005, -21403, -20787, -20159, -19519, -18868
    .word -18204, -17530, -16846, -16151, -15446, -14732, -14010, -13279
    .word -12539, -11793, -11039, -10278, -9512, -8739, -7962, -7179
    .word -6393, -5602, -4808, -4011, -3212, -2410, -1608, -804
    .word 0
    .balign 4
mfx_rinc_t:   | Ring mod: phase step, Q32 (30 Hz -> 4 kHz)
    .long 2684355, 2789791, 2899369, 3013251, 3131606, 3254609, 3382445, 3515301
    .long 3653375, 3796873, 3946007, 4100999, 4262079, 4429486, 4603468, 4784283
    .long 4972201, 5167500, 5370470, 5581412, 5800640, 6028478, 6265266, 6511354
    .long 6767108, 7032908, 7309147, 7596237, 7894603, 8204689, 8526954, 8861877
    .long 9209955, 9571705, 9947664, 10338390, 10744463, 11166486, 11605085, 12060911
    .long 12534642, 13026979, 13538655, 14070429, 14623089, 15197457, 15794385, 16414760
    .long 17059501, 17729567, 18425952, 19149689, 19901854, 20683562, 21495974, 22340297
    .long 23217783, 24129734, 25077506, 26062504, 27086191, 28150087, 29255771, 30404884
    .long 31599132, 32840287, 34130193, 35470765, 36863991, 38311941, 39816763, 41380693
    .long 43006050, 44695249, 46450796, 48275298, 50171462, 52142105, 54190151, 56318641
    .long 58530733, 60829713, 63218992, 65702118, 68282776, 70964798, 73752165, 76649014
    .long 79659646, 82788531, 86040312, 89419817, 92932063, 96582263, 100375837, 104318415
    .long 108415851, 112674226, 117099862, 121699329, 126479455, 131447336, 136610345, 141976148
    .long 147552710, 153348309, 159371549, 165631370, 172137065, 178898293, 185925089, 193227884
    .long 200817520, 208705263, 216902821, 225422365, 234276541, 243478493, 253041880, 262980900
    .long 273310306, 284045432, 295202214, 306797214, 318847644, 331371393, 344387051, 357913941
mfx_nhp_t:   | Noise: the high-pass's pole, Q16 (200 Hz -> 8 kHz)
    .word 1693, 1743, 1793, 1845, 1899, 1954, 2011, 2069
    .word 2129, 2191, 2254, 2320, 2387, 2456, 2527, 2600
    .word 2675, 2752, 2831, 2913, 2996, 3083, 3171, 3262
    .word 3356, 3452, 3551, 3653, 3757, 3865, 3975, 4089
    .word 4205, 4325, 4448, 4574, 4704, 4838, 4975, 5115
    .word 5260, 5408, 5561, 5717, 5878, 6043, 6213, 6386
    .word 6565, 6748, 6936, 7129, 7327, 7530, 7738, 7952
    .word 8171, 8396, 8626, 8862, 9104, 9353, 9607, 9868
    .word 10135, 10408, 10689, 10976, 11270, 11571, 11879, 12194
    .word 12517, 12847, 13184, 13530, 13883, 14244, 14613, 14991
    .word 15376, 15770, 16172, 16582, 17002, 17429, 17866, 18311
    .word 18765, 19227, 19699, 20179, 20668, 21167, 21674, 22190
    .word 22715, 23248, 23791, 24342, 24902, 25471, 26047, 26633
    .word 27226, 27827, 28437, 29054, 29678, 30310, 30948, 31594
    .word 32246, 32904, 33567, 34237, 34911, 35590, 36273, 36960
    .word 37651, 38344, 39040, 39738, 40437, 41137, 41838, 42537
    .balign 4
mfx_glp:   | low-pass, filter -1..-127: g = tan(pi fc/48000), Q24, fc 20 kHz -> 30 Hz
    .long 62613422, 49361129, 40795999, 34771803, 30281522, 26789873, 23985929, 21676645
    .long 19735778, 18077251, 16640328, 15380901, 14266148, 13271123, 12376516, 11567133
    .long 10830849, 10157857, 9540136, 8971052, 8445068, 7957517, 7504436, 7082433
    .long 6688581, 6320341, 5975495, 5652094, 5348414, 5062927, 4794266, 4541207
    .long 4302646, 4077588, 3865125, 3664433, 3474759, 3295410, 3125751, 2965196
    .long 2813203, 2669269, 2532929, 2403749, 2281324, 2165278, 2055257, 1950930
    .long 1851989, 1758142, 1669116, 1584653, 1504513, 1428466, 1356298, 1287806
    .long 1222799, 1161095, 1102523, 1046923, 994140, 944030, 896455, 851287
    .long 808403, 767684, 729023, 692313, 657455, 624356, 592926, 563081
    .long 534740, 507828, 482271, 458002, 434956, 413070, 392286, 372549
    .long 353805, 336005, 319101, 303048, 287802, 273324, 259575, 246517
    .long 234117, 222340, 211156, 200534, 190447, 180868, 171770, 163130
    .long 154924, 147132, 139731, 132703, 126028, 119689, 113669, 107952
    .long 102522, 97365, 92468, 87817, 83400, 79205, 75221, 71438
    .long 67845, 64432, 61192, 58114, 55191, 52415, 49779, 47275
    .long 44897, 42639, 40494, 38457, 36523, 34686, 32942
mfx_ghp:   | high-pass, filter +1..+127: fc 20 Hz -> 10 kHz
    .long 21961, 23071, 24238, 25463, 26751, 28103, 29524, 31017
    .long 32585, 34232, 35963, 37781, 39692, 41698, 43807, 46022
    .long 48348, 50793, 53361, 56059, 58893, 61871, 64999, 68285
    .long 71738, 75365, 79175, 83178, 87384, 91802, 96444, 101320
    .long 106442, 111824, 117478, 123418, 129658, 136214, 143101, 150336
    .long 157938, 165923, 174313, 183127, 192386, 202114, 212334, 223070
    .long 234350, 246200, 258650, 271729, 285470, 299906, 315072, 331006
    .long 347746, 365333, 383810, 403223, 423618, 445045, 467558, 491210
    .long 516060, 542169, 569601, 598424, 628707, 660526, 693958, 729087
    .long 765999, 804785, 845542, 888369, 933374, 980670, 1030373, 1082608
    .long 1137507, 1195208, 1255857, 1319607, 1386621, 1457070, 1531137, 1609011
    .long 1690898, 1777010, 1867576, 1962838, 2063050, 2168485, 2279433, 2396202
    .long 2519120, 2648539, 2784833, 2928404, 3079685, 3239138, 3407263, 3584600
    .long 3771732, 3969293, 4177972, 4398522, 4631767, 4878610, 5140050, 5417191
    .long 5711258, 6023621, 6355813, 6709562, 7086824, 7489827, 7921118, 8383635
    .long 8880783, 9416536, 9995571, 10623434, 11306760, 12053559, 12873610

| rtg_render (d2 = ctx): the whole page. Keeps d2-d7.
rtg_render:
    lea.l   %sp@(-16),%sp
    moveml  %d3-%d5/%a2,%sp@
    clrl    %sp@-                 | clear the screen
    pea     63
    pea     127
    clrl    %sp@-
    clrl    %sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    lea.l   rtg_s_mode,%a0        | MODE      MOMENTARY / LATCH   (DATA)
    moveq   #1,%d0
    jsr     sys_left
    lea.l   rtg_s_mom,%a0
    tstl    rtg_latch
    beqs    rgr_m
    lea.l   rtg_s_lat,%a0
rgr_m:
    moveq   #1,%d0
    jsr     sys_right
    lea.l   rtg_s_fx,%a0          | FX RETURNS    OFF / ON        (knob)
    moveq   #11,%d0
    jsr     sys_left
    lea.l   rtg_s_off,%a0
    tstl    rtg_fx
    beqs    rgr_f
    lea.l   rtg_s_on,%a0
rgr_f:
    moveq   #11,%d0
    jsr     sys_right
    pea     -1                    | the cursor: its row inverted, or only the
    movel   rtg_row,%d0           | value while DATA's press has it editing
    moveq   #10,%d1
    mulsl   %d1,%d0               | rows 10r..10r+9 from the top are
    moveq   #63,%d1               | 54-10r..63-10r from the bottom
    subl    %d0,%d1
    movel   %d1,%sp@-             | y1
    pea     127
    subil   #9,%d1
    movel   %d1,%sp@-             | y0
    moveq   #0,%d0
    tstl    rtg_edit
    beqs    rgr_c
    moveq   #64,%d0
rgr_c:
    movel   %d0,%sp@-             | x0
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    moveq   #0,%d3                | the six tracks: a box each, lit when on
rgr_t:
    movel   %d3,%d4
    moveq   #21,%d0
    mulul   %d0,%d4
    addql   #2,%d4                | x0
    pea     1                     | the outline (y from the bottom: rows
    pea     39                    | 24..35 from the top)
    movel   %d4,%d0
    addil   #18,%d0
    movel   %d0,%sp@-
    pea     28
    movel   %d4,%sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    clrl    %sp@-                 | its inside
    pea     38
    movel   %d4,%d0
    addil   #17,%d0
    movel   %d0,%sp@-
    pea     29
    movel   %d4,%d0
    addql   #1,%d0
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    movel   %d3,%d0               | its number
    addql   #1,%d0
    movel   %d0,%sp@-
    pea     rtg_s_num
    pea     0x02
    pea     29
    movel   %d4,%d0
    addil   #9,%d0
    movel   %d0,%sp@-
    pea     SYS_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    movel   rtg_sel,%d0           | on: the box inverted
    btst    %d3,%d0
    beqs    rgr_tn
    pea     -1
    pea     38
    movel   %d4,%d0
    addil   #17,%d0
    movel   %d0,%sp@-
    pea     29
    movel   %d4,%d0
    addql   #1,%d0
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
rgr_tn:
    addql   #1,%d3
    cmpil   #6,%d3
    bcsw    rgr_t
    bsr     rtg_want              | the repeat playing, big in the middle
    lea.l   rtg_s_none,%a0
    tstl    %d0
    bmis    rgr_d
    lea.l   rtg_names,%a0
    movea.l %a0@(0,%d0:l:4),%a0
rgr_d:
    movel   %a0,%sp@-
    pea     0x40124b58            | "%s"
    pea     0x12
    pea     14                    | row 41 from the top
    pea     64
    pea     SYS_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    lea.l   rtg_s_hint,%a0
    movel   blk_clk,%d0           | a master-FX knob just turned: its value
    subl    mfx_mt,%d0            | for a second instead of the hint
    cmpil   #MFX_SHOW,%d0
    bccs    rgr_hint
    lea.l   mfx_mbuf,%a0
rgr_hint:
    moveq   #54,%d0
    jsr     sys_left
    moveml  %sp@,%d3-%d5/%a2
    lea.l   %sp@(16),%sp
    rts

rtg_s_mode:    .asciz "RETRIG"
rtg_s_mom:     .asciz "MOMENTARY"
rtg_s_lat:     .asciz "LATCH"
rtg_s_fx:      .asciz "FX RETURNS"
rtg_s_off:     .asciz "OFF"
rtg_s_on:      .asciz "ON"
rtg_s_num:     .asciz "%d"
rtg_s_none:    .asciz "--"
rtg_s_hint:    .asciz "PADS TRACKS  STEPS RATE"
rtg_n1:        .asciz "1/64"
rtg_n2:        .asciz "1/48"
rtg_n3:        .asciz "1/32"
rtg_n4:        .asciz "1/24"
rtg_n5:        .asciz "1/16"
rtg_n6:        .asciz "1/12"
rtg_n7:        .asciz "1/8"
rtg_n8:        .asciz "1/6"
rtg_n9:        .asciz "3/16"
rtg_n10:       .asciz "1/4"
rtg_n11:       .asciz "1/3"
rtg_n12:       .asciz "3/8"
rtg_n13:       .asciz "1/2"
rtg_n14:       .asciz "2/3"
rtg_n15:       .asciz "3/4"
rtg_n16:       .asciz "1 BAR"
    .balign 4
rtg_names:     .long rtg_n1, rtg_n2, rtg_n3, rtg_n4, rtg_n5, rtg_n6, rtg_n7, rtg_n8
               .long rtg_n9, rtg_n10, rtg_n11, rtg_n12, rtg_n13, rtg_n14, rtg_n15, rtg_n16
rtg_divs:      .long RTG_QN/16, RTG_QN/12, RTG_QN/8, RTG_QN/6, RTG_QN/4, RTG_QN/3
               .long RTG_QN/2, RTG_QN*2/3, RTG_QN*3/4, RTG_QN, RTG_QN*4/3, RTG_QN*3/2
               .long RTG_QN*2, RTG_QN*8/3, RTG_QN*3, RTG_QN*4
rtg_on:        .long 0            | the page is up
rtg_pat:       .long 0            | Pattern is held (trig keys pass through)
rtg_pat0:      .long 0            | the pattern the page opened on
rtg_topv:      .long 0            | the page's own entry at the top of the stack
rtg_sel:       .long 0x3f         | tracks it acts on, bit n = track n
rtg_latch:     .long 0            | 0 Momentary, 1 Latch
rtg_fx:        .long 0            | the delay and reverb returns too
rtg_row:       .long 0            | the page's cursor: 0 the mode, 1 FX returns
rtg_edit:      .long 0            | DATA's press: turning changes the value
rtg_seq:       .long 0            | press counter: the newest held step wins
rtg_lstep:     .long -1           | Latch: the step on
rtg_held:      .space 64          | per step: its press number while held
rtg_act:       .long -1           | audio: the repeat installed
rtg_des:       .long -1           | audio: the step asked for this block
rtg_lv:        .long 0            | audio: a slice is installed
rtg_lst:       .long 0            | audio: its first sample, absolute
rtg_len:       .long 0            | audio: its length, samples
rtg_e0:        .long 0            | audio: this block, samples into it
rtg_bar:       .long 0            | step 1's time on the audio clock
rtg_pstep:     .long 0
rtg_wet:       .space 4*RTG_NS    | per stream: repeat vs live, Q16
rtg_pos:       .space 128         | this block: the slice position per sample
rtg_env:       .space 128         | ...and the fade there, Q16

| ---- System: CPU and RAM on a page of their own -----------------------------
| A row after Transfer in Device Config opens a full-screen page - the
| machine-page page the mode menu is built on, kind MM_SYS, drawn entirely by
| sys_render (a list menu keeps half the screen for its title):
|   CPU   the load now - busy time over block time, smoothed - and a bar
|   PEAK  the worst single block since the page opened
|   RAM   sample memory in use (every resident slot) of the region, a bar
|   FREE  what is left
| Turning DATA right shows a second page, each track's share (sys_r2), and
| left comes back. Return, Preset or Track closes it; the page only redraws
| on request, so sys_tick asks twice a second.
SYS_REDRAW = 750                  | blocks: half a second
SLE_REDRAW = 75                   | blocks: the tap playhead, 20 times a second
SYS_FONT   = 0x40ea14cc           | the small font
SYS_RAM    = PCM_TOP-PCM_BASE
sys_row:       .long sys_lab, sys_nop, sys_nop, sys_press
sys_lab:
    lea.l   sys_s_row,%a1
    braw    gm_lab
sys_nop:
    moveq   #0,%d0
    rts
sys_press:
    clrl    sys_pg                | always opens on the first page
    clrl    prof_max              | PEAK counts from now
    movel   blk_clk,%d0
    movel   %d0,sys_last
    moveq   #MM_SYS,%d0
    jsr     mm_open
    moveq   #0,%d0
    rts

| sys_render (d2 = ctx): the whole page. Keeps d2-d7.
sys_render:
    lea.l   %sp@(-12),%sp
    moveml  %d3-%d4/%a2,%sp@
    clrl    %sp@-                 | clear the screen
    pea     63
    pea     127
    clrl    %sp@-
    clrl    %sp@-
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    movel   sys_pg,%d0
    subql   #1,%d0
    beqw    sys_r2
    movel   prof_busy,%d0         | CPU
    bsr     prof_pct
    movel   %d0,%d3
    lea.l   sys_s_cpu,%a0
    moveq   #1,%d0
    bsr     sys_left
    movel   %d3,%d0
    bsr     sys_pctbuf
    moveq   #1,%d0
    bsr     sys_right
    moveq   #12,%d0
    movel   %d3,%d1
    bsr     sys_bar
    lea.l   sys_s_peak,%a0        | PEAK
    moveq   #19,%d0
    bsr     sys_left
    movel   prof_max,%d0
    bsr     sys_pctbuf
    moveq   #19,%d0
    bsr     sys_right
    bsr     sys_used              | RAM: used / all
    movel   %d0,%d3
    lea.l   sys_s_ram,%a0
    moveq   #33,%d0
    bsr     sys_left
    movel   %d3,%d0
    lea.l   sys_vbuf,%a1
    bsr     sys_mb
    moveb   #47,%a1@+             | '/'
    movel   #SYS_RAM,%d0
    bsr     sys_mb
    moveb   #77,%a1@+             | 'M'
    clrb    %a1@
    lea.l   sys_vbuf,%a0
    moveq   #33,%d0
    bsr     sys_right
    movel   %d3,%d0               | the bar: used * 100 / all, in KiB
    lsrl    #8,%d0
    lsrl    #2,%d0
    moveq   #100,%d1
    mulul   %d1,%d0
    movel   #SYS_RAM>>10,%d1
    divul   %d1,%d0
    movel   %d0,%d1
    moveq   #44,%d0
    bsr     sys_bar
    lea.l   sys_s_free,%a0        | FREE
    moveq   #51,%d0
    bsr     sys_left
    movel   #SYS_RAM,%d0
    subl    %d3,%d0
    lea.l   sys_vbuf,%a1
    bsr     sys_mb
    moveb   #77,%a1@+
    clrb    %a1@
    lea.l   sys_vbuf,%a0
    moveq   #51,%d0
    bsr     sys_right
sys_r_out:
    moveml  %sp@,%d3-%d4/%a2
    lea.l   %sp@(12),%sp
    rts
| The second page: each track's render - the machine's parameters, its fill,
| filter, effects and gain stages, from sampler_dispatch to sd_prof
| (prof_trk) - as a share of the block, T1-T3 on the left and T4-T6 on the
| right; TRACKS their sum, OTHER the rest of the busy time (the mixer, send
| effects, output stage and every per-block hook), TOTAL the CPU figure of
| the first page. Tenths of a percent: a quiet track costs a few.
sys_r2:
    moveq   #0,%d3                | track
    moveq   #0,%d4                | the tracks' sum
s2_t:
    lea.l   prof_trk,%a0
    movel   %a0@(0,%d3:l:4),%d0
    addl    %d0,%d4
    lea.l   sys_lbuf,%a1          | "T1".."T6"
    moveb   #84,%a1@
    movel   %d3,%d1
    addil   #49,%d1
    moveb   %d1,%a1@(1)
    clrb    %a1@(2)
    moveq   #0,%d1                | column 0 or 1, row 0..2
    movel   %d3,%a2
    cmpil   #3,%d3
    bcss    s2_c
    moveq   #1,%d1
    subql   #3,%a2
s2_c:
    movel   %d1,sys_t             | the column, while the label is drawn
    movel   %a2,%d0
    moveq   #10,%d1
    mulul   %d1,%d0
    addql   #1,%d0                | y
    movea.l %d0,%a2
    moveq   #2,%d1                | label x: 2 or 68
    tstl    sys_t
    beqs    s2_lx
    moveq   #68,%d1
s2_lx:
    lea.l   sys_lbuf,%a0
    bsr     sys_atl
    lea.l   prof_trk,%a0
    movel   %a0@(0,%d3:l:4),%d0
    bsr     sys_pct10
    moveq   #60,%d1               | value x: 60 or 125
    tstl    sys_t
    beqs    s2_vx
    moveq   #125,%d1
s2_vx:
    movel   %a2,%d0
    bsr     sys_atr
    addql   #1,%d3
    cmpil   #6,%d3
    bcsw    s2_t
    lea.l   sys_s_trk,%a0         | TRACKS
    moveq   #33,%d0
    bsr     sys_left
    movel   %d4,%d0
    bsr     sys_pct10
    moveq   #33,%d0
    bsr     sys_right
    lea.l   sys_s_oth,%a0         | OTHER: busy less the tracks
    moveq   #43,%d0
    bsr     sys_left
    movel   prof_busy,%d0
    subl    %d4,%d0
    bpls    s2_o
    moveq   #0,%d0
s2_o:
    bsr     sys_pct10
    moveq   #43,%d0
    bsr     sys_right
    lea.l   sys_s_tot,%a0         | TOTAL
    moveq   #53,%d0
    bsr     sys_left
    movel   prof_busy,%d0
    bsr     sys_pct10
    moveq   #53,%d0
    bsr     sys_right
    braw    sys_r_out

| fx_early - takes the place of the block's `jsr 0x400a7d4a` (the voice loop)
| at 0x4005981e. It first runs 0x4005802e, the effects' per-block setup,
| which the output stage used to call at 0x400567d8: the reverb's tap
| tables in SRAM and the delay's read, started as a DMA on eDMA channel 30
| that the output stage then spins on (0x4005697e) - ~4.5% of every block
| spent waiting. Started here, the transfer runs while the voices render.
| Bit-exact: it reads only state the effects left last block and the delay
| time (a2+428, set before this point), and nothing between here and the
| output stage reads or writes what it touches. At 0x400567d6 the call is
| replaced by what it left behind: MACSR 0x20, acc0 and acc1 clear.
| a2 = the block's state, as the voice loop's own argument.
fx_early:
    clrl    fx_setup
    tstl    fx_off                | the effects are off: no setup, no DMA
    bnes    fxe_v
    movel   %a2,%sp@-
    jsr     FX_SETUP
    addql   #4,%sp
    moveq   #1,%d0
    movel   %d0,fx_setup
fxe_v:
    jmp     FX_VOICES

| ---- the send effects, off while they have nothing to do ----
| Delay and reverb run every block whatever they hold: ~12% of the CPU with
| nothing playing. They are skipped - setup (0x4005802e), delay 0x40057488,
| reverb 0x400579c4, the reverb's ring step 0x40057942 and the write-back
| DMA 0x400573fa - once, for FX_HOLD blocks in a row, no track has made a
| sound (their channels, which is all the sends read) and neither effect has
| put one out. FX_HOLD is one turn of the delay's ring (524288 samples,
| 10.9 s), so by then everything the effects hold is below the silence level
| too. Skipped, nothing of theirs moves: rings, positions, the delay's
| smoothing and the reverb's modulation are all left exactly as they were,
| and their outputs (0x8000ba90, 0x8000bb90) are silence. The first block
| with any sound runs them all again from there - its setup late, with the
| stock wait, if the top of the block skipped it - so they continue as if
| paused. Both go together: they share the DMA chains.
FX_HOLD = 16384
fx_off:     .long 0               | the effects are skipped
fx_skip:    .long 0               | ...and were, this block
fx_setup:   .long 0               | 0x4005802e ran at the top of this block
fx_insil:   .long 0               | this block's track channels are silent
fx_cnt:     .long 0               | blocks in a row with nothing in or out
fx_ret:     .long 0

| fx_quiet(a0 = buffer, d0 = longs) -> Z set when every |sample| < SIL_LVL.
| Clobbers d0, d1, a0.
fx_quiet:
    movel   %a0@+,%d1
    bpls    fxq_p
    negl    %d1
fxq_p:
    cmpil   #SIL_LVL,%d1
    bccs    fxq_loud
    subql   #1,%d0
    bnes    fx_quiet
    rts                           | Z: quiet
fxq_loud:
    moveq   #1,%d0                | NZ
    rts

| in place of `jsr 0x40057488` at 0x4005699c: (out 0x8000ba90, in 0x8000b990,
| state + 428)
fx_a:
    lea.l   0x80001858,%a0        | the six track channels
    movel   #6*32,%d0
    bsr     fx_quiet
    seq     %d0
    extbl   %d0
    movel   %d0,fx_insil
    tstl    fx_off
    beqs    fxa_run
    tstl    %d0
    beqs    fxa_on                | a sound: back on
    movea.l %sp@(4),%a0           | still silent: the delay's output silent
    moveq   #1,%d0
    movel   %d0,fx_skip
    bras    fx_zero
fxa_on:
    clrl    fx_off
    clrl    fx_cnt
fxa_run:
    clrl    fx_skip
    tstl    fx_setup              | the top of the block skipped the setup
    bnes    fxa_go
    movel   %sp@(12),%d0          | state + 428
    subil   #428,%d0
    movel   %d0,%sp@-
    jsr     0x4005802e
    addql   #4,%sp
fxa_w:
    moveq   #16,%d1               | ...and its DMA: the stock wait
    movew   0xfc0453de,%d0
    andl    %d1,%d0
    tstw    %d0
    bnes    fxa_w
fxa_go:
    jmp     0x40057488
fx_zero:                          | a0: 32 stereo frames of silence
    moveq   #31,%d0
    moveq   #0,%d1
fxz_l:
    movel   %d1,%a0@+
    movel   %d1,%a0@+
    subql   #1,%d0
    bpls    fxz_l
    rts

| in place of `jsr 0x400579c4` at 0x40056a2c: (out 0x8000bb90, in, state+432)
fx_b:
    tstl    fx_skip
    beqs    fxb_run
    movea.l %sp@(4),%a0           | skipped: the reverb's output silent
    bras    fx_zero
fxb_run:
    movel   %sp@+,%d0             | the caller's stack, exactly, for the reverb
    movel   %d0,fx_ret
    jsr     0x400579c4
    movel   fx_ret,%d0
    movel   %d0,%sp@-
    tstl    fx_insil              | nothing in, nothing out: count toward off
    beqs    fxb_loud
    lea.l   0x8000ba90,%a0        | the delay's output and the reverb's
    moveq   #64,%d0
    bsr     fx_quiet
    bnes    fxb_loud
    lea.l   0x8000bb90,%a0
    moveq   #64,%d0
    bsr     fx_quiet
    bnes    fxb_loud
    movel   fx_cnt,%d0
    addql   #1,%d0
    movel   %d0,fx_cnt
    cmpil   #FX_HOLD,%d0
    bcss    fxb_out
    moveq   #1,%d0
    movel   %d0,fx_off
    rts
fxb_loud:
    clrl    fx_cnt
fxb_out:
    rts

| in place of `jsr 0x40057942 ; jsr 0x400573fa` at 0x40056a36: the reverb's
| ring step and the write-back DMA, unless skipped
fx_c:
    tstl    fx_skip
    bnes    fxc_out
    jsr     0x40057942
    jmp     0x400573fa
fxc_out:
    rts

| sys_pct10 (d0 = a share of prof_per) -> a0 = "12.3%", in sys_vbuf. As
| prof_pct, in tenths. Keeps d2-d7 and sys_t.
sys_pct10:
    movel   prof_per,%d1
    lsrl    #8,%d1
    bnes    sp10_d
    moveq   #0,%d0
    bras    sp10_f
sp10_d:
    lsrl    #8,%d0
    movel   %d1,%sp@-
    movel   #1000,%d1
    mulul   %d1,%d0
    movel   %sp@+,%d1
    divul   %d1,%d0               | tenths of a percent
sp10_f:
    movel   %d0,sys_w
    moveq   #10,%d1
    divul   %d1,%d0               | whole
    lea.l   sys_vbuf,%a1
    bsr     sys_dec
    moveb   #46,%a1@+             | '.'
    movel   sys_w,%d0
    movel   %d0,%d1
    moveq   #10,%d0
    divul   %d0,%d1
    mulul   %d0,%d1
    movel   sys_w,%d0
    subl    %d1,%d0               | the tenths digit
    addil   #48,%d0
    moveb   %d0,%a1@+
    moveb   #37,%a1@+             | '%'
    clrb    %a1@
    lea.l   sys_vbuf,%a0
    rts

| sys_left / sys_right (a0 = text, d0 = y; d2 = ctx): a line's label at the
| left edge, or its value against the right. Keep d2-d7.
sys_left:
    moveq   #2,%d1
sys_atl:                          | ...or at x = d1
    movel   %d1,%sp@-             | x
    moveq   #0x10,%d1             | left, cleared behind
    bras    sys_txt
sys_right:
    moveq   #125,%d1
sys_atr:                          | ...or against x = d1
    movel   %d1,%sp@-
    moveq   #0x14,%d1             | right-aligned, cleared behind
sys_txt:
    movel   %sp@+,%a1             | x
    movel   %a0,%sp@-             | the text
    pea     0x40124b58            | "%s"
    movel   %d1,%sp@-             | flags
    negl    %d0                   | the screen counts y from the BOTTOM: a
    addil   #55,%d0               | line 9 px tall whose top is row d0 from
    movel   %d0,%sp@-             | the top sits at 55 - d0 (until samplerHP
                                  | every page drawn here came out upside down)
    movel   %a1,%sp@-             | x
    pea     SYS_FONT
    movel   %d2,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    rts

| sys_bar (d0 = y, d1 = percent; d2 = ctx): an outlined bar 5 px tall across
| the screen, filled that far. Keeps d2-d7.
sys_bar:
    lea.l   %sp@(-8),%sp
    moveml  %d3-%d4,%sp@
    moveq   #59,%d3               | y: rows d0..d0+4 from the top are
    subl    %d0,%d3               | 59-d0..63-d0 from the bottom
    movel   %d1,%d4
    cmpil   #100,%d4
    blss    sb_c
    moveq   #100,%d4
sb_c:
    pea     1                     | the outline: set, then its inside cleared
    movel   %d3,%d0
    addql   #4,%d0
    movel   %d0,%sp@-
    pea     125
    movel   %d3,%sp@-
    pea     2
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    clrl    %sp@-
    movel   %d3,%d0
    addql   #3,%d0
    movel   %d0,%sp@-
    pea     124
    movel   %d3,%d0
    addql   #1,%d0
    movel   %d0,%sp@-
    pea     3
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    moveq   #121,%d0              | the fill: 121 px at 100%
    mulul   %d4,%d0
    moveq   #100,%d1
    divul   %d1,%d0
    tstl    %d0
    beqs    sb_out
    addql   #2,%d0                | its right edge
    pea     1
    movel   %d3,%d1
    addql   #3,%d1
    movel   %d1,%sp@-
    movel   %d0,%sp@-
    movel   %d3,%d1
    addql   #1,%d1
    movel   %d1,%sp@-
    pea     3
    movel   %d2,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
sb_out:
    moveml  %sp@,%d3-%d4
    lea.l   %sp@(8),%sp
    rts

| sys_pctbuf (d0 = percent) -> a0 = "42%" in sys_vbuf. Keeps d2-d7.
sys_pctbuf:
    lea.l   sys_vbuf,%a1
    bsr     sys_dec
    moveb   #37,%a1@+             | '%'
    clrb    %a1@
    lea.l   sys_vbuf,%a0
    rts

| sys_mb (d0 = bytes, a1 = dest) -> a1 past "12.3" (MiB, one decimal).
| Keeps d2-d7.
sys_mb:
    lsrl    #8,%d0
    lsrl    #2,%d0                | KiB
    moveq   #10,%d1
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #2,%d0                | tenths of a MiB
    movel   %d0,sys_t
    divul   %d1,%d0               | whole MiB
    movel   %d0,sys_w
    bsr     sys_dec
    moveb   #46,%a1@+             | '.'
    movel   sys_w,%d0
    moveq   #10,%d1
    mulul   %d1,%d0
    movel   sys_t,%d1
    subl    %d0,%d1               | the tenths
    addil   #48,%d1
    moveb   %d1,%a1@+
    rts

| sys_used -> d0 = bytes the resident slots take. Keeps d1-d7.
sys_used:
    movel   %d2,%sp@-
    moveq   #0,%d0
    moveq   #0,%d2
su_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    su_n
    lea.l   slot_size,%a0
    addl    %a0@(0,%d2:l:4),%d0
su_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    su_l
    movel   %sp@+,%d2
    rts

| sys_dec(d0 = value, a1 = dest) -> a1 past its decimal digits. Clobbers
| d0, d1, a0; keeps d2-d7.
sys_dec:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d3,%sp@          | digits go into sp@(8..19), from the end
    lea.l   %sp@(20),%a0
    moveq   #10,%d2
sy_d:
    movel   %d0,%d3
    divul   %d2,%d3
    movel   %d3,%d1
    mulul   %d2,%d1
    subl    %d1,%d0
    addil   #48,%d0
    moveb   %d0,%a0@-
    movel   %d3,%d0
    bnes    sy_d
    movel   %sp,%d1
    addil   #20,%d1
sy_c:
    moveb   %a0@+,%a1@+
    cmpal   %d1,%a0
    bnes    sy_c
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(20),%sp
    rts

| sys_tick: on the UI clock. While the System page is up, a redraw every
| SYS_REDRAW blocks. Keeps d2-d7.
sys_tick:
    tstl    mm_obj
    beqw    sys_t_out
    moveq   #MM_SLE,%d0           | the slice editor: when a trig key has
    cmpl    mm_kind,%d0           | selected a slice
    bnes    sys_t_ns
    tstl    sle_dirty
    beqs    sys_t_sr
    clrl    sle_dirty
    bras    sys_t_draw
sys_t_sr:
    tstl    sle_run               | ...and while tapping, for the playhead,
    beqs    sys_t_out             | until the sample ends
    jsr     sle_tend
    tstl    %d0
    bnes    sys_t_draw
    movel   #SLE_REDRAW,%d1
    bras    sys_t_k
sys_t_ns:
    movel   #SYS_REDRAW,%d1
    moveq   #MM_SYS,%d0
    cmpl    mm_kind,%d0
    beqs    sys_t_k
    movel   #RTG_REDRAW,%d1       | the retrig page: pads and steps show at once
    moveq   #MM_RTG,%d0
    cmpl    mm_kind,%d0
    bnes    sys_t_out
sys_t_k:
    movel   blk_clk,%d0
    subl    sys_last,%d0
    cmpl    %d1,%d0
    bcss    sys_t_out
    movel   blk_clk,%d0
    movel   %d0,sys_last
sys_t_draw:
    movel   mm_obj,%sp@-          | the page is its own view
    jsr     0x40076082
    addql   #4,%sp
sys_t_out:
    rts

sys_s_row:     .asciz "System"
sys_s_cpu:     .asciz "CPU"
sys_s_peak:    .asciz "PEAK"
sys_s_ram:     .asciz "RAM"
sys_s_free:    .asciz "FREE"
sys_s_trk:     .asciz "TRACKS"
sys_s_oth:     .asciz "OTHER"
sys_s_tot:     .asciz "TOTAL"
sys_lbuf:      .asciz "T1"

    .balign 4
sys_last:      .long 0
sys_pg:        .long 0            | 0 CPU and RAM, 1 the tracks

sys_t:         .long 0
sys_w:         .long 0
sys_vbuf:      .space 24

| ---- the Transfer row in the device config menu ----
| "Device Config" (DeviceSettingsMenuView, constructor 0x40032726: USB mode,
| LCD, LED, Contrast) ends with `moveml %sp@(24),%d2-%d6/%a2-%fp` at
| 0x40032aee, with the menu in a2 - the shape Scale Lock's rows are added in.
| cfg_hook adds one row and resumes. (samplerFK hooked 0x40031be4 instead,
| which is "Battery Config": its label functions sit next to these ones.)
cfg_hook:
    lea.l   %sp@(-16),%sp
    moveml  %d0-%d1/%a0-%a1,%sp@
    pea     id_row
    movel   %a2,%sp@-
    jsr     lm_add_row
    addql   #8,%sp
    pea     sys_row               | and after it, System: the load page
    movel   %a2,%sp@-
    jsr     lm_add_row
    addql   #8,%sp
    moveml  %sp@,%d0-%d1/%a0-%a1
    lea.l   %sp@(16),%sp
    moveml  %sp@(24),%d2-%d6/%a2-%fp
    jmp     0x40032af4

| lm_add_row(menu, row): one list-menu row from {label, value, turn, press},
| built exactly as gran_menu_open builds its rows.
lm_add_row:
    linkw   %fp,#-64
    lea.l   %sp@(-16),%sp
    moveml  %d4/%a3-%a5,%sp@
    movel   %fp@(12),%d4          | row
    lea.l   ALLOC,%a4
    lea.l   %fp@(-64),%a5
    pea     0x1
    jsr     %a4@
    addql   #4,%sp
    movel   %d0,%a5@
    clrl    %a5@(4)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a5@(8)
    movea.l %d4,%a0
    movel   %a0@,%d0
    movel   %d0,%a5@(12)
    pea     0x4
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a0
    movel   %fp@(8),%a0@
    movel   %d0,%a5@(16)
    clrl    %a5@(20)
    movel   #SLOT2_MANAGER,%d0
    movel   %d0,%a5@(24)
    movea.l %d4,%a0
    movel   %a0@(12),%d0
    movel   %d0,%a5@(28)
    pea     0x1
    jsr     %a4@
    addql   #4,%sp
    movel   %d0,%a5@(32)
    clrl    %a5@(36)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a5@(40)
    movea.l %d4,%a0
    movel   %a0@(4),%d0
    movel   %d0,%a5@(44)
    pea     0x4
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a0
    movel   %fp@(8),%a0@
    movel   %d0,%a5@(48)
    clrl    %a5@(52)
    movel   #SLOT2_MANAGER,%d0
    movel   %d0,%a5@(56)
    movea.l %d4,%a0
    movel   %a0@(8),%d0
    movel   %d0,%a5@(60)
    pea     0x54
    jsr     %a4@
    addql   #4,%sp
    movea.l %d0,%a3
    pea     0x8
    pea     -1
    pea     %a5@(48)
    pea     %a5@(32)
    pea     %a5@(16)
    movel   %a5,%sp@-
    movel   %a3,%sp@-
    jsr     MENUITEM_CTOR
    lea.l   %sp@(28),%sp
    movel   %a3,%sp@-
    movel   %fp@(8),%sp@-
    jsr     MENUVIEW_ADDITEM
    addql   #8,%sp
    pea     %a5@(48)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    pea     %a5@(32)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    pea     %a5@(16)
    jsr     FREE_CLOSURE
    addql   #4,%sp
    movel   %a5,%sp@-
    jsr     FREE_CLOSURE
    addql   #4,%sp
    moveml  %sp@,%d4/%a3-%a5
    unlk    %fp
    rts

| ---- SMP: the sample file-system commands, answered by the raw ones ----
| The Cycles firmware parses every command but only HANDLES the raw file-system
| family (0x14.., 0x24.., 0x33.., 0x43..): nothing in it answers the sample
| family a Model:Samples advertises (0x10.., 0x20.., 0x30.., 0x40..), so
| Transfer waited forever. The two families parse identically (0x10 and 0x14
| build the same object from the same fields - 0x400f1c00 / 0x400f2522), so in
| SMP a sample-family request is relabelled to its raw twin on the way in, and
| the raw reply relabelled back on the way out. Transfer never sends the raw
| family in SMP (it is not advertised), so every raw reply then is one of ours.
|   in:  rpc_type replaces the factory's `jsr 0x400949d8` (the type byte, msg
|        +8) at 0x4009249a and rewrites +8 - the request object copies it
|   out: rpc_ot replaces `mvzb %a2@(8),%d0 ; lea %sp@(32),%sp` at 0x40094c9a,
|        where the reply header's type byte is written
| Every incoming type also goes into rpc_log, shown by pressing the Transfer row.
rpc_type:
    movea.l %sp@(4),%a0
    moveq   #0,%d0
    moveb   %a0@(8),%d0
    lea.l   rpc_logn,%a1          | log it: the last 16 types
    movel   %a1@,%d1
    addql   #1,%a1@
    andil   #15,%d1
    lea.l   rpc_log,%a1
    moveb   %d0,%a1@(0,%d1:l)
    tstl    id_mode
    beqs    rt3_out
    moveq   #9,%d1                | Query: see qry_take
    cmpl    %d1,%d0
    beqw    qry_take
    lea.l   rpc_map,%a1           | pairs: sample type, raw type; 0 ends
rt3_l:
    moveq   #0,%d1
    moveb   %a1@,%d1
    beqs    rt3_out
    cmpl    %d1,%d0
    beqs    rt3_hit
    addql   #2,%a1
    bras    rt3_l
rt3_hit:
    moveb   %a1@(1),%d0
    moveb   %d0,%a0@(8)
rt3_out:
    rts

| ---- SMP: Transfer's stereo question (Query, message 9) -------------------
| Transfer (1.9.5, statically: see findings) asks a device that lists both 9
| and 0x10 for "sample_file.interleaved_stereo_support" - message 9, the key
| and a NUL - and sends stereo files only if the reply, message 0x89, starts
| with 01 01 (kind 1 = bool, true). Any other kind for any other key is taken
| as "no value" (its chunk-size question then falls back to the legacy size).
| The Cycles has no Query class at all, so the request is answered by one it
| does have: it is relabelled SoftwareVersion (2), whose reply the dispatcher
| builds anyway, and rpc_ot sends that reply as 0x89 with our payload instead.
| Transfer waits for each answer before asking anything else, so the next 0x82
| reply is always this one. The message keeps a 5-byte header ahead of its
| payload in the vector at +12/+16 (0x400949e2: payload = end - begin - 5).
qry_take:                         | a0 = message, d0 = 9
    movel   %a2,%sp@-
    movea.l %a0@(12),%a1
    movel   %a0@(16),%d1
    subl    %a1,%d1
    subql   #5,%d1                | payload bytes
    addql   #5,%a1
    lea.l   qry_stereo,%a2
    moveq   #1,%d0                | "no value" unless the key matches
qt_l:
    tstl    %d1
    beqs    qt_end                | payload over: a match only at the NUL
    moveb   %a1@+,%d0
    cmpb    %a2@+,%d0
    bnes    qt_nomatch
    tstb    %d0
    beqs    qt_yes
    subql   #1,%d1
    bras    qt_l
qt_end:
    tstb    %a2@
    bnes    qt_nomatch
qt_yes:
    moveq   #2,%d0                | stereo: 01 01
    bras    qt_set
qt_nomatch:
    moveq   #1,%d0                | anything else: 00
qt_set:
    movel   %d0,qry_pend
    movea.l %sp@+,%a2
    moveq   #2,%d0                | answered as a SoftwareVersion request
    moveb   %d0,%a0@(8)
    rts

rpc_ot:
    moveq   #0,%d0
    moveb   %a2@(8),%d0
    tstl    id_mode
    beqs    ro3_out
    tstl    qry_pend
    beqs    ro3_nq
    cmpil   #0x82,%d0
    bnes    ro3_nq
    | The Query's answer: type 0x89, and the payload - the serializer's fifth
    | argument, sp@(48) once the 32 bytes of its header calls are dropped, d3
    | bytes long - swapped for ours.
    movel   qry_pend,%d1
    clrl    qry_pend
    lea.l   %sp@(32),%sp
    lea.l   qry_yes,%a0
    moveq   #2,%d3
    subql   #2,%d1
    beqs    ro3_qp
    lea.l   qry_none,%a0
    moveq   #1,%d3
ro3_qp:
    movel   %a0,%sp@(48)
    movel   #0x89,%d0
    jmp     0x40094ca2
ro3_nq:
    lea.l   rpc_map,%a1           | a raw reply (request | 0x80) back to the
ro3_l:                            | sample family's
    moveq   #0,%d1
    moveb   %a1@(1),%d1
    beqs    ro3_out
    bset    #7,%d1
    cmpl    %d1,%d0
    beqs    ro3_hit
    addql   #2,%a1
    bras    ro3_l
ro3_hit:
    moveb   %a1@,%d0
    bset    #7,%d0
ro3_out:
    lea.l   %sp@(32),%sp
    jmp     0x40094ca2

| the Transfer row's press: edit as usual, and in SMP show the command log
id_press:
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    jsr     new_slot2_invoker
    addql   #8,%sp
    rts                           | the load is on its own page now (System)
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    moveq   #10,%d0               | SMP: then "RX" and the last 12 types
    moveb   %d0,%a1@+
    moveq   #82,%d0
    moveb   %d0,%a1@+
    moveq   #88,%d0
    moveb   %d0,%a1@+
    movel   rpc_logn,%d2
    subil   #10,%d2
    moveq   #0,%d3
ip_l:
    movel   %d2,%d4
    andil   #15,%d4
    lea.l   rpc_log,%a0
    moveq   #0,%d1
    moveb   %a0@(0,%d4:l),%d1
    moveq   #32,%d0               | a space, or a new line every 4
    movel   %d3,%d4
    andil   #3,%d4
    bnes    ip_sep
    moveq   #10,%d0
ip_sep:
    moveb   %d0,%a1@+
    movel   %d1,%d0
    lsrl    #4,%d0
    bsr     ip_hex
    movel   %d1,%d0
    bsr     ip_hex
    addql   #1,%d2
    addql   #1,%d3
    cmpil   #10,%d3
    bcss    ip_l
    clrb    %a1@
    pea     msg_buf
    jsr     show_popup
    addql   #4,%sp
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
ip_out:
    rts
ip_hex:
    andil   #15,%d0
    cmpil   #10,%d0
    bcss    ih3_d
    addql   #7,%d0
ih3_d:
    addil   #48,%d0
    moveb   %d0,%a1@+
    rts

    .align 4
qry_pend:     .long 0          | a Query's answer waits: 2 stereo, 1 none
qry_stereo:   .asciz "sample_file.interleaved_stereo_support"
qry_yes:      .byte 1, 1       | kind 1 (bool), true
qry_none:     .byte 0          | kind 0: no value
    .align 4
rpc_logn:     .long 0
rpc_log:      .space 16
| sample-family type, raw twin (the factory switch at 0x4009247c, both images)
rpc_map:      .byte 0x10,0x14, 0x11,0x15, 0x12,0x16
              .byte 0x20,0x24, 0x21,0x25, 0x22,0x26, 0x23,0x27
              .byte 0x30,0x33, 0x31,0x34, 0x32,0x35, 0x36,0x37
              .byte 0x40,0x43, 0x41,0x44, 0x42,0x45, 0x46,0x47
              .byte 0, 0
    .align 4

id_lab:
    lea.l   id_s_lab,%a1
    braw    gm_lab
id_val:
    lea.l   id_mode,%a0
    lea.l   id_names,%a1
    braw    gm_val
| turn (closure, item, delta): right = SMP, left = CYC, then redraw the menu -
| the list's own handler does not redraw a row being edited, and this menu
| has no observer to do it. The closure's data word holds the menu.
id_rot:
    movel   %sp@(12),%d0
    beqs    ir_out
    moveq   #1,%d1
    tstl    %d0
    bgts    ir_set
    moveq   #0,%d1
ir_set:
    lea.l   id_mode,%a1
    movel   %d1,%a1@
    movea.l %sp@(4),%a0           | the closure -> its data -> the menu
    movea.l %a0@,%a0
    movel   %a0@,%d0
    beqs    ir_out
    addil   #0x38,%d0             | the menu's view
    movel   %d0,%sp@-
    jsr     0x40076082
    addql   #4,%sp
ir_out:
    rts

    .align 4
id_mode:      .long 0          | 0 = CYC, 1 = SMP; every boot starts at CYC
id_row:       .long id_lab, id_val, id_rot, id_press
id_names:     .long id_s_cyc, id_s_smp
id_namebuf:   .space 16        | the name the next identity reply carries
id_smp_list:  .byte 0x01,0x02,0x03,0x05,0x04,0x50,0x52,0x51,0x10,0x13,0x11,0x12
              .byte 0x20,0x21,0x22,0x23,0x30,0x31,0x32,0x36,0x40,0x41,0x42,0x46
              .byte 0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,0x5b,0x5c,0x5d
              .byte 0x09          | ours: Query, so Transfer asks about stereo
id_s_lab:     .asciz "Transfer"
id_s_cyc:     .asciz "CYC"
id_s_smp:     .asciz "SMP"
id_n_cyc:     .asciz "Model Cycles"
id_n_smp:     .asciz "Model Samples"
    .align 4

| ================ Quick mute: queue the pads, apply on closing ===============
| The latching-mute tweak keeps QuickMuteMenuView (vtable 0x40100c3c) open
| until FUNC is tapped again; stock, each pad in it toggles its track's mute at
| once (0x4002350a -> 0x40013904(kit, track, 1) at 0x40023550). Now a pad only
| flips a pending bit, the pad LEDs show the state it will have (the painter's
| mute query, `lea 0x4001263c,%a4` at 0x400233bc, answers muted XOR pending),
| and the whole set is applied - through the same stock toggle, CC and all -
| when the view closes: in the tweak's FUNC close (its three nops at
| 0x40148696, just before vtable[0x28]) and, for any other way out, in the
| view's destructors (vtable slots 0 and 1), before they run.
| mq_toggle(kit, track, send): flip it, and re-set the track's CURRENT state
| through 0x4001381c without a CC - no change, but its observers repaint.
mq_toggle:
    movel   %sp@(8),%d0
    cmpil   #MAX_TRK,%d0
    bccs    mqt_out
    lea.l   mq_pending,%a0
    movel   %a0@,%d1
    bchg    %d0,%d1
    movel   %d1,%a0@
    movel   %d2,%sp@-
    movel   %sp@(12),%d2          | track (kit is at 8)
    movel   %d2,%sp@-
    movel   %sp@(12),%sp@-
    jsr     0x4001263c            | muted now?
    addql   #8,%sp
    andil   #0xff,%d0
    sne     %d0
    andil   #1,%d0
    clrl    %sp@-                 | no CC: nothing is changing yet
    movel   %d0,%sp@-
    movel   %d2,%sp@-
    movel   %sp@(20),%sp@-        | kit
    jsr     0x4001381c
    lea.l   %sp@(16),%sp
    movel   %sp@+,%d2
mqt_out:
    rts

| (kit, track): what the pad should show - muted, flipped if pending
mq_muted:
    movel   %sp@(8),%sp@-         | track
    movel   %sp@(8),%sp@-         | kit
    jsr     0x4001263c
    addql   #8,%sp
    andil   #0xff,%d0
    sne     %d0
    andil   #1,%d0                | 1 = muted
    movel   %d2,%sp@-
    movel   %sp@(12),%d1          | track
    movel   mq_pending,%d2
    btst    %d1,%d2
    beqs    mqm_out
    eoril   #1,%d0                | about to flip
mqm_out:
    movel   %sp@+,%d2
    rts

mq_apply:
    tstl    mq_pending
    beqs    mqa_ret
    lea.l   %sp@(-16),%sp
    moveml  %d0-%d2/%a0,%sp@
    moveq   #0,%d2
mqa_l:
    movel   mq_pending,%d0
    btst    %d2,%d0
    beqs    mqa_n
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    addql   #4,%sp
    pea     1                     | with the CC, as the stock pad did
    movel   %d2,%sp@-
    movel   %d0,%sp@-
    jsr     0x40013904            | toggle
    lea.l   %sp@(12),%sp
mqa_n:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    mqa_l
    lea.l   mq_pending,%a0
    clrl    %a0@
    moveml  %sp@,%d0-%d2/%a0
    lea.l   %sp@(16),%sp
mqa_ret:
    rts

mq_dtor0:
    bsr     mq_apply
    jmp     0x400d8f8c
mq_dtor1:
    bsr     mq_apply
    jmp     0x400d9030

    .align 4
mq_pending:   .long 0          | tracks whose mute flips when mute mode closes

| ============================ RESAMPLING ===================================
| Step 1: the capture core. A recording goes into the free sample space above
| alloc_top, laid out like a loaded file (64-byte header, then big-endian
| 16-bit mono at 48 kHz), so once committed it is an ordinary slot and every
| mode plays it. Its slot hash is RS_HASH | n: resident only, never on disk.
|   whole output: rs_out wraps `jsr 0x400567ba` at 0x40059872, the call that
|     writes the final mix - 32 stereo frames, 24-bit in 32, L/R interleaved -
|     to the output ring; L+R summed to mono after it has run
|   one track, dry: rs_trk from amp_hook - after the amp envelope, Attack and
|     the stock machines' Filter; before pan, volume and the effect sends
| The audio side only appends while rs_state = 1. Stopping is rs_state = 0
| (by the key, or by the audio side when the space runs out); rs_watch, on the
| UI clock, then commits: normalise, take a slot, hand it to the destination.
RS_HASH = 0x524d0000             | "RM" + 00 + n: a resident-only recording
RS_MST  = 6                      | source: the whole output (0..5 = a track)
RS_USB  = 7                      | source: the computer's audio over USB
| USB audio in (USB mode A+M: UAC2, stereo, 32-bit PCM on iso endpoint 3): the
| render interrupt reads each block's 32 frames with 0x40002ae0(USB_IN, 32) at
| 0x40059338, byte-swapped to 32 x {L, R} int32, full scale 2^31, silence when
| nothing arrives - the master bus's layout, so rs_out captures it as it does
| the bus, at unity: (L + R) / 2 >> 16.
USB_IN  = 0x40fe4cf0
RS_REC  = 1                      | rs_state: capturing
RS_PAT  = 2                      | ...armed for the top of the pattern
RS_SND  = 3                      | ...armed for the source's first sound
RS_THR  = 328                    | first sound: -40 dBFS on the 16-bit scale
RS_PAT2 = 4                      | ...PAT: step 1 scheduled, waiting to hear it
RS_EARLY = 256                   | a bar take goes on its track this many
                                 | samples before its end (8 blocks, ~5 ms)
RS_BUS  = 0x8000b990             | master bus, 32 x {L, R}, after 0x400565c6's
                                 | x4 and before the output stage (X scaling,
                                 | USB input) - read by rs_out after 0x400567ba
| The replay path of a Sample track, measured (samplerFP, hardware): output =
| take x avg mixer gain x 2^(X-3) x 3.1. From the bus X drops out, leaving
| gain x 3.1, so a take is captured with 1 / (gain x 3.1): 2^23 / 3.1 = 2706000
| over the gain in Q15 gives Q8.
RS_KQ8  = 2706000
| Corrected (samplerFR, level ratio, alignment-proof): bus = take x 0.382 x
| mixer gain - the Sample track's own chain (decimator and the stages before
| the amp) is 0.382, not the unity assumed; the output-level setting does not
| enter (output tap / bus = 1.000). A take at the bus's own level therefore
| needs 1 / (0.382 x gain) of playback gain - up to 6x or more, which 16 bits
| cannot hold. So takes are captured at unity and carry that gain with them,
| applied in 32 bits after the amp stage (amp_hook).
RS_PMST = 351340000              | 4096 x 32768 / 0.382: over the gain (Q15)
RS_PTRK = 10723                  | 4096 / 0.382, Q12

| (buf, track) from amp_hook, after the stock stage, Attack and the filter
rs_trk:
    lea.l   rs_state,%a0
    tstl    %a0@
    beqw    rt2_out
    movel   %sp@(8),%d0
    cmpl    rs_src,%d0
    bnew    rt2_out
    moveq   #RS_PAT2,%d0          | PAT: is step 1 heard in this block?
    cmpl    %a0@,%d0
    bnes    rt2_np
    bsr     rs_patchk
rt2_np:
    moveq   #RS_SND,%d0           | armed for the first sound: this block?
    cmpl    %a0@,%d0
    bnes    rt2_rec
    movea.l %sp@(4),%a1
    moveq   #31,%d1
rt2_th:
    movel   %a1@+,%d0
    asrl    #8,%d0
    asrl    #8,%d0
    bpls    rt2_ta
    negl    %d0
rt2_ta:
    cmpil   #RS_THR,%d0
    bgts    rt2_go
    subql   #1,%d1
    bpls    rt2_th
    rts                           | not yet
rt2_go:
    moveq   #RS_REC,%d0
    movel   %d0,%a0@
rt2_rec:
    moveq   #RS_REC,%d0
    cmpl    %a0@,%d0
    bnew    rt2_out               | armed for the pattern: rs_out starts it
    movel   rs_soff,%d0           | a stereo take: the side first, from what
    beqs    rt2_m                 | the side pass kept (silence if this block
    movel   %d2,%sp@-             | rendered in mono)
    movea.l rs_ptr,%a1
    adda.l  %d0,%a1
    lea.l   sx_cap,%a0
    movel   rs_gain,%d1
    moveq   #31,%d2
rt2_sl:
    moveq   #0,%d0
    tstl    sx_ok
    beqs    rt2_sz
    movel   %a0@,%d0
    asrl    #8,%d0
    asrl    #7,%d0
    mulsl   %d1,%d0
    asrl    #8,%d0
    cmpil   #32767,%d0
    bles    rt2_sh
    movel   #32767,%d0
rt2_sh:
    cmpil   #-32767,%d0
    bges    rt2_sz
    movel   #-32767,%d0
rt2_sz:
    movew   %d0,%a1@+
    addql   #4,%a0
    subql   #1,%d2
    bpls    rt2_sl
    movel   %sp@+,%d2
rt2_m:
    movel   %d2,%sp@-
    movea.l %sp@(8),%a0           | buf: 32 longs
    movea.l rs_ptr,%a1
    movel   rs_gain,%d1
    moveq   #31,%d2
rt2_l:
    movel   %a0@+,%d0
    asrl    #8,%d0
    asrl    #7,%d0                | >>15: what the Sampler's <<15 undoes
    mulsl   %d1,%d0               | the trim, Q8 (rs_gain)
    asrl    #8,%d0
    cmpil   #32767,%d0
    bles    rt2_h
    movel   #32767,%d0
rt2_h:
    cmpil   #-32767,%d0
    bges    rt2_w
    movel   #-32767,%d0
rt2_w:
    movew   %d0,%a1@+
    subql   #1,%d2
    bpls    rt2_l
    movel   %sp@+,%d2
    braw    rs_adv
rt2_out:
    rts

| replaces `jsr 0x400567ba` at 0x40059872: (out, state). Runs the output stage,
| then takes its 32 frames when recording the whole output.
rs_out:
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    jsr     0x400567ba
    addql   #8,%sp
    addql   #1,blk_clk            | wall time, in blocks (1500 a second)
    bsr     prof_end              | the block is rendered: how long did it take
    lea.l   rs_state,%a0
    movel   %a0@,%d0
    beqw    ro_out
    cmpil   #RS_PAT,%d0
    bnes    ro_npat
    | Armed for the pattern: the sequencer's step counter (0x40a78840, the
    | next step, wrapped to 0 after the last) becomes 1 when step 1 plays -
    | at the top of the pattern, or when play is pressed. Capture from the
    | next block, for every source alike.
    movel   0x40a78840,%d0        | now
    movel   rs_prev,%d1           | last block
    lea.l   rs_prev,%a1
    movel   %d0,%a1@
    cmpil   #1,%d0
    bnew    ro_out
    cmpil   #1,%d1
    beqw    ro_out                | was already 1: not the moment it changed
    moveq   #1,%d1
    cmpl    0x40a7883c,%d1        | playing
    bnew    ro_out
    | The sequencer runs a tick ahead of the audio: this tick has just
    | scheduled step 1 for its own time, 0x40a78628, which the audio clock
    | (0x8000184c) reaches a tick from now. Capture from THAT block.
    movel   0x40a78628,%d0
    lea.l   rs_T,%a1
    movel   %d0,%a1@
    moveq   #RS_PAT2,%d0
    movel   %d0,%a0@
    braw    ro_out
ro_npat:
    cmpil   #RS_PAT2,%d0
    bnes    ro_np2
    bsr     rs_patchk
    movel   rs_state,%d0
    cmpil   #RS_REC,%d0
    bnew    ro_out
ro_np2:
    lea.l   RS_BUS,%a1            | the whole output: the master bus
    movel   %a1,ro_srcp
    moveq   #RS_MST,%d1
    cmpl    rs_src,%d1
    beqs    ro_mst
    moveq   #RS_USB,%d1           | the computer's audio
    cmpl    rs_src,%d1
    bnew    ro_out
    lea.l   USB_IN,%a1
    movel   %a1,ro_srcp
ro_mst:
    cmpil   #RS_SND,%d0
    bnes    ro_rec
    movea.l %sp@(4),%a1           | armed for the first sound, whole output
    moveq   #RS_USB,%d1
    cmpl    rs_src,%d1
    bnes    ro_thm
    movea.l #USB_IN,%a1           | ...or the computer's
ro_thm:
    moveq   #31,%d1
ro_th:
    movel   %a1@+,%d0
    addl    %a1@+,%d0
    asrl    #8,%d0
    asrl    #1,%d0
    bpls    ro_ta
    negl    %d0
ro_ta:
    cmpil   #RS_THR,%d0
    bgts    ro_go
    subql   #1,%d1
    bpls    ro_th
    rts
ro_go:
    moveq   #RS_REC,%d0
    movel   %d0,%a0@
ro_rec:
    movel   rs_soff,%d0
    bnew    ro_st
    movel   %d2,%sp@-
    movel   %d3,%sp@-
    movea.l ro_srcp,%a0           | the master bus, before the output stage,
    movea.l rs_ptr,%a1            | or USB_IN
    movel   rs_gain,%d1
    moveq   #31,%d2
ro_l:
    movel   %a0@+,%d0
    asrl    #1,%d0
    movel   %a0@+,%d3
    asrl    #1,%d3
    addl    %d3,%d0               | (L + R) / 2, 32-bit bus scale
    asrl    #8,%d0
    asrl    #4,%d0
    mulsl   %d1,%d0               | make-up for the replay path, Q8 (rs_gain)
    asrl    #8,%d0
    asrl    #4,%d0                | bus >> 16, times the gain
    cmpil   #32767,%d0
    bles    ro_h
    movel   #32767,%d0
ro_h:
    cmpil   #-32767,%d0
    bges    ro_w
    movel   #-32767,%d0
ro_w:
    movew   %d0,%a1@+
    subql   #1,%d2
    bpls    ro_l
    movel   %sp@+,%d3
    movel   %sp@+,%d2
    braw    rs_adv
ro_out:
    rts
| stereo: the mid (L+R)/2 at rs_ptr, the side (L-R)/2 rs_soff above it
ro_st:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    movea.l ro_srcp,%a0
    movea.l rs_ptr,%a1
    movea.l %a1,%a2
    adda.l  %d0,%a2
    movel   rs_gain,%d1
    moveq   #31,%d2
ro_sl:
    movel   %a0@+,%d0
    asrl    #1,%d0                | L / 2
    movel   %a0@+,%d3
    asrl    #1,%d3                | R / 2
    movel   %d0,%d4
    subl    %d3,%d4               | side
    addl    %d3,%d0               | mid
    bsr     ro_q
    movew   %d0,%a1@+
    movel   %d4,%d0
    bsr     ro_q
    movew   %d0,%a2@+
    subql   #1,%d2
    bpls    ro_sl
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    braw    rs_adv
| d0 (bus scale) -> 16 bits, times rs_gain (d1): as ro_l does it
ro_q:
    asrl    #8,%d0
    asrl    #4,%d0
    mulsl   %d1,%d0
    asrl    #8,%d0
    asrl    #4,%d0
    cmpil   #32767,%d0
    bles    roq_h
    movel   #32767,%d0
roq_h:
    cmpil   #-32767,%d0
    bges    roq_w
    movel   #-32767,%d0
roq_w:
    rts

| ============================ STEREO AT THE MIXER ==========================
| Every track reaches the mixer as one channel of 0x80001858 (8 x 32 longs:
| tracks 0-5, then the delay and reverb returns). The main mix 0x40056610 runs
| twice - into bus L (0x8000b990) with the L gains, then bus R (0x8000b994)
| with the R gains - and the stock code already rewrites the two FX channels
| between the passes, from their left outputs to their right. A stereo Sampler
| track does the same: its channel holds the mid, which is what the sends read
| (0x40056716, earlier), and sx_side the side, through the same chain.
|   sx_gain  wraps `jsr 0x40056d9c` at 0x4005982a: that per-track gain (from
|            0x40fe4c90) scales every track channel in place; the sides get it
|            too, laid out the same way
|   sx_mix   is 0x40056610's entry: before the L pass a stereo track's channel
|            becomes mid + side and its side mid - side (= R); before the R
|            pass the channel becomes that R, and the track is done
| Pan then balances L against R. Nothing reads the track channels after the
| main mix.
sx_gain:
    jsr     rtg_audio             | retrig: record, and repeat, before the mix
    lea.l   sx_on,%a0
    movel   %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@+,%d0
    orl     %a0@,%d0
    beqs    sxg_out
    pea     sx_side
    jsr     0x40056d9c
    addql   #4,%sp
sxg_out:
    jmp     0x40056d9c

sx_mix:                           | (bus, channels, gains, steps)
    movel   %sp@(4),%d0
    cmpil   #0x8000b990,%d0
    beqs    sxm_l
    cmpil   #0x8000b994,%d0
    beqw    sxm_r
sxm_go:
    lea.l   %sp@(-40),%sp         | 0x40056610's own first two instructions
    moveml  %d2-%d7/%a2-%a5,%sp@
    jmp     0x40056618
sxm_l:
    moveq   #0,%d0                | retrig: the returns as the L pass hears them
    jsr     rtg_fxpass
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    lea.l   sx_on,%a0             | for the profile: stereo tracks this block
    moveq   #0,%d1
    moveq   #5,%d2
sxl_c:
    tstl    %a0@+
    beqs    sxl_c0
    addql   #1,%d1
sxl_c0:
    subql   #1,%d2
    bpls    sxl_c
    movel   %d1,prof_st
    moveq   #0,%d2
sxl_t:
    lea.l   sx_on,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sxl_n
    movel   %d2,%d0
    lsll    #7,%d0
    movea.l %d0,%a1
    movea.l %d0,%a2
    adda.l  #0x80001858,%a1
    adda.l  #sx_side,%a2
    moveq   #31,%d3
sxl_s:
    movel   %a1@,%d0              | mid
    movel   %d0,%d1
    movel   %a2@,%d4              | side
    addl    %d4,%d0
    satsl   %d0                   | L
    subl    %d4,%d1
    satsl   %d1                   | R
    movel   %d0,%a1@+
    movel   %d1,%a2@+
    subql   #1,%d3
    bpls    sxl_s
sxl_n:
    addql   #1,%d2
    moveq   #MAX_TRK,%d0
    cmpl    %d0,%d2
    bcss    sxl_t
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    braw    sxm_go
sxm_r:
    moveq   #1,%d0                | ...and the R pass
    jsr     rtg_fxpass
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    moveq   #0,%d2
sxr_t:
    lea.l   sx_on,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    sxr_n
    clrl    %a0@(0,%d2:l:4)       | done: the render sets it again next block
    movel   %d2,%d0
    lsll    #7,%d0
    movea.l %d0,%a1
    movea.l %d0,%a0
    adda.l  #0x80001858,%a1
    adda.l  #sx_side,%a0
    moveq   #31,%d3
sxr_s:
    movel   %a0@+,%a1@+
    subql   #1,%d3
    bpls    sxr_s
sxr_n:
    addql   #1,%d2
    moveq   #MAX_TRK,%d0
    cmpl    %d0,%d2
    bcss    sxr_t
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    braw    sxm_go

| ================== stock machines: three cheaper routines ==================
| Found by reading the Kick's render (0x400aa3c4); each replaces a stock
| routine through a jmp at its entry (build_from_stock.py asserts the bytes).
|
| kick_mix - 0x400a9884, the 2-input gain-ramped mixer that Kick, Snare, Metal
| and Perc all use. Its first loop (0x400a98c4-0x400a9902) writes all 32
| outputs, stepping both gains one step a sample, and its second loop then
| overwrites all 32 from the same inputs (the outputs never alias them). The
| first loop's only lasting effect is that the gains have moved 32 steps and
| acc0 is clear: done here directly, bit-exact, then on into the second loop.
| a0 = gain records, a1 = their two indices, d3/d4 = the two steps.
kick_mix:
    movel   %a1@,%d1
    movel   %d3,%d2
    asll    #5,%d2
    addl    %d2,%a0@(24,%d1:l:4)  | current gain 0 += 32 steps
    movel   %a1@(4),%d1
    movel   %d4,%d2
    asll    #5,%d2
    addl    %d2,%a0@(24,%d1:l:4)  | current gain 1 += 32 steps
    movclrl %acc0,%d0             | acc0 clear, as the old loop left it
    jmp     0x400a9904

| kick_click(buf, voice) - 0x400a9daa, the Kick's click: a ramp from full scale
| falling 4483264 a sample (silent after ~10 ms) times a gain-ramped level,
| then two one-pole filters (0x400a9d4e, states at *(voice+712) and
| *(voice+716), +12 last in and +16 last out). The ramp now runs in registers
| (bit-exact: x >= 0, so the stock satsl never acts). Once it is over, the
| stock chain still ran - ramp, both filters, for the rest of the note - on
| zeros: now the output is zeros, and the filters run only while their
| states still ring; once all four are within SIL_LVL (2 LSB of 16-bit, the
| level idle detection already calls silence) they are zeroed and skipped.
| The MAC truncates toward -infinity, so a pole p just under 1 leaves a
| negative tail stuck at up to ~1/(1-p) LSB forever - samplerHS's +-2 LSB
| almost never caught it. The flush is the one difference from stock: a
| constant under -90 dBFS removed.
kick_click:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d4/%a2-%a3,%sp@
    movea.l %sp@(28),%a2          | voice
    movea.l %sp@(24),%a3          | buf
    tstl    %a2@(56)              | a trigger: the ramp from the top
    beqs    kk_nt
    movel   #0x7fffffff,%d1
    movel   %d1,%a2@(720)
kk_nt:
    movel   %a2@(720),%d1         | x
    movel   %a2@(728),%d3         | level
    movel   %a2@(724),%d2         | target
    movel   %d2,%a2@(728)         | where the level ends, as stock
    subl    %d3,%d2
    asrl    #5,%d2                | its step
    tstl    %d1
    beqs    kk_quiet
    moveq   #32,%d0
    movel   #4483264,%d4
kk_l:
    macl    %d3,%d1,%acc0         | level x x
    movclrl %acc0,%a0
    movel   %a0,%a3@+
    subl    %d4,%d1
    bpls    kk_x
    moveq   #0,%d1
kk_x:
    addl    %d2,%d3
    subql   #1,%d0
    bnes    kk_l
    movel   %d1,%a2@(720)
    lea.l   %a3@(-128),%a3
    bras    kk_filt
kk_quiet:
    movclrl %acc0,%d0             | acc0 clear, as the ramp would leave it
    movea.l %a3,%a0
    moveq   #31,%d0
kk_z:
    movel   %d1,%a0@+             | d1 = 0: the ramp's silence
    subql   #1,%d0
    bpls    kk_z
    movea.l %a2@(712),%a0         | still ringing?
    movea.l %a2@(716),%a1
    movel   %a0@(12),%d0
    bsr     kk_tiny
    bhis    kk_filt
    movel   %a0@(16),%d0
    bsr     kk_tiny
    bhis    kk_filt
    movel   %a1@(12),%d0
    bsr     kk_tiny
    bhis    kk_filt
    movel   %a1@(16),%d0
    bsr     kk_tiny
    bhis    kk_filt
    clrl    %a0@(12)              | rung out: flushed, and skipped
    clrl    %a0@(16)
    clrl    %a1@(12)
    clrl    %a1@(16)
    bras    kk_out
kk_filt:
    movel   %a2@(712),%sp@-
    movel   %a3,%sp@-
    jsr     0x400a9d4e
    movel   %a2@(716),%sp@(4)     | its arguments are left as they were
    jsr     0x400a9d4e
    addql   #8,%sp
kk_out:
    moveml  %sp@,%d2-%d4/%a2-%a3
    lea.l   %sp@(20),%sp
    rts
| d0 -> flags "hi" when |d0| > SIL_LVL
kk_tiny:
    addil   #SIL_LVL,%d0
    cmpil   #2*SIL_LVL,%d0
    rts

| kick_sum(a, b, out) - 0x400a956c, out = sat(b + a), 32 longs: the same
| order of reads and the same saturation, post-increment instead of indexed.
kick_sum:
    movel   %a2,%sp@-
    movea.l %sp@(8),%a1
    movea.l %sp@(12),%a2
    movea.l %sp@(16),%a0
    moveq   #32,%d0
ksm_l:
    movel   %a2@+,%d1
    addl    %a1@+,%d1
    satsl   %d1
    movel   %d1,%a0@+
    subql   #1,%d0
    bnes    ksm_l
    movea.l %sp@+,%a2
    rts

| chord_osc - the Chord's oscillator 0x400a8722 (only Chord calls it; four
| voices a block), entered at 0x400a8906 once its setup has put everything on
| the stack. Each voice blends two adjacent wavetables, (1-m) and m, each read
| with linear interpolation, then scales by a ramped amplitude. The stock loop
| also adds two phase-modulation inputs every sample, whose depths Chord never
| sets (the machine change 0x400a7ab8 zeroes them; its parameter function
| never writes them) - exact zeros - and keeps pointers, weights and ramps on
| the stack and in SRAM scratch, re-read every sample. Here: no PM, everything
| in registers, and when the second table's weight is 0 and not ramping (the
| waveform control exactly on a table) that table is not read at all. The
| same MAC operations in the same order: bit-exact. With any PM depth or ramp
| set it falls back to the stock loop.
| On entry: d7 phase, d1 amplitude, d4/fp PM depths, a0 scaled out, a3 raw
| out; sp@(68)/(72) tables, (80) phase step, (84) amplitude step, (100)/(104)
| PM ramps, (108)/(112) weights, (116)/(120) their ramps.
chord_osc:
    tstl    %d4
    bnew    co_stock
    movel   %fp,%d0
    bnew    co_stock
    tstl    %sp@(100)
    bnew    co_stock
    tstl    %sp@(104)
    bnew    co_stock
    movea.l %sp@(68),%a1          | table A, weight d4
    movea.l %sp@(72),%a2          | table B, weight d5
    movel   %sp@(108),%d4
    movel   %sp@(112),%d5
    movea.l %sp@(80),%a4          | phase step
    movea.l %sp@(84),%fp          | amplitude step
    moveq   #32,%d0
    tstl    %d5
    bnes    co_two
    tstl    %sp@(120)
    beqw    co_one
co_two:
    movel   %d7,%d2               | index: phase bits 16-23
    andil   #0xffffff,%d2
    swap    %d2
    mvzw    %d2,%d2
    mvzw    %d7,%d6               | fraction: bits 0-15, << 15
    lsll    #8,%d6
    lsll    #7,%d6
    movel   %a1@(0,%d2:l:4),%d3   | A = a0 + f (a1 - a0)
    movea.l %a1@(4,%d2:l:4),%a5
    movel   %d3,%acc0
    macl    %d6,%a5,%acc0
    msacl   %d6,%d3,%acc0
    movel   %a2@(0,%d2:l:4),%d3   | B, likewise
    movea.l %a2@(4,%d2:l:4),%a5
    movel   %d3,%acc2
    macl    %d6,%a5,%acc2
    msacl   %d6,%d3,%acc2
    movclrl %acc0,%d6             | A wA + B wB
    macl    %d4,%d6,%acc0
    movclrl %acc2,%d3
    macl    %d5,%d3,%acc0
    addl    %sp@(116),%d4
    addl    %sp@(120),%d5
    addl    %a4,%d7
    andil   #0xffffff,%d7
    movclrl %acc0,%d6             | the sample, raw; then x -amplitude
    msacl   %d1,%d6,%acc0
    addl    %fp,%d1
    movel   %d6,%a3@+
    movclrl %acc0,%d6
    movel   %d6,%a0@+
    subql   #1,%d0
    bnew    co_two
    jmp     0x400a89d4
co_one:                           | table B weighs nothing: A alone
    movel   %d7,%d2
    andil   #0xffffff,%d2
    swap    %d2
    mvzw    %d2,%d2
    mvzw    %d7,%d6
    lsll    #8,%d6
    lsll    #7,%d6
    movel   %a1@(0,%d2:l:4),%d3
    movea.l %a1@(4,%d2:l:4),%a5
    movel   %d3,%acc0
    macl    %d6,%a5,%acc0
    msacl   %d6,%d3,%acc0
    movclrl %acc0,%d6
    macl    %d4,%d6,%acc0
    addl    %sp@(116),%d4
    addl    %a4,%d7
    andil   #0xffffff,%d7
    movclrl %acc0,%d6
    msacl   %d1,%d6,%acc0
    addl    %fp,%d1
    movel   %d6,%a3@+
    movclrl %acc0,%d6
    movel   %d6,%a0@+
    subql   #1,%d0
    bnes    co_one
    jmp     0x400a89d4
co_stock:
    movea.l #0x8000caa8,%a4       | the instruction the jmp replaced
    jmp     0x400a890c

| ============================ AUDIO LOAD PROFILE ==========================
| The render is one interrupt a block (32 samples, ~667 us): 0x40058c5e, on
| vector 0x400002fc. isr_prof is installed there instead (0x40059670) and
| stamps DTIM2's free-running counter (0xfc07800c - the stock sequencer
| interrupt 0x400589c0 stamps the same one) before jumping to it; prof_end,
| from rs_out once the final mix is written, stamps it again. Busy time over
| the time between block starts is the share of the CPU the audio takes -
| independent of the timer's rate. Also the worst single block, and how many
| tracks were stereo. Shown by pressing the Transfer row (id_press).
FX_SETUP  = 0x4005802e
FX_VOICES = 0x400a7d4a
isr_prof:
    movel   %d0,%sp@-
    movel   0xfc07800c,%d0
    movel   %d0,prof_t0
    movel   %sp@+,%d0
    jmp     0x40058c5e
prof_end:
    movel   0xfc07800c,%d0
    subl    prof_t0,%d0           | busy
    bmis    pe_out
    movel   prof_t0,%d1
    tstl    prof_prev
    beqs    pe_first
    subl    prof_prev,%d1         | period
    bles    pe_first
    movea.l %d0,%a0
    addl    %d0,prof_busy
    addl    %d1,prof_per
    lea.l   prof_c100,%a1
    mulul   %a1@,%d0
    divul   %d1,%d0               | this block, percent
    cmpl    prof_max,%d0
    blss    pe_nm
    movel   %d0,prof_max
pe_nm:
    movel   prof_per,%d0          | keep both small enough for x100
    andil   #0xff000000,%d0
    beqs    pe_first
    movel   prof_per,%d0
    lsrl    #1,%d0
    movel   %d0,prof_per
    movel   prof_busy,%d0
    lsrl    #1,%d0
    movel   %d0,prof_busy
    lea.l   prof_trk,%a0
    moveq   #5,%d1
pe_h:
    movel   %a0@,%d0
    lsrl    #1,%d0
    movel   %d0,%a0@+
    subql   #1,%d1
    bpls    pe_h
pe_first:
    movel   prof_t0,%d0
    movel   %d0,prof_prev
pe_out:
    rts
| d0 = a share of prof_per -> percent. Keeps d1-d7, a1.
prof_pct:
    movel   %d1,%sp@-
    movel   prof_per,%d1
    lsrl    #8,%d1
    beqs    pp_z
    lsrl    #8,%d0
    lea.l   prof_c100,%a0
    mulul   %a0@,%d0
    divul   %d1,%d0
    bras    pp_o
pp_z:
    moveq   #0,%d0
pp_o:
    movel   %sp@+,%d1
    rts
    .align 4
prof_c100:    .long 100
prof_t0:      .long 0
prof_prev:    .long 0
prof_busy:    .long 0
prof_per:     .long 0
prof_max:     .long 0
prof_st:      .long 0
prof_ta:      .long 0
prof_trk:     .long 0,0,0,0,0,0    | each track's render time

| PAT: this block holds step 1 when its event time rs_T falls before the
| audio clock's next block start (a block is 2 x tempo on that clock). Then
| capture starts with this very block. Keeps a0.
rs_patchk:
    movel   rs_T,%d0
    subl    0x8000184c,%d0        | how far ahead step 1 still is
    movel   0x40149310,%d1
    addl    %d1,%d1
    cmpl    %d1,%d0
    bges    rpk_out
    moveq   #RS_REC,%d0
    movel   %d0,rs_state
rpk_out:
    rts

| a block has been appended at rs_ptr..a1: advance, and stop when full
rs_adv:
    lea.l   rs_ptr,%a0
    movel   %a1,%a0@
    lea.l   rs_n,%a0
    moveq   #32,%d0
    addl    %d0,%a0@
    movel   rs_target,%d0         | a length in bars:
    beqs    ra_man
    tstl    rs_handed             | - a few blocks before the end, the take
    bnes    ra_end                | goes on the track at its full length while
    subl    %a0@,%d0              | its last blocks are still being written
    cmpil   #RS_EARLY,%d0         | (the track reads from the start), so the
    bhis    ra_end                | downbeat's trig finds it whichever block
    movel   %a1,%sp@-             | it lands in
    bsr     rs_handoff
    movea.l %sp@+,%a1
ra_end:
    movel   rs_target,%d0         | - at the end: stop, and MUT's silence
    cmpl    rs_n,%d0              | starts on this exact block
    bhis    ra_man                | (not yet: still bounded by the space)
    lea.l   rs_state,%a0
    clrl    %a0@
    braw    rs_mutenow
ra_man:
    cmpal   rs_lim,%a1
    bcss    ra_out
    lea.l   rs_state,%a0          | out of space: stop here
    clrl    %a0@
ra_out:
    rts

| ---- UI side ----
| rs_begin(d0 = source, d1 = destination track): claim the free space and start
rs_begin:
    movel   %d2,%sp@-
    bsr     rs_begin2
    movel   %sp@+,%d2
    rts
rs_begin2:
    tstl    rs_sv_state           | a save owns the take's memory
    bnew    rb2_out
    lea.l   rs_state,%a0
    tstl    %a0@
    bnew    rb2_out
    lea.l   rs_pending,%a0
    tstl    %a0@
    bnew    rb2_out
    lea.l   rs_src,%a0
    movel   %d0,%a0@
    lea.l   rs_dst,%a0
    movel   %d1,%a0@
    bsr     rs_area               | d0 = where, d1 = the limit
    lea.l   rs_lim,%a0
    movel   %d1,%a0@
    lea.l   rs_base,%a0
    movel   %d0,%a0@
    addil   #64,%d0               | past the header
    lea.l   rs_ptr,%a0
    movel   %d0,%a0@
    lea.l   rs_n,%a0
    clrl    %a0@
    | length: 1/2/4/8/16 bars at the current tempo, manual (0), or PTN - the
    | current pattern's length
    lea.l   rs_target,%a0
    clrl    %a0@
    movel   rs_c_len,%d1
    cmpil   #6,%d1                | PTN: the pattern's length
    bnes    rb2_nptn
    bsr     rs_ptn_len            | (uses a0)
    lea.l   rs_target,%a0
    movel   %d0,%a0@
    lea.l   rs_barlen,%a1         | progress in seconds
    clrl    %a1@
    bras    rb2_man
rb2_nptn:
    cmpil   #4,%d1
    bhis    rb2_man
    movel   0x40149310,%d0        | tempo, 1/120 BPM
    beqs    rb2_man
    movel   #1382400000,%d2       | a bar in samples at 48 kHz
    divul   %d0,%d2
    lsll    %d1,%d2               | << log2(bars)
    movel   %d2,%a0@
    lea.l   rs_barlen,%a0
    lsrl    %d1,%d2
    movel   %d2,%a0@
rb2_man:
    | ---- CHN STE: a side plane, rs_soff bytes above the mid - for the whole
    | output, or for a track playing a stereo sample (rs_trk takes its side
    | from sx_cap, silence for any block it renders in mono) ----
    | A bar take's mid is its length (plus a block: the last block can run up
    | to 31 samples past it); a manual one gets half the space. The mid then
    | stops a block short of the side, as the mono take stops short of the
    | delay lines. rs_watch closes any gap a manual take leaves.
    lea.l   rs_soff,%a0
    clrl    %a0@
    tstl    rs_c_chn
    beqs    rb2_mono
    moveq   #RS_MST,%d0
    cmpl    rs_src,%d0
    beqs    rb2_ste               | the whole output: always stereo
    moveq   #RS_USB,%d0
    cmpl    rs_src,%d0
    beqs    rb2_ste               | the computer's audio: stereo too
    movel   rs_src,%d0            | a track: when it plays a stereo sample
    lea.l   track_slot,%a1
    movel   %a1@(0,%d0:l:4),%d0
    bmis    rb2_mono
    lea.l   slot_soff,%a1
    tstl    %a1@(0,%d0:l:4)
    beqs    rb2_mono
rb2_ste:
    movel   rs_lim,%d0
    subl    rs_ptr,%d0
    lsrl    #1,%d0
    andil   #0xfffffff0,%d0       | half the space
    movel   rs_target,%d1
    beqs    rb2_half
    addl    %d1,%d1
    addil   #64+15,%d1
    andil   #0xfffffff0,%d1
    cmpl    %d0,%d1
    bhis    rb2_half              | more than half: half is all there is
    movel   %d1,%d0
rb2_half:
    movel   %d0,%a0@
    movel   rs_ptr,%d1
    addl    %d0,%d1
    subil   #64,%d1
    lea.l   rs_lim,%a0
    movel   %d1,%a0@
rb2_mono:
    bsr     rs_calc_gain
    bsr     rs_pick_slot          | the slot the take will become, chosen now
    tstl    %d0                   | so the audio thread can hand it over
    bmiw    rb2_noslot
    lea.l   rs_slot,%a0
    movel   %d0,%a0@
    lea.l   rs_seq,%a0
    addql   #1,%a0@
    movel   %a0@,%d0
    andil   #0xff,%d0
    oril    #RS_HASH,%d0
    lea.l   rs_hash,%a0
    movel   %d0,%a0@
    lea.l   rs_handed,%a0
    clrl    %a0@
    lea.l   rs_eu_done,%a0
    clrl    %a0@
    lea.l   rs_prev,%a0           | the step counter as it stands
    movel   0x40a78840,%d0
    movel   %d0,%a0@
    lea.l   rs_pending,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
    movel   rs_c_sta,%d0          | 0 PAT, 1 NOW, 2 SND
    moveq   #RS_PAT,%d1
    tstl    %d0
    beqs    rb2_go
    moveq   #RS_REC,%d1
    cmpil   #1,%d0
    beqs    rb2_go
    moveq   #RS_SND,%d1
rb2_go:
    lea.l   rs_state,%a0          | last: the audio side acts on it now
    movel   %d1,%a0@
rb2_out:
    rts
rb2_noslot:
    pea     rs_m_noslot
    jsr     show_popup
    addql   #4,%sp
    rts

| ---- capture gain: a take replayed on its track sounds as it was heard ----
| A Sample track plays s as s<<15 (half scale), the amp stage is unity at full
| level (voice +0x2a0 = 0x20000000, times 4; +0x2a4 = 1.0), 0x400a7d4a halves
| every track, the main mix adds it with the track's L/R gains (0x40a78c08[t],
| 0x40a78be8[t], negative: msac, fractional), 0x400565c6 multiplies the bus by
| 4, and the output stage by (0xff800000 >> (3 - X)) with X the byte at
| 0x404e9b5f. rs_out then takes (L+R)/2 >> 8. Round trip for the destination:
|     G = avg(|gL|, |gR|) * 2^(X-3)
| so the whole output is captured with 1/G, in Q12: 2^(30-X) / (avg gain >> 16)
| (capped at 16x). A track (dry, before the halving) is captured at unity - the
| >>15 in rs_trk undoes the Sampler's <<15. Then the TRM trim on top.
rs_calc_gain:
    movel   %d2,%sp@-
    lea.l   rs_gain,%a0           | capture at unity: bus >> 16 cannot clip
    movel   #256,%d0
    movel   %d0,%a0@
    movel   #RS_PTRK,%d0          | a dry track: 1 / 0.382
    moveq   #RS_USB,%d1
    cmpl    rs_src,%d1
    bnes    rcg_nusb
    movel   #4096,%d0             | USB: captured at full scale, played as
    bras    rcg_trim              | any sample is (unity), then the trim
rcg_nusb:
    moveq   #RS_MST,%d1
    cmpl    rs_src,%d1
    bnes    rcg_trim
    movel   rs_dst,%d1
    lsll    #2,%d1
    lea.l   0x40a78c08,%a0
    movel   %a0@(0,%d1:l),%d0
    bpls    rcg_l
    negl    %d0
rcg_l:
    lea.l   0x40a78be8,%a0
    movel   %a0@(0,%d1:l),%d2
    bpls    rcg_r
    negl    %d2
rcg_r:
    lsrl    #8,%d0
    lsrl    #8,%d0
    lsrl    #8,%d2
    lsrl    #8,%d2
    addl    %d2,%d0
    lsrl    #1,%d0                | avg mixer gain, Q15
    cmpil   #5361,%d0
    bcss    rcg_cap               | would need more than 16x
    movel   #RS_PMST,%d1          | 1 / (0.382 x gain), Q12
    divul   %d0,%d1
    movel   %d1,%d0
rcg_trim:
    movel   rs_c_trim,%d1
    lea.l   rs_trimq12,%a0
    movel   %a0@(0,%d1:l:4),%d1
    mulul   %d1,%d0
    lsrl    #8,%d0
    lsrl    #4,%d0
    cmpil   #65536,%d0
    blss    rcg_st
rcg_cap:
    movel   #65536,%d0            | 16x at most
rcg_st:
    lea.l   rs_pg,%a0
    movel   %d0,%a0@
    movel   %sp@+,%d2
    rts

| rs_ptn_len -> d0 = the current pattern's length in samples: length x
| ticks per step x one tick. The pattern is *0x40a7887c (the sequencer's
| step logic at 0x4005542e): steps at +0x77C6 (word), speed at +0x77CC, an
| index into the ticks-per-step table 0x4010afa4 {3,4,6,8,12,24,48} - 2x
| down to 1/8x. A tick is 14,400,000 / tempo samples (tempo in 1/120 BPM),
| worked as quotient and remainder so nothing overflows. Mode byte +0x77CB =
| 1, which that logic treats specially, or anything implausible: one bar at
| 1x. 0 if there is no tempo. Keeps d2-d7.
rs_ptn_len:
    movel   %d2,%sp@-
    moveq   #0,%d0
    movel   0x40149310,%d2        | tempo
    beqs    rpl_out
    moveq   #96,%d1               | fallback: 16 steps x 6 ticks
    movel   0x40a7887c,%d0
    beqs    rpl_calc
    movea.l %d0,%a0
    moveq   #0,%d0
    moveb   %a0@(0x77cb),%d0
    cmpil   #1,%d0
    beqs    rpl_calc
    moveq   #0,%d0
    moveb   %a0@(0x77cc),%d0
    cmpil   #6,%d0
    bhis    rpl_calc
    lea.l   0x4010afa4,%a1
    movel   %a1@(0,%d0:l:4),%d0   | ticks per step
    mvzw    %a0@(0x77c6),%d1      | steps
    tstl    %d1
    beqs    rpl_bar
    cmpil   #256,%d1
    bhis    rpl_bar
    mulul   %d0,%d1               | ticks
    bras    rpl_calc
rpl_bar:
    moveq   #96,%d1
rpl_calc:
    movel   #14400000,%d0
    divul   %d2,%d0               | q: whole samples a tick
    movea.l %d0,%a1
    mulul   %d2,%d0
    negl    %d0
    addil   #14400000,%d0         | r
    mulul   %d1,%d0
    divul   %d2,%d0               | ticks x r / tempo
    movel   %a1,%d2
    mulul   %d1,%d2               | ticks x q
    addl    %d2,%d0
rpl_out:
    movel   %sp@+,%d2
    rts

| d0 = a free slot, else one evict_one empties, else -1. UI side.
rs_pick_slot:
    bsr     free_slot
    tstl    %d0
    bpls    rps_out
    moveq   #-1,%d0
    movel   %d0,el_slot
    bsr     evict_one
    tstl    %d0
    beqs    rps_none
    bsr     free_slot
    rts
rps_none:
    moveq   #-1,%d0
rps_out:
    rts

| rs_handoff: the take becomes rs_dst's sample - from the audio thread the
| moment a bar-length take completes, or from rs_watch for any other stop.
| Plain stores only. MUT also silences every other track from the next block
| (rs_silence, applied in amp_hook); the stock mutes follow on the UI clock.
rs_handoff:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d5,%sp@
    movel   rs_n,%d2
    movel   rs_target,%d0
    beqs    rh_nt
    movel   %d0,%d2               | exactly the bars asked for - also when
rh_nt:                            | handed over before the last blocks are in
    cmpil   #480,%d2
    bcsw    rh_out                | under 10 ms: rs_watch says so
    movel   rs_slot,%d3
    lea.l   slot_hash,%a0
    movel   rs_hash,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_base,%a0
    movel   rs_base,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_count,%a0
    movel   %d2,%a0@(0,%d3:l:4)
    lea.l   slot_pgain,%a0
    movel   rs_pg,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_soff,%a0         | a stereo take's side plane
    movel   rs_soff,%d0
    movel   %d0,%a0@(0,%d3:l:4)
    movel   rs_base,%d0
    lea.l   rs_len,%a0
    movel   %d2,%a0@
    addl    %d2,%d2               | alloc_top past it, 16-aligned
    addl    %d2,%d0
    addl    rs_soff,%d0           | (and past the side)
    addil   #64+15,%d0
    andil   #0xfffffff0,%d0
    subl    rs_base,%d0
    lea.l   slot_size,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    bsr     top_calc              | alloc_top: the highest slot's end - not
                                  | this take's, which may sit below the files
    | Its owner: this pattern's rs_dst, standing in for the token that track
    | names here (the sample the name keeps naming until SAV) - so the take
    | plays in this pattern only, and name_probe finds it again on the way back.
    | A take the track already played there stands in for the same token.
    movel   rs_dst,%d2
    lea.l   track_hash,%a0
    movel   %a0@(0,%d2:l:4),%d1   | what the track played: a take's token is
    movel   %d1,%d0               | its own ttok, anything else is the token
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    bnes    rh_tok
    moveq   #0,%d0
rh_tf:
    lea.l   slot_hash,%a0
    cmpl    %a0@(0,%d0:l:4),%d1
    bnes    rh_tn
    lea.l   slot_tpat,%a0
    tstl    %a0@(0,%d0:l:4)
    bmis    rh_tn
    lea.l   slot_ttok,%a0
    movel   %a0@(0,%d0:l:4),%d1
    bras    rh_tok
rh_tn:
    addql   #1,%d0
    cmpil   #MAX_SLOT,%d0
    bcss    rh_tf
rh_tok:
    lea.l   rs_tok,%a0
    movel   %d1,%a0@(0,%d2:l:4)
    bsr     cur_pat
    moveq   #0,%d4                | an older take owned by the same place is
rh_old:                           | no longer wanted there
    lea.l   slot_tpat,%a0
    cmpl    %a0@(0,%d4:l:4),%d0
    bnes    rh_on
    lea.l   slot_ttrk,%a0
    cmpl    %a0@(0,%d4:l:4),%d2
    bnes    rh_on
    lea.l   slot_tpat,%a0
    moveq   #-1,%d5
    movel   %d5,%a0@(0,%d4:l:4)
rh_on:
    addql   #1,%d4
    cmpil   #MAX_SLOT,%d4
    bcss    rh_old
    lea.l   slot_tpat,%a0
    movel   %d0,%a0@(0,%d3:l:4)
    lea.l   slot_ttrk,%a0
    movel   %d2,%a0@(0,%d3:l:4)
    lea.l   slot_ttok,%a0
    movel   %d1,%a0@(0,%d3:l:4)
    lea.l   track_hash,%a0
    movel   rs_hash,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   track_pend,%a0        | the render takes it up at the track's next
    movel   %d3,%a0@(0,%d2:l:4)   | note (or once it is silent): switching a
rh_done:                          | voice mid-note was a click
    lea.l   rs_handed,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
rh_out:
    moveml  %sp@,%d2-%d5
    lea.l   %sp@(16),%sp
    rts

| A stereo take not yet on its track: move its side plane down to just past
| the mid, so a manual take does not keep half the space. UI side.
rs_compact:
    movel   rs_soff,%d0
    beqs    rcp_out
    movel   rs_n,%d1
    addl    %d1,%d1
    addil   #15,%d1
    andil   #0xfffffff0,%d1       | where the side can start
    cmpl    %d0,%d1
    bccs    rcp_out               | already there
    movel   %d1,rs_soff
    movea.l rs_base,%a0
    lea.l   %a0@(64),%a0
    movea.l %a0,%a1
    adda.l  %d0,%a0               | from
    adda.l  %d1,%a1               | to: below it, so a forward copy is safe
    movel   rs_n,%d0
    beqs    rcp_out
rcp_l:
    movew   %a0@+,%a1@+
    subql   #1,%d0
    bnes    rcp_l
rcp_out:
    rts

| MUT: silence every track but the take's own, from the next block (amp_hook)
rs_mutenow:
    tstl    rs_c_mut
    beqs    rmn_out
    movel   rs_dst,%d1
    moveq   #0x3f,%d0
    bclr    %d1,%d0
    lea.l   rs_silence,%a0
    movel   %d0,%a0@
rmn_out:
    rts

| rs_watch: on the UI clock. A recording that has stopped is committed here.
rs_watch:
    bsr     mute_poll
    bsr     rs_menu_tick
    bsr     rs_unsilence
    bsr     rs_early_unmute
    lea.l   rs_pending,%a0
    tstl    %a0@
    beqw    rw_out
    lea.l   rs_state,%a0
    tstl    %a0@
    bnew    rw_out                | still recording
    lea.l   %sp@(-32),%sp
    moveml  %d2-%d7/%a2-%a3,%sp@
    tstl    rs_handed             | stopped by hand or out of space: hand
    bnes    rw_h                  | over now
    bsr     rs_compact
    bsr     rs_handoff
    tstl    rs_handed
    beqw    rw_short
rw_h:
    movel   rs_target,%d0         | a bar take stopped by hand after it was
    beqs    rw_h2                 | handed over: only what was written
    movel   rs_n,%d1
    cmpl    %d0,%d1
    bccs    rw_h2
    movel   rs_slot,%d0
    lea.l   slot_count,%a0
    movel   %d1,%a0@(0,%d0:l:4)
    lea.l   rs_len,%a0
    movel   %d1,%a0@
rw_h2:
    movel   rs_slot,%d0           | a stereo take with a silent side is mono
    bsr     sx_quiet_slot
    bsr     rs_mutenow
    lea.l   rs_pending,%a0
    clrl    %a0@
    tstl    rs_c_mut
    beqs    rw_nomut
    bsr     rs_solo               | MUT: the stock mutes, for LEDs and MIDI
rw_nomut:
    | "T1>T3 12.3s" / "OUT>T3 12.3s"
    movel   rs_len,%d0            | tenths of a second: n / 4800
    movel   #4800,%d1
    divul   %d1,%d0
    moveq   #10,%d1
    movel   %d0,%d4
    divul   %d1,%d4               | seconds
    movel   %d4,%d7
    mulul   %d1,%d7
    subl    %d7,%d0               | tenths
    lea.l   rs_args,%a0
    lea.l   rs_f_trk,%a1
    moveq   #RS_MST,%d1
    cmpl    rs_src,%d1
    bnes    rw_nm
    lea.l   rs_f_mst,%a1          | whole output: no source number
    bras    rw_fd
rw_nm:
    moveq   #RS_USB,%d1
    cmpl    rs_src,%d1
    bnes    rw_ft
    lea.l   rs_f_usb,%a1          | the computer: no source number either
    bras    rw_fd
rw_ft:
    movel   rs_src,%d1
    addql   #1,%d1
    movel   %d1,%a0@+
rw_fd:
    movel   rs_dst,%d1
    addql   #1,%d1
    movel   %d1,%a0@+
    movel   %d4,%a0@+
    movel   %d0,%a0@+
    pea     rs_args
    movel   %a1,%sp@-
    pea     msg_buf
    jsr     0x400005cc            | vsprintf(buf, fmt, args)
    lea.l   %sp@(12),%sp
    lea.l   msg_buf,%a0
    bras    rw_msg
rw_short:
    lea.l   rs_pending,%a0
    clrl    %a0@
    lea.l   rs_m_short,%a0
rw_msg:
    movel   %a0,%sp@-
    jsr     show_popup
    addql   #4,%sp
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(32),%sp
rw_out:
    rts

| ---- the Resample menu (Track + key 9) -------------------------------------
| The Granular menu's list, with its own rows: SRC (T1..T6, MST = the whole
| output), LEN (1/2/4/8/16 bars or MAN), STA (PAT = the top of the pattern, NOW,
| SND = the source's first sound) and REC, whose press arms, stops, or cancels
| an armed take instead of editing. The recording goes to the track that was
| selected when the menu opened, which must then be a Sampler.
rs_menu_open:
    linkw   %fp,#-80
    lea.l   %sp@(-28),%sp
    moveml  %d2-%d4/%a2-%a5,%sp@
    lea.l   mm_opened,%a0
    clrl    %a0@
    moveq   #0,%d0
    movew   %sr,%d0
    andil   #0x0700,%d0
    bnew    gm_done
    tstl    0x40fe4178
    beqw    gm_done
    bsr     gm_live               | a list menu already up: no second copy
    tstl    %d0
    bnew    gm_opened
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    lea.l   %sp@(8),%sp
    cmpil   #MAX_TRK,%d0
    bccw    gm_done
    lea.l   gm_track,%a0
    movel   %d0,%a0@
    lea.l   rs_desc,%a0
    lea.l   gm_cur,%a1
    movel   %a0,%a1@
    braw    lm_build

| values: a0 = &setting, a1 = its names
rs_val_src:
    lea.l   rs_c_src,%a0
    lea.l   rs_n_src,%a1
    braw    gm_val
rs_val_chn:
    lea.l   rs_c_chn,%a0
    lea.l   rs_n_chn,%a1
    braw    gm_val
rs_val_len:
    lea.l   rs_c_len,%a0
    lea.l   rs_n_len,%a1
    braw    gm_val
rs_val_sta:
    lea.l   rs_c_sta,%a0
    lea.l   rs_n_sta,%a1
    braw    gm_val
rs_val_mut:
    lea.l   rs_c_mut,%a0
    lea.l   gm_n_frz,%a1          | OFF / ON
    braw    gm_val
rs_val_trm:
    lea.l   rs_c_trim,%a0
    lea.l   rs_n_trm,%a1
    braw    gm_val
| REC: what the recorder is doing - GO, ARM, bar n/N or seconds, or ...
rs_val_rec:
    lea.l   %sp@(-16),%sp
    moveml  %d0-%d1/%a0-%a1,%sp@
    bsr     rs_rec_text
    moveml  %sp@,%d0-%d1/%a0-%a1
    lea.l   %sp@(16),%sp
    lea.l   rs_zero,%a0
    lea.l   rs_n_rec,%a1
    braw    gm_val
rs_rec_text:
    lea.l   rs_state,%a0
    movel   %a0@,%d0
    beqs    rrt_idle
    cmpil   #RS_REC,%d0
    beqs    rrt_rec
    lea.l   rs_s_arm,%a0
    bras    rrt_cp
rrt_idle:
    lea.l   rs_s_go,%a0
    tstl    rs_pending
    beqs    rrt_cp
    lea.l   rs_s_busy,%a0
    bras    rrt_cp
rrt_rec:
    lea.l   rs_args,%a1
    movel   rs_target,%d0
    beqs    rrt_sec
    movel   rs_n,%d1              | bar n of N
    movel   rs_barlen,%d0
    beqs    rrt_sec
    divul   %d0,%d1
    addql   #1,%d1
    movel   %d1,%a1@
    movel   rs_target,%d1
    divul   %d0,%d1
    movel   %d1,%a1@(4)
    lea.l   rs_f_bar,%a0
    bras    rrt_fmt
rrt_sec:
    movel   rs_n,%d1              | seconds
    movel   #48000,%d0
    divul   %d0,%d1
    movel   %d1,%a1@
    lea.l   rs_f_sec,%a0
rrt_fmt:
    pea     rs_args
    movel   %a0,%sp@-
    pea     rs_vbuf
    jsr     0x400005cc
    lea.l   %sp@(12),%sp
    rts
rrt_cp:
    lea.l   rs_vbuf,%a1
rrt_c:
    moveb   %a0@+,%d0
    moveb   %d0,%a1@+
    bnes    rrt_c
    rts

| turns: a1 = &setting, d1 = how many; no persistence
rs_rot_src:
    lea.l   rs_c_src,%a1
    moveq   #8,%d1                | T1..T6, MST, USB
    bras    rs_rot
rs_rot_chn:
    lea.l   rs_c_chn,%a1
    moveq   #2,%d1
    bras    rs_rot
rs_rot_len:
    lea.l   rs_c_len,%a1
    moveq   #7,%d1
    bras    rs_rot
rs_rot_mut:
    lea.l   rs_c_mut,%a1
    moveq   #2,%d1
    bras    rs_rot
rs_rot_trm:
    lea.l   rs_c_trim,%a1
    moveq   #5,%d1
    bras    rs_rot
rs_rot_sta:
    lea.l   rs_c_sta,%a1
    moveq   #3,%d1
rs_rot:
    movel   %sp@(12),%d0          | the turn
    beqs    rr_out
    bgts    rr_up
    movel   %a1@,%d0
    subql   #1,%d0
    bpls    rr_set
    moveq   #0,%d0
    bras    rr_set
rr_up:
    movel   %a1@,%d0
    addql   #1,%d0
    cmpl    %d1,%d0
    bcss    rr_set
    movel   %d1,%d0
    subql   #1,%d0
rr_set:
    movel   %d0,%a1@
rr_out:
    rts
rs_rot_none:
    rts

| REC's press (closure, item): stop a take, cancel an armed one, or arm
rs_press:
    lea.l   rs_state,%a0
    movel   %a0@,%d0
    beqs    rp_arm
    clrl    %a0@                  | stop / cancel
    cmpil   #RS_REC,%d0
    beqs    rp_out                | a take: rs_watch commits it
    lea.l   rs_pending,%a0        | armed, nothing captured: just forget it
    clrl    %a0@
rp_out:
    rts
rp_arm:
    tstl    rs_pending
    bnes    rp_out                | the last take is still being committed
    movel   gm_track,%d0
    jsr     sound_obj
    tstl    %d0
    beqs    rp_need
    movea.l %d0,%a0
    mvzb    %a0@(38),%d0
    cmpil   #6,%d0
    bnes    rp_need
    movel   rs_c_src,%d0
    movel   gm_track,%d1
    braw    rs_begin
rp_need:
    pea     rs_m_need
    jsr     show_popup
    addql   #4,%sp
    rts

| CLR: SMP while the track has a sample, --- once it is empty
rs_val_clr:
    lea.l   rs_zero,%a0
    lea.l   rs_n_emp,%a1
    movel   gm_track,%d0
    lea.l   track_slot,%a1
    tstl    %a1@(0,%d0:l:4)
    lea.l   rs_n_emp,%a1
    bmiw    gm_val
    lea.l   rs_n_smp,%a1
    braw    gm_val

| CLR's press: the track the menu is for loses its sample and goes silent.
| It gets RS_HASH | 0xff - a hash nothing is ever stored under, so no load is
| attempted - written into this pattern's sound name as well, so the track is
| empty in this pattern only, and stays so when the project is saved. A
| recording nothing else wants gives its memory back at once. Not while the
| recorder is busy.
rs_clear:
    tstl    rs_sv_state
    bnew    rc_out
    tstl    rs_state
    bnew    rc_out
    tstl    rs_pending
    bnew    rc_out
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    movel   gm_track,%d2
    lea.l   track_pend,%a0        | no take still waiting to land
    moveq   #-1,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   track_slot,%a0        | silent first: the audio side reads this
    movel   %a0@(0,%d2:l:4),%d3   | the slot it played
    moveq   #-1,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    lea.l   track_hash,%a0
    movel   #RS_HASH+0xff,%d0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d2,%d0               | and in this pattern's sound name: empty
    movel   #RS_HASH+0xff,%d1     | here, and only here, and it is saved
    jsr     name_store
    tstl    %d3
    bmiw    rc_msg                | it had none
    lea.l   slot_hash,%a0         | a recording nothing wants any more goes
    movel   %a0@(0,%d3:l:4),%d0   | now (a file stays resident for other
    andil   #0xffffff00,%d0       | patterns, or until space is needed)
    cmpil   #RS_HASH,%d0
    bnes    rc_msg
    movel   %d3,%d0
    bsr     slot_level
    tstl    %d0
    bnes    rc_msg
    movel   %d3,%d0
    bsr     slot_drop
    bsr     top_calc
rc_msg:
    pea     rs_m_clr
    jsr     show_popup
    addql   #4,%sp
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
rc_out:
    rts

| mute_poll: on the UI clock. mute_sil <- the Sampler tracks the stock mute
| (FUNC + pad) holds: amp_hook fades them out as it does MUT's silence (64
| samples), and voice_quiet then ends their note, so a muted loop is silent
| and costs nothing until the first trig after its unmute. Stock machines
| keep the stock mute - no new trigs, the note rings out - and go idle once
| it has.
mute_poll:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    addql   #4,%sp
    movel   %d0,%d4
    moveq   #0,%d3
    moveq   #0,%d2
mp_l:
    lea.l   trk_mach,%a0
    moveq   #6,%d0
    cmpl    %a0@(0,%d2:l:4),%d0
    bnes    mp_n
    movel   %d2,%sp@-
    movel   %d4,%sp@-
    jsr     0x4001263c            | muted?
    addql   #8,%sp
    tstb    %d0
    beqs    mp_n
    bset    %d2,%d3
mp_n:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    mp_l
    movel   %d3,mute_sil
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
    rts

| rs_silence: while a bit is set, amp_hook zeroes that track. Set by the
| handover (MUT) so the other tracks stop on the exact block; the stock mutes
| rs_solo applies then take over, and a bit is dropped once its track is
| unmuted by hand. Only checked with no take pending, so the stock mutes are in.
rs_unsilence:
    tstl    rs_silence
    beqs    ru_out
    tstl    rs_pending
    bnes    ru_out
    movel   %d2,%sp@-
    moveq   #0,%d2
ru_l:
    movel   rs_silence,%d0
    btst    %d2,%d0
    beqs    ru_n
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    addql   #4,%sp
    movel   %d2,%sp@-
    movel   %d0,%sp@-
    jsr     0x4001263c            | muted?
    addql   #8,%sp
    tstb    %d0
    bnes    ru_n
    lea.l   rs_silence,%a0        | unmuted: audible again
    movel   %a0@,%d0
    bclr    %d2,%d0
    movel   %d0,%a0@
ru_n:
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    ru_l
    movel   %sp@+,%d2
ru_out:
    rts

| MUT with a muted destination: the sequencer drops trigs on muted tracks when
| it SCHEDULES them, a tick (14,400,000 / tempo samples) before they sound, so
| the downbeat trig was gone before the take's commit unmuted the track - a
| whole bar of silence. So, RS_EUTICKS ticks before a bar take ends, the
| destination is unmuted through the stock setter (UI side, CC and all) and
| held silent in amp_hook until the bar line, where rs_mutenow releases it.
RS_EUTICKS = 4
rs_early_unmute:
    moveq   #RS_REC,%d0
    cmpl    rs_state,%d0
    bnew    reu_out
    tstl    rs_target
    beqs    reu_out
    tstl    rs_c_mut
    beqs    reu_out
    tstl    rs_eu_done
    bnes    reu_out
    movel   0x40149310,%d1        | a tick, in samples
    beqs    reu_out
    movel   #14400000*RS_EUTICKS,%d0
    divul   %d1,%d0
    movel   rs_target,%d1
    subl    rs_n,%d1              | samples still to come
    cmpl    %d0,%d1
    bhis    reu_out
    lea.l   rs_eu_done,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
    movel   %d2,%sp@-
    movel   rs_dst,%d2
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    addql   #4,%sp
    movel   %d0,%sp@-             | kept for the setter
    movel   %d2,%sp@-
    movel   %d0,%sp@-
    jsr     0x4001263c            | muted?
    addql   #8,%sp
    movel   %sp@+,%d1
    tstb    %d0
    beqs    reu_done
    lea.l   rs_silence,%a0        | silent first, then audible to the sequencer
    movel   %a0@,%d0
    bset    %d2,%d0
    movel   %d0,%a0@
    pea     1                     | with the CC, as a hand-made unmute
    clrl    %sp@-
    movel   %d2,%sp@-
    movel   %d1,%sp@-
    jsr     0x4001381c
    lea.l   %sp@(16),%sp
reu_done:
    movel   %sp@+,%d2
reu_out:
    rts

| ---- SAV: write the track's take to disk ------------------------------------
| Pressing SAV queues it; rs_save_do runs it in the UI task, a step per
| message (sv_post / sv_run), because writing blocks. The file is an ordinary device sample
| (docs/notes/sample_format.md): 64-byte header, big-endian 16-bit mono at
| 48 kHz, 16 zero bytes after - plus our playback gain in header bytes the
| format leaves zero ("RSG1" at +0x18, the gain at +0x1c), which our loader
| reads back. Written through the firmware's own FileWriter - what Transfer's
| raw write commands use (0x4008870a): ctor 0x4007c7ca(fw, path, size) opens
| it (making the folder), vtable +0x10 writes (buffered), +0x1c reports an
| error, +0x14 closes, +0x18 aborts and deletes; dtor 0x4007c76a. Named
| /Resampled/Take-XXXXXX from an FNV-1a hash of the audio, so names do not
| collide across boots. Afterwards the new file's hash is read from the inode
| table (the newest file of that size) and the track relinked to it - slot,
| track and name token - so it survives a project save and reload.
|
| The stock FileWriter MUTES THE AUDIO for as long as it exists: its ctor
| calls the function object at 0x40f07be4 and its dtor the one at 0x40f07bd4,
| which the UI task sets at boot (0x40007f32/0x40007f66) to 0x40007774 ->
| 0x40059692(1) - the render interrupt 0x40058c5e then fades out and zeroes
| every block - and 0x40007780 -> 0x40059692(0). Loads never make a
| FileWriter, which is why they play on. The audio itself is that level-5
| interrupt, not a task, and the eMMC driver sleeps on semaphores (its own
| interrupts are level 3), so nothing else in the write path can stop it.
| Each object is empty when its word at +8 is zero (0x400e3c54 tests it, and
| static init 0x400e8d12 clears exactly those words), so ours blanks it just
| for its own ctor and dtor calls; every stock save keeps the stock mute.
RS_GMAGIC = 0x52534731           | "RSG1"
FW_SIZE   = 0x8110
FW_HOOK_ON  = 0x40f07be4
FW_HOOK_OFF = 0x40f07bd4
| SAV names the take first: the stock name editor (ModelsNameView, as the
| pattern and preset renames open it - 0x4002c92a, 0x400a516e), prefilled
| with the default "Take-XXXXXX". Its save calls nm_save with the name,
| which starts the save; backing out saves nothing. No take on the track:
| straight to the save, which says there is nothing to save.
RS_NAMEMAX = 12                   | the length the stock renames allow
rs_save_press:
    tstl    rs_state              | not while recording
    bnes    rsp_out
    tstl    rs_pending
    bnes    rsp_out
    lea.l   rs_save_trk,%a0
    movel   gm_track,%d0
    movel   %d0,%a0@
    bsr     rs_defname            | the default name, if there is a take
    tstl    %d0
    beqs    rs_save_go
    braw    rs_name_open
rs_save_go:
    lea.l   rs_save_req,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
    lea.l   sv_msg_a,%a0          | the save runs in the UI task, a step per
    braw    sv_post               | message (see sv_run)
rsp_out:
    rts

| rs_defname -> d0 = 1 and rs_name = "Take-XXXXXX" (FNV-1a over every 64th
| byte of the take and its length, so names do not repeat across boots), or
| 0 when rs_save_trk plays no unsaved take. Keeps d2-d7.
rs_defname:
    lea.l   %sp@(-20),%sp
    moveml  %d2-%d5/%a3,%sp@
    movel   rs_save_trk,%d0
    lea.l   track_slot,%a0
    movel   %a0@(0,%d0:l:4),%d1   | its slot
    bmiw    rdn_no
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d1:l:4),%d0
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    bnew    rdn_no                | a file already
    lea.l   slot_count,%a0
    movel   %a0@(0,%d1:l:4),%d4
    addl    %d4,%d4               | data bytes, a plane
    lea.l   slot_base,%a0
    movea.l %a0@(0,%d1:l:4),%a3
    lea.l   %a3@(64),%a3
    movel   %d4,%d5               | both planes' bytes
    lea.l   slot_soff,%a0
    tstl    %a0@(0,%d1:l:4)
    beqs    rdn_m
    addl    %d4,%d5
rdn_m:
    movel   #0x811c9dc5,%d0
    movel   #16777619,%d1
    eorl    %d5,%d0
    mulul   %d1,%d0
    movea.l %a3,%a0
    movel   %d4,%d2
    lsrl    #6,%d2
    beqs    rdn_hd
rdn_h:
    moveq   #0,%d3
    moveb   %a0@,%d3
    lea.l   %a0@(64),%a0
    eorl    %d3,%d0
    mulul   %d1,%d0
    subql   #1,%d2
    bnes    rdn_h
rdn_hd:
    lea.l   rs_take,%a0           | "Take-" + 6 hex digits
    lea.l   rs_name,%a1
rdn_p:
    moveb   %a0@+,%d1
    beqs    rdn_x0
    moveb   %d1,%a1@+
    bras    rdn_p
rdn_x0:
    moveq   #20,%d2
rdn_x:
    movel   %d0,%d1
    lsrl    %d2,%d1
    andil   #15,%d1
    cmpil   #10,%d1
    bcss    rdn_xd
    addql   #7,%d1
rdn_xd:
    addil   #48,%d1
    moveb   %d1,%a1@+
    subql   #4,%d2
    bpls    rdn_x
    clrb    %a1@
    moveq   #1,%d0
    bras    rdn_out
rdn_no:
    moveq   #0,%d0
rdn_out:
    moveml  %sp@,%d2-%d5/%a3
    lea.l   %sp@(20),%sp
    rts

| rs_name_open: the stock name editor over the Resample menu. Strings are
| built as the stock does (0x400f980c, released with 0x400f7d5c); the two
| std::functions - {data, 0, manager, invoker}, as our menu rows' closures -
| are copied by the editor, and ours released after (FREE_CLOSURE).
|   ctor 0x40041152(view, title, name, prompt, 0, 12, draw, save)
|   present 0x40076220(parent view, view, 0)
rs_name_open:
    linkw   %fp,#-56
    lea.l   %sp@(-16),%sp
    moveml  %d2/%a2-%a4,%sp@
    lea.l   0x400f980c,%a4        | String(this, cstr, tag)
    pea     %fp@(-13)
    pea     rs_nm_title
    pea     %fp@(-4)
    jsr     %a4@
    pea     %fp@(-14)
    pea     rs_name
    pea     %fp@(-8)
    jsr     %a4@
    pea     %fp@(-15)
    pea     rs_nm_prompt
    pea     %fp@(-12)
    jsr     %a4@
    lea.l   %sp@(36),%sp
    lea.l   ALLOC,%a3             | the draw callback: draws nothing
    pea     1
    jsr     %a3@
    addql   #4,%sp
    movel   %d0,%fp@(-32)
    clrl    %fp@(-28)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%fp@(-24)
    movel   #nm_draw,%d0
    movel   %d0,%fp@(-20)
    pea     1                     | the save callback: nm_save
    jsr     %a3@
    addql   #4,%sp
    movel   %d0,%fp@(-48)
    clrl    %fp@(-44)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%fp@(-40)
    movel   #nm_save,%d0
    movel   %d0,%fp@(-36)
    pea     0xac                  | the editor, as the stock allocates it
    jsr     0x400802e0
    addql   #4,%sp
    movel   %d0,%d2
    beqs    rno_free
    pea     %fp@(-48)
    pea     %fp@(-32)
    pea     RS_NAMEMAX
    clrl    %sp@-
    pea     %fp@(-12)
    pea     %fp@(-8)
    pea     %fp@(-4)
    movel   %d2,%sp@-
    jsr     0x40041152
    lea.l   %sp@(32),%sp
    clrl    %sp@-                 | over the Resample menu
    movel   %d2,%sp@-
    movel   gm_obj,%d0
    addil   #0x38,%d0
    movel   %d0,%sp@-
    jsr     0x40076220
    lea.l   %sp@(12),%sp
rno_free:
    pea     %fp@(-32)
    jsr     FREE_CLOSURE
    pea     %fp@(-48)
    jsr     FREE_CLOSURE
    lea.l   0x400f7d5c,%a2
    pea     %fp@(-4)
    jsr     %a2@
    pea     %fp@(-8)
    jsr     %a2@
    pea     %fp@(-12)
    jsr     %a2@
    lea.l   %sp@(20),%sp
    moveml  %sp@,%d2/%a2-%a4
    unlk    %fp
    rts

| the editor's callbacks. Draw (closure, bitmap, x, y): nothing. Save (closure,
| std::string&& name): the name's characters are *(char **)name; an empty one
| keeps the default. Then the save starts, as SAV used to start it.
nm_draw:
    rts
nm_save:
    movea.l %sp@(8),%a0
    movea.l %a0@,%a0              | the characters
    lea.l   nm_buf,%a1            | copied, at most RS_NAMEMAX
    moveq   #RS_NAMEMAX-1,%d1
nsv_c:
    moveb   %a0@+,%d0
    moveb   %d0,%a1@+
    beqs    nsv_t
    subql   #1,%d1
    bpls    nsv_c
    clrb    %a1@
    addql   #1,%a1
nsv_t:
    subql   #1,%a1                | at its NUL: trailing spaces go
nsv_s:
    lea.l   nm_buf,%a0
    cmpal   %a0,%a1
    beqs    nsv_go                | nothing left: the default stands
    mvzb    %a1@(-1),%d0
    cmpil   #32,%d0               | ' '
    bnes    nsv_k
    subql   #1,%a1
    clrb    %a1@
    bras    nsv_s
nsv_k:
    lea.l   nm_buf,%a0            | the name
    lea.l   rs_name,%a1
nsv_k2:
    moveb   %a0@+,%d0
    moveb   %d0,%a1@+
    bnes    nsv_k2
nsv_go:
    braw    rs_save_go
nm_buf:       .space 16
    .balign 2

| ---- run the save in the UI task, below the audio ----
| led_hook's clock outranks the audio: a save there froze it, however it was
| sliced. The master UI task (0x40007d46, priority 6 against the audio's 7)
| takes messages from queue 0x404a9154, and type 6 carries a callback: data
| at +4, its manager at +0xc, the callback at +0x10 (called with the closure
| and the word at +0x14), and +0x18 cleared once it has run (0x400081fa). So
| each step of rs_save_do is one such message, and posts the next itself -
| on the other of two messages, since the one running is only released after
| its callback returns.
MQ_MAIN = 0x404a9154
sv_post:                          | a0 = the message
    tstl    %a0@(0x18)
    bnes    svp_out               | still queued or running
    movel   %a0,%sp@-
    pea     1
    jsr     ALLOC                 | closure data, released by the manager
    addql   #4,%sp
    movea.l %sp@+,%a0
    movel   %d0,%a0@(4)
    clrl    %a0@(8)
    movel   #GENERIC_MANAGER,%d0
    movel   %d0,%a0@(0x0c)
    movel   #sv_run,%d0
    movel   %d0,%a0@(0x10)
    clrl    %a0@(0x14)
    moveq   #1,%d0
    movel   %d0,%a0@(0x18)
    moveq   #6,%d0                | type 6: run the callback
    moveb   %d0,%a0@
    movel   %a0,%sp@-
    pea     MQ_MAIN
    jsr     0x40001fba            | post
    addql   #8,%sp
svp_out:
    rts

sv_run:                           | (closure, arg), in the UI task
    jsr     rs_save_do
    tstl    rs_sv_state
    beqs    svr_out               | done
    lea.l   sv_which,%a0          | the next step, on the other message
    movel   %a0@,%d0
    eoril   #1,%d0
    movel   %d0,%a0@
    lea.l   sv_msg_a,%a0
    tstl    %d0
    beqs    svr_p
    lea.l   sv_msg_b,%a0
svr_p:
    braw    sv_post
svr_out:
    rts

rs_val_sav:
    lea.l   rs_zero,%a0
    lea.l   rs_n_sav,%a1
    movel   rs_save_req,%d0
    orl     rs_sv_state,%d0
    beqw    gm_val
    lea.l   rs_n_busy,%a1
    braw    gm_val

rs_save_do:
    movel   rs_sv_state,%d0
    bnew    rsd_step
    tstl    rs_save_req
    bnew    rsd_start
    rts
rsd_step:
    cmpil   #1,%d0
    beqw    rsd_write
    braw    rsd_scan

| ---- tick 1: check, name, open, header ----
rsd_start:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
    lea.l   rs_save_req,%a0
    clrl    %a0@
    tstl    rs_state              | not while a take is being made
    bnew    rsd_none
    tstl    rs_pending
    bnew    rsd_none
    movel   rs_save_trk,%d7       | the track
    lea.l   track_slot,%a0
    movel   %a0@(0,%d7:l:4),%d6   | its slot
    bmiw    rsd_none
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d6:l:4),%d0
    andil   #0xffffff00,%d0
    cmpil   #RS_HASH,%d0
    bnew    rsd_none              | a file already: nothing to save
    lea.l   slot_count,%a0
    movel   %a0@(0,%d6:l:4),%d5   | samples
    lea.l   slot_base,%a0
    movea.l %a0@(0,%d6:l:4),%a3
    lea.l   %a3@(64),%a3          | PCM
    movel   %d5,%d4
    addl    %d4,%d4               | data bytes
    lea.l   rs_sv_trk,%a0
    movel   %d7,%a0@
    lea.l   rs_sv_slot,%a0
    movel   %d6,%a0@
    lea.l   rs_sv_pcm,%a0
    movel   %a3,%a0@
    lea.l   rs_sv_len,%a0         | bytes per plane
    movel   %d4,%a0@
    lea.l   rs_sv_pos,%a0
    clrl    %a0@
    lea.l   slot_soff,%a0         | stereo: the side plane follows the mid
    movel   %a0@(0,%d6:l:4),%d0
    movel   %d4,%d1
    tstl    %d0
    beqs    rsd_mono
    addl    %d4,%d1               | two planes of data
    addl    %a3,%d0               | where the side is
rsd_mono:
    movel   %d0,rs_sv_pcm2
    movel   %d1,rs_sv_tot
    | ---- the path: "/Resampled/" + the name chosen at SAV (rs_name) ----
    lea.l   rs_dir,%a0
    lea.l   rs_path,%a1
rsd_p:
    moveb   %a0@+,%d1
    beqs    rsd_p2
    moveb   %d1,%a1@+
    bras    rsd_p
rsd_p2:
    lea.l   rs_name,%a0
    moveq   #RS_NAMEMAX-1,%d2
rsd_n:
    moveb   %a0@+,%d1
    moveb   %d1,%a1@+
    beqs    rsd_nd
    subql   #1,%d2
    bpls    rsd_n
    clrb    %a1@
rsd_nd:
    | ---- the header: stock layout, our gain in its spare words ----
    lea.l   rs_hdr,%a0
    moveq   #19,%d0               | 80 bytes: header and trailer
rsd_z:
    clrl    %a0@+
    subql   #1,%d0
    bpls    rsd_z
    lea.l   rs_hdr,%a0
    movel   rs_sv_tot,%d0
    movel   %d0,%a0@(4)           | data length
    tstl    rs_sv_pcm2
    beqs    rsd_hm
    moveq   #1,%d0                | +0x20 bit 0: mid plane, then side plane
    movel   %d0,%a0@(32)
rsd_hm:
    movel   #48000,%d0
    movel   %d0,%a0@(8)
    movel   %d5,%d0
    subql   #1,%d0
    movel   %d0,%a0@(16)          | count - 1
    movel   #0x7f000000,%d0
    movel   %d0,%a0@(20)
    movel   #RS_GMAGIC,%d0
    movel   %d0,%a0@(24)
    lea.l   slot_pgain,%a1
    movel   %a1@(0,%d6:l:4),%d0
    movel   %d0,%a0@(28)
    | ---- open ----
    pea     FW_SIZE
    jsr     0x400802e0            | operator new
    addql   #4,%sp
    tstl    %d0
    beqw    rsd_fail
    movea.l %d0,%a4
    lea.l   rs_sv_fw,%a0
    movel   %a4,%a0@
    movel   rs_sv_tot,%d0
    addil   #80,%d0               | file size
    lea.l   rs_sv_fsize,%a0
    movel   %d0,%a0@
    movel   %d0,%sp@-
    pea     rs_path
    movel   %a4,%sp@-
    lea.l   FW_HOOK_ON+8,%a0      | without the stock mute (see FW_HOOK_ON)
    movel   %a0@,%d0
    lea.l   fw_hook_sv,%a1
    movel   %d0,%a1@
    clrl    %a0@
    jsr     0x4007c7ca
    movel   fw_hook_sv,%d0
    movel   %d0,FW_HOOK_ON+8
    lea.l   %sp@(12),%sp
    pea     64
    pea     rs_hdr
    bsr     rs_fw_put             | write + flush
    addql   #8,%sp
    lea.l   rs_sv_state,%a0       | one piece per message from now on
    moveq   #1,%d0
    movel   %d0,%a0@
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts

| (data, len <= 0x8000): the FileWriter's write, then its flush. Its write only
| ever fills the 32 KB buffer: when that fills it flushes and RETURNS, dropping
| the rest of the call - so pieces are kept to 32 KB and flushed each time.
rs_fw_put:
    movea.l rs_sv_fw,%a0
    movel   %sp@(8),%sp@-
    movel   %sp@(8),%sp@-
    movel   %a0,%sp@-
    movea.l %a0@,%a1
    movea.l %a1@(0x10),%a1
    jsr     %a1@
    lea.l   %sp@(12),%sp
    movea.l rs_sv_fw,%a0
    movel   %a0,%sp@-
    movea.l %a0@,%a1
    movea.l %a1@(0x0c),%a1        | flush
    jsr     %a1@
    addql   #4,%sp
    rts

| ---- one 32 KB piece per tick; the last closes the file ----
rsd_write:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
rsd_w0:
    movel   rs_sv_len,%d0
    subl    rs_sv_pos,%d0         | left
    bnes    rsd_wp
    movel   rs_sv_pcm2,%d0        | the mid is out: now the side, if any
    beqw    rsd_close
    movel   %d0,rs_sv_pcm
    clrl    rs_sv_pcm2
    clrl    rs_sv_pos
    bras    rsd_w0
rsd_wp:
    cmpil   #0x8000,%d0
    blss    rsd_w1
    movel   #0x8000,%d0
rsd_w1:
    movel   %d0,%d2
    movel   %d2,%sp@-
    movel   rs_sv_pcm,%d1
    addl    rs_sv_pos,%d1
    movel   %d1,%sp@-
    bsr     rs_fw_put
    addql   #8,%sp
    lea.l   rs_sv_pos,%a0
    addl    %d2,%a0@
    braw    rsd_ret
rsd_close:
    pea     16                    | trailer
    pea     rs_hdr+64
    bsr     rs_fw_put
    addql   #8,%sp
    movea.l rs_sv_fw,%a4
    movel   %a4,%sp@-
    movea.l %a4@,%a0
    movea.l %a0@(0x1c),%a0        | an error?
    jsr     %a0@
    addql   #4,%sp
    moveq   #0x14,%d1             | no: close and commit
    moveq   #1,%d2
    tstb    %d0
    beqs    rsd_c1
    moveq   #0x18,%d1             | yes: abort and delete
    moveq   #0,%d2
rsd_c1:
    movel   %a4,%sp@-
    movea.l %a4@,%a0
    movea.l %a0@(0,%d1:l),%a0
    jsr     %a0@
    lea.l   FW_HOOK_OFF+8,%a0     | nor the unmute that pairs with it
    movel   %a0@,%d0
    lea.l   fw_hook_sv,%a1
    movel   %d0,%a1@
    clrl    %a0@
    jsr     0x4007c76a            | dtor
    movel   fw_hook_sv,%d0
    movel   %d0,FW_HOOK_OFF+8
    jsr     0x400802ec            | operator delete
    addql   #4,%sp
    lea.l   rs_sv_fw,%a0
    clrl    %a0@
    tstl    %d2
    beqw    rsd_failw
    lea.l   rs_sv_blk,%a0         | now find it in the inode table, a page a tick
    movel   #TABLE_BLOCK,%d0
    movel   %d0,%a0@
    lea.l   rs_sv_ino,%a0
    moveq   #-1,%d0
    movel   %d0,%a0@
    lea.l   rs_sv_hash,%a0
    clrl    %a0@
    lea.l   rs_sv_empty,%a0
    clrl    %a0@
    lea.l   rs_sv_state,%a0
    moveq   #2,%d0
    movel   %d0,%a0@
    braw    rsd_ret
rsd_failw:
    lea.l   rs_sv_state,%a0
    clrl    %a0@
    pea     rs_m_savefail
    jsr     show_popup
    addql   #4,%sp
rsd_ret:
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts

| ---- a page of the inode table per tick: the newest file of our size ----
rsd_scan:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
    movel   rs_sv_blk,%d7
    movel   #TABLE_END,%d0
    cmpl    %d7,%d0
    blsw    rsd_found
    pea     TBL_BUF
    pea     65536
    movel   %d7,%sp@-
    jsr     0x4008b24a            | readBlocks
    lea.l   %sp@(12),%sp
    tstl    %d0
    bnew    rsd_found
    movea.l #TBL_BUF,%a2
    movel   #512,%d3
    movel   rs_sv_fsize,%d2
    moveq   #0,%d4                | anything in this page?
rss_rec:
    movel   %a2@,%d0
    beqs    rss_next
    moveq   #1,%d4
    cmpil   #0x00020001,%d0
    bnes    rss_next
    cmpl    %a2@(4),%d2
    bnes    rss_next
    movel   %a2@(16),%d0          | inode number
    movel   rs_sv_ino,%d1
    bmis    rss_take
    cmpl    %d1,%d0
    blss    rss_next
rss_take:
    lea.l   rs_sv_ino,%a0
    movel   %d0,%a0@
    lea.l   rs_sv_hash,%a0
    movel   %a2@(12),%d0
    movel   %d0,%a0@
rss_next:
    lea.l   %a2@(128),%a2
    subql   #1,%d3
    bnes    rss_rec
    lea.l   rs_sv_blk,%a0
    movel   #128,%d0
    addl    %d0,%a0@
    lea.l   rs_sv_empty,%a0       | four empty pages in a row: past the end
    tstl    %d4
    beqs    rss_e
    clrl    %a0@
    braw    rsd_ret
rss_e:
    addql   #1,%a0@
    moveq   #4,%d0
    cmpl    %a0@,%d0
    bhiw    rsd_ret
rsd_found:
    lea.l   rs_sv_state,%a0
    clrl    %a0@
    movel   rs_sv_hash,%d3
    beqs    rsd_msg               | saved, but not in the table (yet)
    movel   rs_sv_slot,%d6
    movel   rs_sv_trk,%d7
    lea.l   slot_hash,%a0         | relink the track to the file
    movel   %d3,%a0@(0,%d6:l:4)
    lea.l   slot_tpat,%a0         | a file now: no pattern owns it
    moveq   #-1,%d0
    movel   %d0,%a0@(0,%d6:l:4)
    movel   %d6,%d0               | and its name: "Take-XXXXXX", past
    lsll    #5,%d0                | "/Resampled/"
    addil   #NAME_BASE,%d0
    movea.l %d0,%a1
    lea.l   rs_path,%a0
    lea.l   %a0@(11),%a0
    moveq   #30,%d0
rsd_nm:
    moveb   %a0@+,%d1
    moveb   %d1,%a1@+
    beqs    rsd_nmd
    subql   #1,%d0
    bpls    rsd_nm
    clrb    %a1@
rsd_nmd:
    lea.l   track_hash,%a0
    movel   %d3,%a0@(0,%d7:l:4)
    lea.l   rs_tok,%a0
    clrl    %a0@(0,%d7:l:4)
    movel   %d7,%d0
    movel   %d3,%d1
    jsr     name_store            | the token: it persists with the project
rsd_msg:
    lea.l   rs_path,%a0           | "Saved\nTake-XXXXXX"
    lea.l   %a0@(11),%a0          | past "/Resampled/"
    lea.l   rs_args,%a1
    movel   %a0,%a1@
    pea     rs_args
    pea     rs_f_saved
    pea     msg_buf
    jsr     0x400005cc
    lea.l   %sp@(12),%sp
    pea     msg_buf
    bras    rsd_pop
rsd_none:
    pea     rs_m_nosave
    bras    rsd_pop
rsd_fail:
    pea     rs_m_savefail
rsd_pop:
    jsr     show_popup
    addql   #4,%sp
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts

    .align 4
rs_save_req:  .long 0          | SAV pressed: rs_save_do does it
sv_which:     .long 0
sv_msg_a:     .space 0x1c      | two UI-task messages for the save's steps
sv_msg_b:     .space 0x1c
fw_hook_sv:   .long 0          | a stock FileWriter hook, while ours is blanked
rs_sv_state:  .long 0          | 0 idle, 1 writing a piece a tick, 2 scanning
rs_sv_fw:     .long 0          | the FileWriter while open
rs_sv_trk:    .long 0
rs_sv_slot:   .long 0
rs_sv_pcm:    .long 0
rs_sv_len:    .long 0          | data bytes (per plane)
rs_sv_pcm2:   .long 0          | a stereo take's side plane, still to write
rs_sv_tot:    .long 0          | data bytes, both planes
rs_sv_pos:    .long 0          | ...written so far
rs_sv_fsize:  .long 0          | file size, to find it in the table
rs_sv_blk:    .long 0          | table page being scanned
rs_sv_ino:    .long 0          | newest match so far (-1: none)
rs_sv_hash:   .long 0
rs_sv_empty:  .long 0          | empty table pages in a row
rs_save_trk:  .long 0
rs_n_sav:     .long rs_s_go
rs_n_busy:    .long rs_s_busy2
rs_hdr:       .space 80        | header (64) and trailer (16)
rs_path:      .space 40
rs_name:      .space 28        | the take's name: the editor's, or the default

| from rs_watch, on the UI clock: while the Resample menu is up and the
| recorder is doing anything - or has just stopped - redraw it
rs_menu_tick:
    movel   rs_state,%d0
    orl     rs_pending,%d0
    movel   rs_lastact,%d1
    lea.l   rs_lastact,%a0
    movel   %d0,%a0@
    orl     %d1,%d0
    beqs    rmt_out               | idle now and last time
    lea.l   gm_cur,%a0
    lea.l   rs_desc,%a1
    cmpal   %a0@,%a1
    bnes    rmt_out
    jsr     gm_live
    tstl    %d0
    beqs    rmt_out
    movel   gm_obj,%d0
    addil   #0x38,%d0
    movel   %d0,%sp@-
    jsr     0x40076082
    addql   #4,%sp
rmt_out:
    rts

    .align 4
rs_desc:      .long rs_title, rs_vname, 9, rs_items
rs_items:     .long rs_lab_src, rs_val_src, rs_rot_src, new_slot2_invoker
              .long rs_lab_chn, rs_val_chn, rs_rot_chn, new_slot2_invoker
              .long rs_lab_len, rs_val_len, rs_rot_len, new_slot2_invoker
              .long rs_lab_sta, rs_val_sta, rs_rot_sta, new_slot2_invoker
              .long rs_lab_mut, rs_val_mut, rs_rot_mut, new_slot2_invoker
              .long rs_lab_trm, rs_val_trm, rs_rot_trm, new_slot2_invoker
              .long rs_lab_clr, rs_val_clr, rs_rot_none, rs_clear
              .long rs_lab_rec, rs_val_rec, rs_rot_none, rs_press
              .long rs_lab_sav, rs_val_sav, rs_rot_none, rs_save_press
rs_n_src:     .long rs_s_t1, rs_s_t2, rs_s_t3, rs_s_t4, rs_s_t5, rs_s_t6, rs_s_mst
              .long rs_s_usb
rs_n_len:     .long rs_s_1, rs_s_2, rs_s_4, rs_s_8, rs_s_16, rs_s_man, rs_s_ptn
rs_n_chn:     .long rs_s_mon, rs_s_ste
rs_n_sta:     .long rs_s_pat, rs_s_now, rs_s_snd
rs_n_rec:     .long rs_vbuf
rs_n_smp:     .long rs_s_smp
rs_n_emp:     .long rs_s_emp
rs_zero:      .long 0
rs_c_src:     .long RS_MST     | the menu's settings, shared by every track
rs_c_len:     .long 2          | 4 bars
rs_c_chn:     .long 1          | CHN: whole-output takes in stereo (STE)
rs_soff:      .long 0          | this take's side plane, bytes above the mid
rs_c_sta:     .long 0          | PAT
rs_c_mut:     .long 0          | MUT: after a take, mute every other track
rs_c_trim:    .long 2          | TRM: -6 -3 0 +3 +6 dB; 0 dB
rs_gain:      .long 256        | the capture gain, Q8 (rs_calc_gain)
rs_pg:        .long 4096       | the next take's playback gain, Q12
slot_pgain:   .space 4*MAX_SLOT    | per slot: a take's playback gain, Q12
rs_trimq12:   .long 2053, 2900, 4096, 5786, 8173
rs_n_trm:     .long rs_s_m6, rs_s_m3, rs_s_0, rs_s_p3, rs_s_p6
rs_target:    .long 0          | samples to take; 0 = until stopped
rs_barlen:    .long 0          | samples in a bar, for the progress
rs_prev:      .long 0          | the step counter at the last block (PAT)
rs_lastact:   .long 0
rs_vbuf:      .space 16
rs_lab_src:
    lea.l   rs_s_src,%a1
    jmp     gm_lab
rs_lab_len:
    lea.l   rs_s_len,%a1
    jmp     gm_lab
rs_lab_chn:
    lea.l   rs_s_chn,%a1
    jmp     gm_lab
rs_lab_sta:
    lea.l   rs_s_sta,%a1
    jmp     gm_lab
rs_lab_rec:
    lea.l   rs_s_rec,%a1
    jmp     gm_lab
rs_lab_clr:
    lea.l   rs_s_clr,%a1
    jmp     gm_lab
rs_lab_mut:
    lea.l   rs_s_mut,%a1
    jmp     gm_lab
rs_lab_sav:
    lea.l   rs_s_sav,%a1
    jmp     gm_lab
rs_lab_trm:
    lea.l   rs_s_trm,%a1
    jmp     gm_lab
rs_title:     .asciz "Resample"
rs_vname:     .asciz "ResampleMenuView"
rs_s_src:     .asciz "SRC"
rs_s_len:     .asciz "LEN"
rs_s_chn:     .asciz "CHN"
rs_s_mon:     .asciz "MON"
rs_s_ste:     .asciz "STE"
rs_s_sta:     .asciz "STA"
rs_s_rec:     .asciz "REC"
rs_s_clr:     .asciz "CLR"
rs_s_mut:     .asciz "MUT"
rs_s_sav:     .asciz "SAV"
rs_s_busy2:   .asciz "..."
rs_m_nosave:  .asciz "No take on\nthis track"
rs_m_savefail: .asciz "Save failed"
rs_f_saved:   .asciz "Saved\n%s"
rs_dir:       .asciz "/Resampled/"
rs_take:      .asciz "Take-"
rs_nm_title:  .asciz "Save Take"
rs_nm_prompt: .asciz "Save take as"
rs_s_trm:     .asciz "TRM"
rs_s_m6:      .asciz "-6"
rs_s_m3:      .asciz "-3"
rs_s_0:       .asciz "0"
rs_s_p3:      .asciz "+3"
rs_s_p6:      .asciz "+6"
rs_s_smp:     .asciz "SMP"
rs_s_emp:     .asciz "---"
rs_m_clr:     .asciz "Sample cleared"
rs_s_t1:      .asciz "T1"
rs_s_t2:      .asciz "T2"
rs_s_t3:      .asciz "T3"
rs_s_t4:      .asciz "T4"
rs_s_t5:      .asciz "T5"
rs_s_t6:      .asciz "T6"
rs_s_mst:     .asciz "MST"
rs_s_usb:     .asciz "USB"
rs_s_1:       .asciz "1"
rs_s_2:       .asciz "2"
rs_s_4:       .asciz "4"
rs_s_8:       .asciz "8"
rs_s_16:      .asciz "16"
rs_s_man:     .asciz "MAN"
rs_s_ptn:     .asciz "PTN"
rs_s_pat:     .asciz "PAT"
rs_s_now:     .asciz "NOW"
rs_s_snd:     .asciz "SND"
rs_s_go:      .asciz "GO"
rs_s_arm:     .asciz "ARM"
rs_s_busy:    .asciz "..."
rs_f_bar:     .asciz "%d/%d"
rs_f_sec:     .asciz "%ds"
    .align 4

| MUT: every track but rs_dst muted, rs_dst unmuted - through the stock setter
| the mute mode uses, 0x4001381c(kit, track, muted, send), so the LEDs, the
| screen and the MIDI mute CC all follow as they do for a hand-made mute.
| The kit object is 0x4000eb90(0x400cf866()), as 0x4002350a gets it. UI side.
rs_solo:
    lea.l   %sp@(-8),%sp
    moveml  %d2-%d3,%sp@
    moveq   #0,%d2
rso_l:
    moveq   #1,%d3                | muted...
    cmpl    rs_dst,%d2
    bnes    rso_set
    moveq   #0,%d3                | ...except the take's own track
rso_set:
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    addql   #4,%sp
    pea     1                     | send the mute CC, as a hand-made mute does
    movel   %d3,%sp@-
    movel   %d2,%sp@-
    movel   %d0,%sp@-
    jsr     0x4001381c
    lea.l   %sp@(16),%sp
    addql   #1,%d2
    cmpil   #MAX_TRK,%d2
    bcss    rso_l
    moveml  %sp@,%d2-%d3
    lea.l   %sp@(8),%sp
    rts

| rs_area -> d0 = where a take starts, d1 = where it must stop. Above every
| slot (alloc_top, in the cached part while files go there first) when 16 MiB
| or more is free there; otherwise whichever is bigger, that or the free top
| of the uncached part (above its highest slot, up to PCM_CACHED). Keeps d2-d7.
rs_area:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    bsr     top_calc              | alloc_top: the end of the highest slot
    movel   alloc_top,%d0
    movel   #PCM_TOP-64,%d1       | a block short of the retrig histories
    movel   %d1,%d3
    subl    %d0,%d3               | free up there
    bmis    rsa_lo
    cmpil   #0x01000000,%d3
    bccs    rsa_out
rsa_lo:
    movel   #PCM_BASE,%d4         | the uncached part's top: the end of its
    moveq   #0,%d2                | highest slot
rsa_l:
    lea.l   slot_hash,%a0
    tstl    %a0@(0,%d2:l:4)
    beqs    rsa_n
    lea.l   slot_base,%a0
    movel   %a0@(0,%d2:l:4),%d1
    cmpil   #PCM_CACHED,%d1
    bccs    rsa_n
    lea.l   slot_size,%a0
    addl    %a0@(0,%d2:l:4),%d1
    cmpl    %d4,%d1
    blss    rsa_n
    movel   %d1,%d4
rsa_n:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    rsa_l
    addil   #15,%d4
    andil   #0xfffffff0,%d4
    movel   #PCM_CACHED-64,%d1
    subl    %d4,%d1               | free down there
    bmis    rsa_hi
    cmpl    %d3,%d1
    blss    rsa_hi
    movel   %d4,%d0
    movel   #PCM_CACHED-64,%d1
    bras    rsa_out
rsa_hi:
    movel   #PCM_TOP-64,%d1
rsa_out:
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
    rts

| rs_keep: from rebuild_slots, before it drops the slots. Every recording a
| track still plays is moved down to the bottom of the region, lowest first -
| always downwards, so a forward copy is safe - and rs_top is left just above
| them for the files that are reloaded next. Recordings nothing plays go.
rs_keep:
    lea.l   %sp@(-32),%sp
    moveml  %d2-%d7/%a2-%a3,%sp@
    movel   #PCM_BASE,%d7         | where the next one goes
    lea.l   rk_mark,%a0           | slots done
    moveq   #MAX_SLOT/4-1,%d0
rk_z:
    clrl    %a0@+
    subql   #1,%d0
    bpls    rk_z
rk_pass:
    moveq   #-1,%d4               | lowest base found this pass
    moveq   #-1,%d5               | ...and its slot
    moveq   #0,%d2
rk_s:
    lea.l   rk_mark,%a0
    tstb    %a0@(0,%d2:l)
    bnes    rk_sn
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d2:l:4),%d0
    movel   %d0,%d1
    andil   #0xffffff00,%d1
    cmpil   #RS_HASH,%d1
    bnes    rk_sn
    movel   %d2,%d0               | wanted - played here, or its own pattern's
    bsr     slot_level            | track still names what it stands in for?
    cmpil   #2,%d0
    bccs    rk_used
    movel   %d2,%d0               | not any more: drop it
    bsr     slot_drop
    bras    rk_sn
rk_used:
    lea.l   slot_base,%a0
    movel   %a0@(0,%d2:l:4),%d0
    cmpl    %d4,%d0
    bccs    rk_sn
    movel   %d0,%d4
    movel   %d2,%d5
rk_sn:
    addql   #1,%d2
    cmpil   #MAX_SLOT,%d2
    bcss    rk_s
    tstl    %d5
    bmiw    rk_done
    lea.l   rk_mark,%a0
    moveq   #1,%d0
    moveb   %d0,%a0@(0,%d5:l)
    lea.l   slot_count,%a0
    movel   %a0@(0,%d5:l:4),%d2   | samples
    addil   #32,%d2               | + the 64-byte header, in words
    movea.l %d4,%a0
    movea.l %d7,%a1
    cmpal   %a0,%a1
    beqs    rk_same
rk_cp:
    movew   %a0@+,%a1@+
    subql   #1,%d2
    bnes    rk_cp
rk_same:
    lea.l   slot_base,%a0
    movel   %d7,%a0@(0,%d5:l:4)
    lea.l   slot_count,%a0
    movel   %a0@(0,%d5:l:4),%d2   | samples
    movel   %d2,%d3
    addl    %d3,%d3
    addil   #15,%d3
    andil   #0xfffffff0,%d3       | a side plane's new offset: just past the mid
    lea.l   slot_soff,%a0
    movel   %a0@(0,%d5:l:4),%d0
    beqs    rk_mono
    movel   %d3,%a0@(0,%d5:l:4)
    movea.l %d4,%a0               | from: old base + 64 + old offset
    lea.l   %a0@(64),%a0
    adda.l  %d0,%a0
    movea.l %d7,%a1               | to: new base + 64 + new offset - never above
    lea.l   %a1@(64),%a1          | it, and past the mid just copied
    adda.l  %d3,%a1
    cmpal   %a0,%a1
    beqs    rk_sd
    tstl    %d2
    beqs    rk_sd
rk_sc:
    movew   %a0@+,%a1@+
    subql   #1,%d2
    bnes    rk_sc
rk_sd:
    addl    %d3,%d7               | past the side's offset...
rk_mono:
    lea.l   slot_count,%a0
    movel   %a0@(0,%d5:l:4),%d0
    addl    %d0,%d0
    addl    %d0,%d7               | ...and one plane
    addil   #64+15,%d7
    andil   #0xfffffff0,%d7
    movel   %d7,%d0               | what it occupies now
    lea.l   slot_base,%a0
    subl    %a0@(0,%d5:l:4),%d0
    lea.l   slot_size,%a0
    movel   %d0,%a0@(0,%d5:l:4)
    braw    rk_pass
rk_done:
    lea.l   rs_top,%a0
    movel   %d7,%a0@
    moveml  %sp@,%d2-%d7/%a2-%a3
    lea.l   %sp@(32),%sp
    rts

rs_f_trk:     .asciz "T%d>T%d %d.%ds"
rs_f_mst:     .asciz "OUT>T%d %d.%ds"
rs_f_usb:     .asciz "USB>T%d %d.%ds"
rs_m_need:    .asciz "Select a\nSample track"
rs_m_short:   .asciz "Too short"
rs_m_noslot:  .asciz "No free slot"
    .align 4
rs_state:     .long 0          | 1 = the audio side appends
rs_pending:   .long 0          | a recording to commit (UI side)
rs_src:       .long 0          | 0..5 = a track, RS_MST = the whole output,
                               | RS_USB = the computer's audio
ro_srcp:      .long RS_BUS     | where rs_out captures from this block
rs_dst:       .long 0          | the track that gets it
rs_base:      .long 0          | its header
rs_ptr:       .long 0          | the next sample
rs_lim:       .long 0          | stop here
rs_n:         .long 0          | samples so far
rs_seq:       .long 0          | numbers the recordings' hashes
rs_top:       .long PCM_BASE   | rs_keep: above the recordings it kept
slot_soff:    .space 4*MAX_SLOT    | per slot: side plane offset; 0 = mono
sx_ok:        .long 0          | render: this block is stereo
sx_pass:      .long 0          | render: filling the side plane
sx_soff:      .long 0          | render: its offset
sx_inside:    .long 0          | amp_hook: running the side
sx_dsv:       .long 0          | voice+0x318 while the side decimates
sx_on:        .long 0,0,0,0,0,0,0  | per track: stereo this block (the mixer)
sx_sv:        .space 24        | the fill's state, between the two passes
sx_vsv:       .space 28        | gain-stage words and atk_gain, likewise
sx_y1:        .long 0,0,0,0,0,0    | the side's ladder, as filt_y1..4
sx_y2:        .long 0,0,0,0,0,0
sx_y3:        .long 0,0,0,0,0,0
sx_y4:        .long 0,0,0,0,0,0
sx_dstate:    .space 6*48      | the side's decimator state, per track
fx_buf:       .long sampler_buf+32 | what lofi/tape/vinyl_apply process
gf_dst:       .long sampler_buf+32 | where gran_fill's grains go
wf_dst:       .long sampler_buf+32 | where wave_fill writes
pk_dst:       .long sampler_buf+32 | where pluck_fill writes
pk_dbase:     .long DLY_BASE   | pluck_fill's bank of delay lines
pk_initp:     .long pk_init    | ...and its "line zeroed" flags
sx_side_off:  .long 0          | Pluck/Wavetable: the side plane, this block
sx_pklp:      .long 0,0,0,0,0,0,0  | the side string's lowpass, write
sx_pkwp:      .long 0,0,0,0,0,0,0  | position, strike left and strike index
sx_pkel:      .long 0,0,0,0,0,0,0
sx_pkei:      .long 0,0,0,0,0,0,0
sx_pkinit:    .byte 0,0,0,0,0,0,0,0
sx_wvph:      .space 12        | Wavetable: the phases, while the side renders
sx_gpcm:      .long 0          | gran_fill: the side plane, this block
sx_ga2:       .long 0          | ...the track's real grain records
sx_gwh:       .long 0          | ...the whole step, as passed
sx_gmid:      .long 0          | ...the mid plane
sx_grec:      .space GR_MAX*GR_STRIDE  | the copy the side renders from
sx_lfh:       .long 0,0,0,0,0,0,0  | the right channel's Lo-fi hold
sx_tpl:       .long 0,0,0,0,0,0,0  | ...Tape lowpass
sx_vnl:       .long 0,0,0,0,0,0,0  | ...Vinyl lowpass
sx_tmp:       .long 0
sv_idle:      .byte 0,0,0,0,0,0,0,0  | per track: idle since the last block
sx_cap:       .space 128       | the side, dry, for a stereo track capture
sx_tmp2:      .long 0
    .balign 16
sx_side:      .space 6*128     | per track, laid out like 0x80001858
sx_buf:       .space 512       | the side's 2x buffer, as sampler_buf
rs_tok:       .long 0,0,0,0,0,0,0  | the hash a recording replaced, per track
rs_args:      .long 0,0,0,0        | vsprintf arguments for the popups
rs_slot:      .long 0          | the slot the take becomes (chosen when armed)
rs_hash:      .long 0          | ...and its hash
rs_handed:    .long 0          | the take is on the track
rs_len:       .long 0          | its length, for the popup
rs_silence:   .long 0          | tracks amp_hook keeps silent (bit n = track n)
rk_mark:      .space MAX_SLOT  | rs_keep: slots already moved
mute_sil:     .long 0          | Sampler tracks muted by hand (mute_poll)
rs_eu_done:   .long 0          | this take's destination has been unmuted early
rs_T:         .long 0          | PAT: step 1's event time, on the audio clock

| ============== Start/End: the sample's waveform, full screen =============
| Turning Start or End on a Sampler track shows the whole sample instead of the
| stock value popup. The popup is slot 0x90 of the parameter view's vtable
| (0x4001d818, entry 0x401005bc), called by the view's render 0x4001e40a as
| (this, ctx, id, value, locked, 1) after it has painted the name box on the
| left; the render then finishes by XOR-inverting the left 64x64 box
| (0x40070dea(ctx, 0,0,63,63, -1)). So wf_popup clears the whole screen, draws,
| and pre-inverts that box itself - the render's own inversion then puts it
| right. Anything else (other parameters, other machines, Stretch and
| Wavetable, no sample loaded) goes to the stock popup untouched.
|
| Screen 128x64. Row 0-8: the label and the value (small font, the value boxed
| when p-locked, as the stock popup frames it). Rows 10-63: the waveform, one
| column per 1/128 of the sample, min..max of up to 128 samples read across
| that stretch, scaled to the loudest column so quiet samples still fill it.
|   One shot, Loop: Start and End as lines (the one being turned solid, the
|     other dotted); outside the window the waveform is drawn dotted
|   Slice: every slice boundary as a dotted line
|   Granular, Pluck: Start is Position / Strike - one solid line
| Dial values map straight to columns: the render plays value/32768 of the
| sample, so column = value >> 8.
| Rows here are counted from the top, but the screen - 0x40070dea, 0x40071a04
| and the framebuffer alike - counts y from the BOTTOM, so each is mirrored
| where it is drawn (63 - y; text 55 - y, its 9 px above its y).
WF_TOP  = 10
WF_MID  = 37
WF_HALF = 26
wf_popup:
    movel   %sp@(12),%d0          | id
    moveq   #0,%d1
    cmpil   #0x2e,%d0             | Start
    beqs    wp_id
    moveq   #1,%d1
    cmpil   #0x3e,%d0             | End
    bnew    wp_stock
wp_id:
    lea.l   wf_act,%a0
    movel   %d1,%a0@
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    addql   #8,%sp
    cmpil   #MAX_TRK,%d0
    bccw    wp_stock
    lea.l   wf_trk,%a0
    movel   %d0,%a0@
    jsr     sound_obj
    tstl    %d0
    beqw    wp_stock
    movea.l %d0,%a0
    lea.l   wf_snd,%a1
    movel   %d0,%a1@
    mvzb    %a0@(38),%d0
    cmpil   #6,%d0
    bnew    wp_stock              | not a Sampler track
    bsr     wf_pick               | the sample: the held step's lock, or own
    tstl    wf_slot
    bmiw    wp_stock              | none resident
    lea.l   wf_trk,%a0
    movel   %a0@,%d0
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d0:l:4),%d0
    lea.l   wf_mode,%a0
    movel   %d0,%a0@
    cmpil   #2,%d0
    blsw    wf_draw               | One shot, Loop, Slice
    cmpil   #3,%d0
    beqs    wp_pos
    cmpil   #5,%d0
    bnew    wp_stock              | Stretch, Wavetable
wp_pos:
    lea.l   wf_act,%a0            | Granular, Pluck: Start (the position) only
    tstl    %a0@
    beqw    wf_draw
wp_stock:
    jmp     0x4001d818

wf_draw:
    linkw   %fp,#-8
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
    movea.l %fp@(12),%a4          | ctx
    movea.l %a4@(16),%a5          | its framebuffer: columns of stride words,
    movel   %a4@(12),%d6          | bit 31-(y&31) of word x*stride + y/32
    pea     0                     | clear the screen
    pea     63
    pea     127
    clrl    %sp@-
    clrl    %sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    | ---- the sample ----
    movel   wf_slot,%d0
    lea.l   slot_base,%a0
    movel   %a0@(0,%d0:l:4),%d1
    addil   #64,%d1               | past the file header
    movea.l %d1,%a3               | big-endian 16-bit samples
    lea.l   slot_count,%a0
    movel   %a0@(0,%d0:l:4),%d5   | how many
    | Slice: Start and End trim within the slice being played, so show that
    | slice, zoomed to the full width, once one has played (wf_zoom = 1).
    lea.l   wf_zoom,%a0
    clrl    %a0@
    lea.l   wf_mode,%a0
    moveq   #2,%d0
    cmpl    %a0@,%d0
    bnes    wf_rng
    lea.l   wf_trk,%a0
    movel   %a0@,%d0
    lea.l   track_slot,%a0        | the slice played was of another sample
    movel   %a0@(0,%d0:l:4),%d1
    cmpl    wf_slot,%d1
    bnes    wf_rng
    lea.l   wf_sll,%a0
    movel   %a0@(0,%d0:l:4),%d1
    beqs    wf_rng                | nothing played yet: the whole sample
    lea.l   wf_slb,%a0
    movel   %a0@(0,%d0:l:4),%d2
    movel   %d2,%d3
    addl    %d1,%d3
    cmpl    %d5,%d3
    bhis    wf_rng                | stale (another sample since): whole sample
    addl    %d2,%d2
    addal   %d2,%a3               | the slice's first sample
    movel   %d1,%d5               | ...and its length
    lea.l   wf_zoom,%a0
    moveq   #1,%d0
    movel   %d0,%a0@
wf_rng:
    | ---- min/max per column, and the loudest: once per sample and view ----
    | Turning Start or End redraws this popup on every step, and reading up to
    | 16,384 scattered samples each time is what slowed the UI. The columns
    | only change with the stretch shown, so they are kept, as pixel extents,
    | until the slot's hash (every take has its own), the first sample or the
    | length changes.
    movel   wf_slot,%d0
    lea.l   slot_hash,%a0
    movel   %a0@(0,%d0:l:4),%d0
    cmpl    wf_ck_h,%d0
    bnes    wf_scan
    cmpal   wf_ck_a,%a3
    bnes    wf_scan
    cmpl    wf_ck_n,%d5
    beqw    wf_cached
wf_scan:
    movel   %d0,wf_ck_h
    movel   %a3,wf_ck_a
    movel   %d5,wf_ck_n
    moveq   #0,%d2                | column
    movel   #256,%d7              | loudest, floored so silence is not blown up
wf_pk:
    movel   %d2,%d3
    mulul   %d5,%d3
    lsrl    #7,%d3                | first sample of the column
    movel   %d2,%d4
    addql   #1,%d4
    mulul   %d5,%d4
    lsrl    #7,%d4                | ...one past its last
    subl    %d3,%d4               | n
    bgts    wf_pn
    moveq   #1,%d4
wf_pn:
    movel   %d4,%d1
    lsrl    #7,%d1                | step: at most 128 reads per column
    bnes    wf_ps
    moveq   #1,%d1
wf_ps:
    movel   %d1,%fp@(-4)
    movel   #32767,%a1            | min
    movel   #-32768,%a2           | max
wf_pr:
    cmpl    %d5,%d3
    bccs    wf_pd                 | past the end (a one-sample column)
    mvsw    %a3@(0,%d3:l:2),%d0
    cmpl    %a1,%d0
    bges    wf_p1
    movea.l %d0,%a1
wf_p1:
    cmpl    %a2,%d0
    bles    wf_p2
    movea.l %d0,%a2
wf_p2:
    addl    %fp@(-4),%d3
    subl    %fp@(-4),%d4
    bgts    wf_pr
wf_pd:
    cmpal   #32767,%a1
    bnes    wf_pv
    suba.l  %a1,%a1               | nothing read: a flat line
    suba.l  %a2,%a2
wf_pv:
    lea.l   wf_mn,%a0
    movel   %a1,%d0
    movew   %d0,%a0@(0,%d2:l:2)
    bpls    wf_pa
    negl    %d0
wf_pa:
    cmpl    %d7,%d0
    bles    wf_pb
    movel   %d0,%d7
wf_pb:
    lea.l   wf_mx,%a0
    movel   %a2,%d0
    movew   %d0,%a0@(0,%d2:l:2)
    bpls    wf_pc
    negl    %d0
wf_pc:
    cmpl    %d7,%d0
    bles    wf_pe
    movel   %d0,%d7
wf_pe:
    addql   #1,%d2
    cmpil   #128,%d2
    bcsw    wf_pk
    moveq   #0,%d2                | ...as rows: top and bottom of each column
wf_ext:
    lea.l   wf_mx,%a0
    mvsw    %a0@(0,%d2:l:2),%d3
    moveq   #WF_HALF,%d0
    mulsl   %d0,%d3
    divsl   %d7,%d3
    negl    %d3
    addil   #WF_MID,%d3           | top
    lea.l   wf_mn,%a0
    mvsw    %a0@(0,%d2:l:2),%d4
    moveq   #WF_HALF,%d0
    mulsl   %d0,%d4
    divsl   %d7,%d4
    negl    %d4
    addil   #WF_MID,%d4           | bottom
    cmpil   #WF_TOP,%d3
    bges    wf_x1
    moveq   #WF_TOP,%d3
wf_x1:
    cmpil   #63,%d4
    bles    wf_x2
    moveq   #63,%d4
wf_x2:
    moveq   #63,%d0               | the screen counts y from the bottom: rows
    subl    %d4,%d0               | d3..d4 from the top are 63-d4..63-d3, and
    moveq   #63,%d4               | positive samples point up (until samplerHP
    subl    %d3,%d4               | the whole view was upside down)
    movel   %d0,%d3
    lea.l   wf_top,%a0
    moveb   %d3,%a0@(0,%d2:l)
    lea.l   wf_bot,%a0
    moveb   %d4,%a0@(0,%d2:l)
    addql   #1,%d2
    cmpil   #128,%d2
    bcss    wf_ext
wf_cached:
    | ---- the window, in columns (One shot / Loop), else all of it ----
    bsr     wf_windowed
    moveq   #0,%d0
    movel   #127,%d1
    tstl    %d2
    beqs    wf_win
    bsr     wf_se                 | d3 = Start column, d4 = End column
    movel   %d3,%d0
    movel   %d4,%d1
    cmpl    %d1,%d0
    blss    wf_win
    movel   %d4,%d0               | reversed: Start > End
    movel   %d3,%d1
wf_win:
    movel   %d0,%fp@(-4)          | window lo
    movel   %d1,%fp@(-8)          | window hi
    | ---- the columns ----
    moveq   #0,%d2
wf_col:
    moveq   #0,%d3
    lea.l   wf_top,%a0
    moveb   %a0@(0,%d2:l),%d3     | top
    moveq   #0,%d4
    lea.l   wf_bot,%a0
    moveb   %a0@(0,%d2:l),%d4     | bottom
    cmpl    %fp@(-4),%d2
    blts    wf_dot
    cmpl    %fp@(-8),%d2
    bgts    wf_dot
    pea     1                     | inside: solid
    movel   %d4,%sp@-
    movel   %d2,%sp@-
    movel   %d3,%sp@-
    movel   %d2,%sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    bras    wf_cn
wf_dot:
    bsr     wf_vdots              | outside: every other pixel
wf_cn:
    addql   #1,%d2
    cmpil   #128,%d2
    bcsw    wf_col
    | ---- markers ----
    bsr     wf_windowed
    tstl    %d2
    beqs    wf_m1
    bsr     wf_se                 | One shot / Loop / a zoomed slice: Start, End
    lea.l   wf_act,%a0
    tstl    %a0@
    beqs    wf_ms
    movel   %d3,%d0               | End is the one being turned
    movel   %d4,%d3
    movel   %d0,%d4
wf_ms:
    movel   %d3,%d0
    bsr     wf_solid
    movel   %d4,%d0
    bsr     wf_dotted
    braw    wf_text
wf_m1:
    lea.l   wf_mode,%a0
    movel   %a0@,%d0
    cmpil   #2,%d0
    bnes    wf_m3
    lea.l   wf_trk,%a0            | Slice: the boundaries of its row
    movel   %a0@,%d0
    lea.l   sl_S,%a0
    movel   %a0@(0,%d0:l:4),%d2   | slices in the row; 0 = not built yet
    beqw    wf_text
    movel   #SLROW,%d1
    mulul   %d1,%d0
    lea.l   sl_tbl,%a2
    addal   %d0,%a2
    moveq   #1,%d3                | boundary 0 is the start of the sample
wf_sl:
    cmpl    %d2,%d3
    bccw    wf_text
    movel   %a2@(0,%d3:l:4),%d0
    lsll    #7,%d0
    divul   %d5,%d0
    bsr     wf_dotted
    addql   #1,%d3
    bras    wf_sl
wf_m3:
    movel   %fp@(20),%d0          | Granular / Pluck: the position being turned
    bsr     wf_col_of
    bsr     wf_solid
    | ---- the label and the value ----
wf_text:
    lea.l   wf_mode,%a0
    movel   %a0@,%d0
    lea.l   wf_lbl_se,%a0
    cmpil   #2,%d0
    blss    wf_t1
    lea.l   wf_lbl_pos,%a0
    cmpil   #3,%d0
    beqs    wf_t1
    lea.l   wf_lbl_str,%a0
wf_t1:
    lea.l   wf_act,%a1
    movel   %a1@,%d0
    movel   %a0@(0,%d0:l:4),%sp@-
    pea     wf_fmt_s
    pea     0x10                  | clear behind the text
    pea     55                    | y from the bottom: the top line
    pea     1
    pea     0x40ea14cc            | the small font
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
    lea.l   wf_zoom,%a0           | a zoomed slice: which one, centred
    tstl    %a0@
    beqs    wf_tv
    lea.l   wf_trk,%a0
    movel   %a0@,%d0
    lea.l   wf_sli,%a0
    movel   %a0@(0,%d0:l:4),%d0
    addql   #1,%d0
    movel   %d0,%sp@-
    pea     wf_fmt_sl
    pea     0x12                  | centred, cleared behind
    pea     55
    pea     64
    pea     0x40ea14cc
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(28),%sp
wf_tv:
    movel   %fp@(20),%d0          | value, as fine_draw shows it: whole.tenths
    bges    wf_t2
    moveq   #0,%d0
wf_t2:
    movel   %d0,%d1
    andil   #0xff,%d1
    movel   %d1,%d2
    lsll    #2,%d1
    addl    %d2,%d1
    addl    %d1,%d1               | * 10
    lsrl    #8,%d1
    lsrl    #8,%d0
    movel   %d1,%sp@-
    movel   %d0,%sp@-
    pea     wf_fmt_v
    moveq   #0x14,%d0             | right-aligned, cleared behind
    tstb    %fp@(27)              | p-locked: boxed, as the stock popup marks it
    beqs    wf_t3
    moveq   #0x1c,%d0
wf_t3:
    movel   %d0,%sp@-
    pea     55
    pea     126
    pea     0x40ea14cc
    movel   %a4,%sp@-
    jsr     0x40071a04
    lea.l   %sp@(32),%sp
    | ---- pre-invert the left box, which the render inverts once more ----
    pea     -1
    pea     63
    pea     63
    clrl    %sp@-
    clrl    %sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    moveml  %sp@,%d2-%d7/%a2-%a5
    unlk    %fp
    rts

| wf_pick: the sample the Start/End popup shows, into wf_slot (-1 = none
| resident), and the sound the other of Start/End is read from, into wf_snd.
| While steps are held - the edit object 0x400cf9a8() keeps them as a 64-bit
| mask, +348 steps 32-63 and +352 steps 0-31, as 0x4006be48 walks them - the
| first held step's sound lock counts: 0x40015996(track pattern, step), the
| getter the browser's lock path uses (0x400a33a6), gives its pool index or
| -1, and a lock plays the kit's pool sound +694 + i x 100 when that entry is
| in use (+4 set), exactly as 0x40054be0 builds the trig. That sound's token
| names the sample. Otherwise the pattern's own sample (track_hash), as
| sp_lock goes back to it - not whatever the last, maybe locked, note left in
| track_slot, which is only the fallback. wf_trk and wf_snd (the track's
| sound) must be set. Keeps d2-d7.
wf_pick:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@
    movel   wf_trk,%d2
    lea.l   track_slot,%a0        | the fallback
    movel   %a0@(0,%d2:l:4),%d4
    lea.l   track_hash,%a0        | the pattern's own sample, if resident
    movel   %a0@(0,%d2:l:4),%d0
    bsr     wfk_find
    bmis    wfk_own
    movel   %d0,%d4
wfk_own:
    moveq   #1,%d0
    cmpl    kit_ok,%d0
    bnew    wfk_out               | the kit's layout unconfirmed: no locks
    jsr     0x400cf9a8            | the held steps
    movea.l %d0,%a0
    movel   %a0@(352),%d0
    moveq   #0,%d3
    tstl    %d0
    bnes    wfk_bit
    movel   %a0@(348),%d0
    moveq   #32,%d3
    tstl    %d0
    beqw    wfk_out               | none held
wfk_bit:
    btst    #0,%d0                | the lowest held
    bnes    wfk_step
    lsrl    #1,%d0
    addql   #1,%d3
    bras    wfk_bit
wfk_step:
    jsr     0x400cf866            | the selected track's pattern track
    movel   %d0,%sp@-
    jsr     0x4000f23e
    addql   #4,%sp
    movel   %d3,%sp@-
    movel   %d0,%sp@-
    jsr     0x40015996            | its lock: the pool index, or -1
    addql   #8,%sp
    extbl   %d0
    tstl    %d0
    bmis    wfk_out
    cmpil   #64,%d0
    bccs    wfk_out
    moveq   #SND_SIZE,%d1
    mulul   %d1,%d0
    addl    CUR_KIT,%d0
    addil   #KIT_POOL,%d0
    movea.l %d0,%a2
    tstb    %a2@(4)
    beqs    wfk_out               | an empty pool entry: the trig plays its own
    movea.l %a2,%a0
    bsr     tok_of
    tstl    %d0
    beqs    wfk_out               | not a sample's sound
    bsr     wfk_find
    movel   %d0,%d4               | not resident: none (the preloader's job)
    bmis    wfk_out
    movel   %a2,wf_snd            | a locked step plays the pool sound's own
wfk_out:                          | Start and End under its p-locks
    movel   %d4,wf_slot
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    rts
| d0 = hash -> d0 = its slot, or -1 (flags set from d0). Keeps d2-d7.
wfk_find:
    tstl    %d0
    beqs    wfk_nf
    moveq   #0,%d1
    lea.l   slot_hash,%a0
wfk_fl:
    cmpl    %a0@(0,%d1:l:4),%d0
    beqs    wfk_hit
    addql   #1,%d1
    cmpil   #MAX_SLOT,%d1
    bcss    wfk_fl
wfk_nf:
    moveq   #-1,%d0
    rts
wfk_hit:
    movel   %d1,%d0
    rts

| d3 = Start column, d4 = End column: the value being turned from the popup,
| the other from the sound (k=11 Start at +42, k=12 End at +44)
wf_se:
    movea.l wf_snd,%a0
    mvsw    %a0@(42),%d0
    tstl    wf_act
    bnes    wf_se1
    movel   %fp@(20),%d0
wf_se1:
    bsr     wf_col_of
    movel   %d0,%d3
    movea.l wf_snd,%a0
    mvsw    %a0@(44),%d0
    tstl    wf_act
    beqs    wf_se2
    movel   %fp@(20),%d0
wf_se2:
    bsr     wf_col_of
    movel   %d0,%d4
    rts

| d2 = 1 when Start/End are drawn as a window: One shot, Loop, zoomed slice
wf_windowed:
    moveq   #1,%d2
    lea.l   wf_mode,%a0
    moveq   #1,%d0
    cmpl    %a0@,%d0
    bccs    wf_wd
    lea.l   wf_zoom,%a0
    movel   %a0@,%d2
wf_wd:
    rts

| d0 = dial value -> column 0..127
wf_col_of:
    tstl    %d0
    bges    wf_co1
    moveq   #0,%d0
wf_co1:
    asrl    #8,%d0
    cmpil   #127,%d0
    bles    wf_co2
    moveq   #127,%d0
wf_co2:
    rts

| d0 = column: a solid / dotted line down the waveform area, XOR so it shows
| over the waveform and on black alike
wf_solid:
    movel   %d0,%sp@-
    pea     -1
    pea     63-WF_TOP             | rows WF_TOP..63 from the top
    movel   %d0,%sp@-
    clrl    %sp@-
    movel   %d0,%sp@-
    movel   %a4,%sp@-
    jsr     0x40070dea
    lea.l   %sp@(24),%sp
    movel   %sp@+,%d0
    rts
wf_dotted:
    movel   %d2,%sp@-
    movel   %d0,%d2
    moveq   #0,%d1                | rows WF_TOP..63 from the top
wf_dt:
    movel   %d1,%sp@-
    movel   %d2,%d0
    bsr     wf_pxx
    movel   %sp@+,%d1
    addql   #3,%d1
    cmpil   #63-WF_TOP,%d1
    bles    wf_dt
    movel   %sp@+,%d2
    rts

| Column d2, rows d3..d4 (10..63): every other pixel, from the even row at or
| above d3 - two masked words, where it used to be a call per pixel. The
| framebuffer is columns of d6 words, row y at bit 31-(y&31) of word y/32.
| Keeps d2-d7.
wf_vdots:
    lea.l   %sp@(-12),%sp
    moveml  %d2-%d4,%sp@
    movel   %d2,%d0
    mulsl   %d6,%d0
    lsll    #2,%d0
    movea.l %a5,%a0
    addal   %d0,%a0               | column d2, rows 0-31
    moveq   #0,%d2                | the word's first row
wvd_w:
    movel   %sp@(4),%d3
    bclr    #0,%d3
    movel   %d3,%d0
    subl    %d2,%d0               | first row in this word
    bpls    wvd_s
    moveq   #0,%d0
wvd_s:
    cmpil   #31,%d0
    bgts    wvd_n
    movel   %d4,%d1
    subl    %d2,%d1               | last row in this word
    bmis    wvd_n
    cmpil   #31,%d1
    bles    wvd_e
    moveq   #31,%d1
wvd_e:
    cmpl    %d1,%d0
    bgts    wvd_n
    moveq   #-1,%d3
    lsrl    %d0,%d3               | rows from the first...
    moveq   #31,%d0
    subl    %d1,%d0
    moveq   #-1,%d1
    lsll    %d0,%d1               | ...to the last
    andl    %d1,%d3
    andil   #0xAAAAAAAA,%d3       | even rows only
    orl     %d3,%a0@
wvd_n:
    addql   #4,%a0
    moveq   #32,%d0
    addl    %d0,%d2
    cmpil   #64,%d2
    bcss    wvd_w
    moveml  %sp@,%d2-%d4
    lea.l   %sp@(12),%sp
    rts

| flip pixel d0 = x, d1 = y; a5 = framebuffer, d6 = stride. Clobbers d0, d1,
| a0.
wf_pxx:
    movel   %d1,%sp@-
    mulsl   %d6,%d0
    lsrl    #5,%d1
    addl    %d1,%d0
    lsll    #2,%d0
    movea.l %a5,%a0
    addal   %d0,%a0
    movel   %sp@+,%d1
    andil   #31,%d1
    movel   #0x80000000,%d0
    lsrl    %d1,%d0
    eorl    %d0,%a0@
    rts

wf_fmt_s:     .asciz "%s"
wf_fmt_v:     .asciz "%d.%d"
wf_fmt_sl:    .asciz "SLICE %d"
wf_s_start:   .asciz "START"
wf_s_end:     .asciz "END"
wf_s_pos:     .asciz "POSITION"
wf_s_size:    .asciz "SIZE"
wf_s_strike:  .asciz "STRIKE"
wf_s_len:     .asciz "LENGTH"
    .align 4
wf_lbl_se:    .long wf_s_start, wf_s_end
wf_lbl_pos:   .long wf_s_pos, wf_s_size
wf_lbl_str:   .long wf_s_strike, wf_s_len
wf_trk:       .long 0
wf_snd:       .long 0          | the sound Start/End are read from
wf_slot:      .long -1         | the sample shown (wf_pick)
wf_mode:      .long 0
wf_act:       .long 0          | 0 = Start is being turned, 1 = End
wf_zoom:      .long 0          | this draw shows one slice, not the sample
wf_slb:       .long 0,0,0,0,0,0,0  | per track, from the render: the slice
wf_sll:       .long 0,0,0,0,0,0,0  | being played - first sample, length
wf_sli:       .long 0,0,0,0,0,0,0  | (0 = none yet) and its number
wf_mn   = UI_BUF               | per column: lowest sample (256 B) - in the
wf_mx   = UI_BUF+256           | ...and highest              region since
wf_top  = UI_BUF+512           | per column: its top row      samplerHR, to
wf_bot  = UI_BUF+640           | ...and bottom row            keep the blob
                               | in 4 cache blocks; written before read
wf_ck_h:      .long 0          | what wf_top/wf_bot show: the slot's hash,
wf_ck_a:      .long 0          | the first sample and the length
wf_ck_n:      .long 0

| ---- Filter and Resonance for the stock machines --------------------------
| Preset + Sweep / Contour, as Preset + Decay is Attack: param ids 0x0c and 0x0b
| (two more of the "Error" placeholders), common group, parameter indices 24
| and 25 - trackData +48 / +50, sound object +68 / +70, carried by the same
| 66-byte mirror as Attack and saved in record slots 25 and 26 (see
| snd_save_post). The Sampler keeps its own filter; for it these stay off.
|
| The filter is the Sampler's own 4-pole ladder, coefficients from the same
| tables (filt_coef / filt_fbmax / filt_mkt), run in amp_hook on the 32 output
| samples after the amp envelope - the point every machine passes. Those
| tables are for one step per 48 kHz sample, which is what the Sampler runs
| them at too (once per pair of its 2x buffer). Wide open with no resonance is
| a bypass (gflt_f = 0), so an untouched track costs nothing.
|
| gflt_coef: from sampler_pre, per track per block. d1 = machine, d2 = track,
| a2 = trackData. Preserves everything but d0/a0/a1.
gflt_coef:
    lea.l   %sp@(-12),%sp
    moveml  %d1/%d3-%d4,%sp@
    moveq   #0,%d0
    cmpil   #6,%d1
    beqs    gc_store              | the Sampler: off
    mvsw    %a2@(48),%d1
    bges    gc_fok
    moveq   #0,%d1
gc_fok:
    mvsw    %a2@(50),%d4
    bges    gc_rok
    moveq   #0,%d4
gc_rok:
    movel   %d1,%d3               | raw, for the bypass test
    asrl    #8,%d1                | dial 0..127
    cmpil   #127,%d1
    bles    gc_idx
    moveq   #127,%d1
gc_idx:
    cmpil   #32512,%d3
    blts    gc_on
    tstl    %d4
    beqs    gc_store              | wide open, no resonance
gc_on:
    lea.l   filt_coef,%a0
    mvzw    %a0@(0,%d1:l:2),%d0
    lea.l   gflt_f,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d4,%d0               | feedback from Resonance, as the Sampler's
    asrl    #1,%d0
    asrl    #5,%d4
    subl    %d4,%d0
    lea.l   filt_fbmax,%a0        | capped at the stable limit for this cutoff
    mvzw    %a0@(0,%d1:l:2),%d4
    cmpl    %d4,%d0
    bles    gc_qok
    movel   %d4,%d0
gc_qok:
    lea.l   gflt_q,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    movel   %d0,%d4               | resonance makeup
    asrl    #7,%d4
    lea.l   filt_mkt,%a0
    mvzw    %a0@(0,%d4:l:2),%d4
    lea.l   gflt_mk,%a0
    movel   %d4,%a0@(0,%d2:l:4)
    bras    gc_out
gc_store:
    lea.l   gflt_f,%a0
    movel   %d0,%a0@(0,%d2:l:4)
gc_out:
    moveml  %sp@,%d1/%d3-%d4
    lea.l   %sp@(12),%sp
    rts

| gflt_run(buf, track): the ladder over 32 output samples, in place. The
| arithmetic is the Sampler's (sv_flt), with one more bit of headroom: the amp
| stage's output can reach full scale, where the Sampler's buffer never passes
| half, so samples enter as >>14 rather than >>13 and leave as <<14, and the
| output clamp of 131068 then lands just inside full scale.
gflt_run:
    | Nothing to do - no registers saved, nothing read - when the filter is
    | bypassed, or when the block is silent and the ladder has settled (its
    | state is then cleared, so the next note starts from rest).
    movel   %sp@(8),%d0           | track
    lea.l   gflt_f,%a0
    tstl    %a0@(0,%d0:l:4)
    beqs    gr2_none
    | A new note starts this block (voice+56): the stock chain faded the old
    | one to silence over the last block (0x400a9252/0x400a9430, AFTER this
    | stage), so the ladder starts from rest too. Carried over, its state
    | smeared the old note into the new one's first samples, past that fade:
    | a click on every note, above a low cutoff (heard on the Chord; fixed in
    | samplerHV).
    lea.l   voice_ptr,%a0
    movea.l %a0@(0,%d0:l:4),%a0
    tstl    %a0@(56)
    beqs    gr2_nt
    movel   %d0,%d1
    lsll    #2,%d1
    lea.l   gflt_y1,%a0
    adda.l  %d1,%a0
    clrl    %a0@
    clrl    %a0@(28)
    clrl    %a0@(56)
    clrl    %a0@(84)
gr2_nt:
    movea.l %sp@(4),%a0           | the input: silent?
    moveq   #31,%d1
gr2_q:
    tstl    %a0@+
    bnes    gr2_go
    subql   #1,%d1
    bpls    gr2_q
    lsll    #2,%d0
    lea.l   gflt_y1,%a0           | the ladder: settled? (y1..y4, stride 28)
    adda.l  %d0,%a0
    moveq   #3,%d1
gr2_s:
    movel   %a0@,%d0
    bpls    gr2_sp
    negl    %d0
gr2_sp:
    cmpil   #4096,%d0             | under one step of the output: inaudible
    bgts    gr2_go
    lea.l   %a0@(28),%a0
    subql   #1,%d1
    bpls    gr2_s
    lea.l   %a0@(-112),%a0        | settled: clear it and skip the ladder
    moveq   #3,%d1
gr2_c:
    clrl    %a0@
    lea.l   %a0@(28),%a0
    subql   #1,%d1
    bpls    gr2_c
gr2_none:
    rts
gr2_go:
    lea.l   %sp@(-40),%sp
    moveml  %d2-%d7/%a2-%a5,%sp@
    movea.l %sp@(44),%a1          | buf
    movel   %sp@(48),%d7          | track
    lea.l   gflt_f,%a0
    movel   %a0@(0,%d7:l:4),%d0
    beqw    gr2_out               | bypass
    lea.l   gflt_q,%a0
    movel   %a0@(0,%d7:l:4),%d1
    lea.l   gflt_y1,%a0
    movel   %a0@(0,%d7:l:4),%d2
    lea.l   gflt_y2,%a0
    movel   %a0@(0,%d7:l:4),%d3
    lea.l   gflt_y3,%a0
    movel   %a0@(0,%d7:l:4),%d4
    lea.l   gflt_y4,%a0
    movel   %a0@(0,%d7:l:4),%d5
    movea.l %d7,%a4               | track, while d7 counts
    lea.l   gflt_mk,%a0
    lea.l   %a0@(0,%d7:l:4),%a0   | &makeup
    lea.l   %a1@(128),%a2         | the end
    moveq   #12,%d7               | every >> 12 in one instruction
    tstl    %d1                   | no resonance: the fast loop
    bnes    gr2_loop
    movel   %a0@,%d6
    cmpil   #4096,%d6
    beqw    gr2_fast
gr2_loop:
    movel   %a1@,%d6              | x = s >> 14, then makeup (Q12)
    asrl    #8,%d6
    asrl    #6,%d6
    mulsl   %a0@,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d5,%d6               | (fb * y4) >> 12
    asrl    %d7,%d6
    mulsl   %d1,%d6
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6               | ladder input = x - fb * y4
    cmpil   #262143,%d6
    bles    gr2_ih
    movel   #262143,%d6
gr2_ih:
    cmpil   #-262143,%d6
    bges    gr2_il
    movel   #-262143,%d6
gr2_il:
    movea.l %d6,%a5               | a5 carries the cascade value
    movel   %d2,%d6               | pole 1
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d2
    cmpil   #536870912,%d2
    bles    gr2_1h
    movel   #536870912,%d2
gr2_1h:
    cmpil   #-536870912,%d2
    bges    gr2_1l
    movel   #-536870912,%d2
gr2_1l:
    movel   %d2,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d3,%d6               | pole 2
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d3
    cmpil   #536870912,%d3
    bles    gr2_2h
    movel   #536870912,%d3
gr2_2h:
    cmpil   #-536870912,%d3
    bges    gr2_2l
    movel   #-536870912,%d3
gr2_2l:
    movel   %d3,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d4,%d6               | pole 3
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d4
    cmpil   #536870912,%d4
    bles    gr2_3h
    movel   #536870912,%d4
gr2_3h:
    cmpil   #-536870912,%d4
    bges    gr2_3l
    movel   #-536870912,%d4
gr2_3l:
    movel   %d4,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d5,%d6               | pole 4
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d5
    cmpil   #536870912,%d5
    bles    gr2_4h
    movel   #536870912,%d5
gr2_4h:
    cmpil   #-536870912,%d5
    bges    gr2_4l
    movel   #-536870912,%d5
gr2_4l:
    movel   %d5,%d6               | output = y4
    asrl    %d7,%d6
    cmpil   #131068,%d6
    bles    gr2_oh
    movel   #131068,%d6
gr2_oh:
    cmpil   #-131068,%d6
    bges    gr2_ol
    movel   #-131068,%d6
gr2_ol:
    asll    #8,%d6
    asll    #6,%d6
    movel   %d6,%a1@+
    cmpal   %a2,%a1
    bnew    gr2_loop
gr2_st:
    movel   %a4,%d7
    lea.l   gflt_y1,%a0
    movel   %d2,%a0@(0,%d7:l:4)
    lea.l   gflt_y2,%a0
    movel   %d3,%a0@(0,%d7:l:4)
    lea.l   gflt_y3,%a0
    movel   %d4,%a0@(0,%d7:l:4)
    lea.l   gflt_y4,%a0
    movel   %d5,%a0@(0,%d7:l:4)
gr2_out:
    moveml  %sp@,%d2-%d7/%a2-%a5
    lea.l   %sp@(40),%sp
    rts
| Resonance 0 (feedback 0, makeup exactly 4096): the input is s >> 14 with
| nothing to add or scale, and no clamp inside can act - the input stays
| within full scale, so every pole does too - so only the output clamp is
| kept. Bit-exact with gr2_loop there (modelled over every cutoff, full-scale
| square waves included), at about half its cost.
gr2_fast:
    movel   %a1@,%d6
    asrl    #8,%d6
    asrl    #6,%d6
    movea.l %d6,%a5               | x
    movel   %d2,%d6               | pole 1
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d2
    movel   %d2,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d3,%d6               | pole 2
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d3
    movel   %d3,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d4,%d6               | pole 3
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d4
    movel   %d4,%d6
    asrl    %d7,%d6
    movea.l %d6,%a5
    movel   %d5,%d6               | pole 4
    asrl    %d7,%d6
    negl    %d6
    addl    %a5,%d6
    mulsl   %d0,%d6
    addl    %d6,%d5
    movel   %d5,%d6               | output = y4, clamped as gr2_loop does
    asrl    %d7,%d6
    cmpil   #131068,%d6
    bles    grf_oh
    movel   #131068,%d6
grf_oh:
    cmpil   #-131068,%d6
    bges    grf_ol
    movel   #-131068,%d6
grf_ol:
    asll    #8,%d6
    asll    #6,%d6
    movel   %d6,%a1@+
    cmpal   %a2,%a1
    bnew    gr2_fast
    braw    gr2_st

| ---- keep them out of the Sampler's LFO destination list ------------------
| paramIdFor answers the common parameters from 0x40a79394[idx] whatever the
| machine, so the Sampler would list a second Filter and Resonance that do
| nothing there. Entered in place of `lea 0x40a79394,%a0` at 0x4005a6d0 (the
| `movel %a0@(0,%a2:l:4),%d0 ; bras` after it is replayed here), with
| %a2 = offsetIdx and %d2 = group; both exits restore them.
sampler_com_gate:
    cmpil   #6,%d2
    bnes    cg_stock
    movel   %a2,%d0
    subil   #24,%d0
    cmpil   #1,%d0
    bhis    cg_stock              | not 24/25
    jmp     0x4005a6ac            | none
cg_stock:
    lea.l   0x40a79394,%a0
    movel   %a0@(0,%a2:l:4),%d0
    jmp     0x4005a6fc

| ---- Preset + Decay dial -> Attack --------------------------------------
| Holding the modifier swaps the page descriptor so the Decay dial carries Attack
| (id 0x0d) instead of Amp Decay - see descr_hook. The dial therefore edits
| Attack directly: Decay is never written, so there is nothing to undo.
|
| The first attempt did the opposite - let Decay change, then put it back - and
| it would not stick even when held down for 16 ticks, so something else owns
| that word between our writes. Not writing it at all is both simpler and
| immune to whatever that is.
|
| Choosing the modifier has been the awkward part. TRACK turned out to be
| taken - stock uses Track+dial to copy a dial's value to every track - and
| PATTERN fired its own action when released, which suppressing the release
| did not fix, so it presumably acts on the press. Now PRESET, which is also
| half of the loop/slice chord but with a different partner. All three codes
| were measured with probe builds rather than guessed.
|
| All this has to do is publish whether the modifier is down. It used to ferry
| Attack into a private table too, on the belief that the mirror stopped at
| k=22. It does not: the mirror is a 66-byte memcpy covering k=0..32, and only
| the SAVE format stops at 22. sampler_pre reads trackData+46 directly now.
| Driven from tick_hook, which is input-driven, so the descriptor swap follows
| the button within a frame.
atk_watch:
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d3/%a2-%a3,%sp@
    pea     KEY_ATKMOD
    jsr     0x4007faf4
    addql   #4,%sp
    lea.l   mod_held,%a3
    movel   %d0,%a3@              | published for descr_hook
    moveml  %sp@,%d2-%d3/%a2-%a3
    lea.l   %sp@(16),%sp
    rts

| ---- is the selected track in granular mode? (for apply_names) ----------
| The UI's own current-track lookup, as loop_toggle uses it. UI thread only.
gran_watch:
    jsr     0x400cf866
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    addql   #8,%sp
    moveq   #0,%d1
    cmpil   #MAX_TRK,%d0
    bccs    gw_set
    lea.l   loop_mode,%a0
    moveq   #2,%d1
    cmpl    %a0@(0,%d0:l:4),%d1
    bcsw    gw_modes
    lea.l   fx_sel,%a0            | Lo-fi, Tape, Vinyl: their own labels
    movel   %a0@(0,%d0:l:4),%d1
    cmpil   #1,%d1
    bnes    gw_tv
    moveq   #5,%d1
    bras    gw_set
gw_tv:
    subql   #2,%d1
    cmpil   #1,%d1
    bhis    gw_none
    moveq   #6,%d1
    bras    gw_set
gw_modes:
    movel   %a0@(0,%d0:l:4),%d0
    subql   #2,%d0                | 3 -> 1 granular, 4 -> 2 stretch, 5 -> 3 pluck,
    bles    gw_set                | 6 -> 4 wavetable; 5 = One shot's Lo-fi
    cmpil   #4,%d0
    bhis    gw_set
    movel   %d0,%d1
    bras    gw_set
gw_none:
    moveq   #0,%d1
gw_set:
    lea.l   ui_gran,%a0
    movel   %d1,%a0@
    rts

| ---- the firmware has just committed a machine change -------------------
| 0x40014072 runs only from setMachine (0x4001477e), and only when the machine
| actually changed: setMachine has already written the new machine to
| sound+38, and 0x40014072 has just written that machine's page defaults -
| for the Sampler, the borrowed ids' OWN defaults, 10/38/43/24. Patched in at
| 0x4001413e, the notify that follows, so our four go out with it. Project and
| pattern loads never come through here: they deserialise the sound directly.
| At this point a2 = trackObj; d2..d6, a3..a5 and the frame belong to
| 0x40014072, so only d0/d1/a0/a1 are touched.
mc_commit_hook:
    movel   %a2,%sp@-
    movea.l %a2@,%a0
    movea.l %a0@(40),%a0          | vtable[40]: the sound
    jsr     %a0@
    addql   #4,%sp
    tstl    %d0
    beqs    mch_ntf
    movea.l %d0,%a0
    mvzb    %a0@(38),%d0          | the machine just set
    cmpil   #6,%d0
    bnes    mch_ntf
    | A sound with no packed state (never a Sampler, or saved before there was
    | one) starts from the defaults: One shot, every option at its first, 16
    | equal slices. One that has one - a Sampler switched away and back - keeps
    | its modes, as it keeps its sample.
    tstb    %a0@(72)
    bmis    mch_hasst
    movel   %d1,%sp@-
    movel   #ST_DEFAULT,%d1
    movel   %d1,%a0@(72)
    movel   %sp@+,%d1
mch_hasst:
    | Parameter k lives at sound+20+2k; ours are k = 11..14 (Start, End,
    | Filter, Resonance) -> +42..+48, the order of sampler_defaults.
    lea.l   %a0@(42),%a0
    lea.l   sampler_defaults,%a1
    moveq   #3,%d0
mch_w:
    movew   %a1@+,%a0@+
    subql   #1,%d0
    bpls    mch_w
mch_ntf:
    moveal  %a2@,%a0              | the instructions this patch replaced
    clrl    %sp@-
    movel   %a2,%sp@-
    jmp     0x40014144            | on to the firmware's own notify

| ---- the machine page's "back to the original machine" restore ----------
| Opening the machine page snapshots every track's page values; landing a
| track back on the machine it had then writes the snapshot back
| (0x4001416c, called from 0x400a2712 and nowhere else). For the Sampler that
| brought back an old Sample End instead of the defaults mc_commit_hook has
| just written, so skip it there. args: sp@(4) = trackObj, sp@(8) = pairs.
restore_hook:
    movel   %sp@(4),%d0
    beqs    rs_go
    movel   %d0,%sp@-
    movea.l %d0,%a0
    movea.l %a0@,%a0
    movea.l %a0@(40),%a0          | vtable[40]: the sound
    jsr     %a0@
    addql   #4,%sp
    tstl    %d0
    beqs    rs_go
    movea.l %d0,%a0
    mvzb    %a0@(38),%d0
    cmpil   #6,%d0
    beqs    rs_skip
rs_go:
    jmp     0x4001416c
rs_skip:
    rts

lh_clock:
    .long 0
led_hook:
    lea.l   %sp@(-48),%sp
    moveml  %d0-%d7/%a0-%a3,%sp@
    | Only at IPL 0: interrupts enabled, task context, so blocking on the
    | readBlocks mutex is safe. At any elevated level do nothing and let the
    | KeyboardView hook handle it. Measured IP0 in practice, but the guard
    | stays - it costs four instructions and removes a whole failure mode.
    moveq   #0,%d0
    movew   %sr,%d0
    andil   #0x0700,%d0
    bnew    lh_out
    movel   0x8000184c,%d0        | installed in five LedHandler slots: run
    cmpl    lh_clock,%d0          | once per audio block, not once per slot
    beqw    lh_out
    movel   %d0,lh_clock
    lea.l   ld_busy,%a0           | a load holds this callback for seconds
    tstl    %a0@
    bnew    lh_out
    moveq   #1,%d0
    movel   %d0,%a0@
    jsr     atk_watch
    jsr     gran_watch
    jsr     slice_watch
    jsr     name_probe
    jsr     load_pending
    jsr     pl_step
    jsr     nm_step
    jsr     nm_tick
    jsr     sys_tick
    jsr     rs_watch
    lea.l   ld_busy,%a0
    clrl    %a0@
lh_out:
    moveml  %sp@,%d0-%d7/%a0-%a3
    lea.l   %sp@(48),%sp
    rts

| ================= Scale Lock (ported from the Model:Samples mod) =========
| The two devices are the same framework compiled twice, so the note entry
| points match byte for byte. Samples' note-off prologue and Cycles'
| 0x4008145e are identical over their first 28 bytes, the `bcsw`
| displacement included.
| Hook points, both right before the function's own range check, exactly as
| the Samples mod does it:
|     note ON   0x4008173c  continue 0x40081742  out-of-range 0x4008190e
|     note OFF  0x40081474  continue 0x4008147a  out-of-range 0x400815f0
| The note-on function is the same one pad_load_hook uses, but that patches
| offset +0 and this patches +0x1e, so they do not collide.
|
| ONE REAL DIFFERENCE FROM THE SAMPLES PORT: there, d5/d6 are dead at the
| hook point, so snap_note used them freely. On Cycles both are LIVE -
| 0x40081730 loads %fp@(20) into d5 and 0x40081738 loads %fp@(32) into d6 -
| so the hooks save and restore them around the call. d1 is dead (the code
| after the hook writes it immediately) and d0 holds the 127 the range check
| needs, which snap_note never touches.
note_on_hook:
    lea.l   %sp@(-8),%sp
    moveml  %d5-%d6,%sp@
    | d2 = track, d3 = the raw note; d0 (=127) is the caller's range
    | limit and must survive. a0 is not live until 0x40081746.
    movel   %d2,%d5
    cmpil   #MAX_TRK,%d5
    bccs    non_snap          | not a real track: behave as before
    lea.l   live_note,%a0
    moveb   %d3,%a0@(0,%d5:l)     | the played note, before any folding
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d5:l:4),%d6
    cmpil   #2,%d6
    beqs    non_noscale       | slice track: folding the note would
                                  | stop consecutive pads being
                                  | consecutive slices
non_snap:
    jsr     snap_note
non_noscale:
    moveml  %sp@,%d5-%d6
    lea.l   %sp@(8),%sp
    cmpl    %d3,%d0
    bccs    non_go
    jmp     0x4008190e
non_go:
    jmp     0x40081742

note_off_hook:
    lea.l   %sp@(-8),%sp
    moveml  %d5-%d6,%sp@
    | d2 = track, d3 = the raw note; d0 (=127) is the caller's range
    | limit and must survive. a0 is not live until 0x40081746.
    movel   %d2,%d5
    cmpil   #MAX_TRK,%d5
    bccs    nof_snap          | not a real track: behave as before
    lea.l   live_note,%a0
    moveb   %d3,%a0@(0,%d5:l)     | the played note, before any folding.
                                  | This is the only place it is visible,
                                  | and it covers pads and sequencer alike.
    lea.l   loop_mode,%a0
    movel   %a0@(0,%d5:l:4),%d6
    cmpil   #2,%d6
    beqs    nof_noscale       | slice track: folding the note would
                                  | stop consecutive pads being
                                  | consecutive slices
nof_snap:
    jsr     snap_note
nof_noscale:
    moveml  %sp@,%d5-%d6
    lea.l   %sp@(8),%sp
    cmpl    %d3,%d0
    bccs    nof_go
    jmp     0x400815f0
nof_go:
    jmp     0x4008147a

| snap_note, unchanged from the Samples mod apart from comments. BASE is the
| raw note of the first trig pad; 52 (E4) was MEASURED on Samples hardware,
| and whether Cycles matches is the main thing this build tests.
snap_note:
    movel   %a5,%sp@-
    tstb    scale_state
    beqs    sn_done
    cmpil   #0x7f,%d3
    beqs    sn_done
    movel   %d3,%d5
    moveq   #52,%d6               | BASE: first trig pad's raw note
    subl    %d6,%d5               | signed offset from BASE
    moveq   #0,%d6
    moveb   scale_state,%d6
    subql   #1,%d6
    lea.l   fold_lengths,%a0
    moveb   %a0@(0,%d6:l),%d6     | N = notes in this scale
    divsw   %d6,%d5
    movel   %d5,%d1
    extl    %d1                   | quotient
    swap    %d5
    extl    %d5                   | remainder, may be negative
    tstl    %d5
    bges    sn_rem_ok
    addl    %d6,%d5               | floor-correct: remainder += N
    subql   #1,%d1                | and one octave down
sn_rem_ok:
    moveq   #0,%d6
    moveb   scale_state,%d6
    subql   #1,%d6
    muluw   #7,%d6                | fold table stride
    lea.l   fold_tables,%a5
    addal   %d6,%a5
    moveq   #0,%d6
    moveb   %a5@(0,%d5:l),%d6     | scale degree
    mulsw   #12,%d1
    addl    %d6,%d1
    addil   #48,%d1               | C_REF = C4. key_state is semitones above C,
                                  | so it MUST be added onto a multiple of 12,
                                  | not onto BASE - that was a real bug on
                                  | Samples (F major played A4 at pad 1).
    moveq   #0,%d6
    moveb   key_state,%d6
    addl    %d6,%d1               | key applied AFTER folding, so the root
    movel   %d1,%d3               | always stays on pad 1
sn_done:
    movel   %sp@+,%a5
    rts


| ---- Scale Lock menu: Samples -> Cycles address map -------------------
| Every one of these was resolved by wildcard byte matching and verified a
| second way; see docs/notes/scalelock_address_map.md.
    .equ ALLOC,            0x40080064
    .equ FREE_CLOSURE,     0x400cf044
    .equ MENUITEM_CTOR,    0x400734b0
    .equ MENUVIEW_ADDITEM, 0x40072ce6
    .equ FORMAT_STRING,    0x400f980c
    .equ TINYSTR_WRAP,     0x400f85bc
    .equ DRAW_FMT_A,       0x40072260
    .equ DRAW_FMT_B,       0x40072080
    .equ DRAW_TEXT,        0x40071a04
    .equ FREE_TINYSTR,     0x400f7d5c
    .equ SLOT2_MANAGER,    0x4002f188
    .equ SLOT2_INVOKER,    0x4002ec3a
    .equ GENERIC_MANAGER,  0x4002f136

|------------------------------------------------------------------
| slot1 invoker: label text. Clone of FUN_400300ec, own string.
| in: a0 = output buffer. out: d0 = a0.
|------------------------------------------------------------------
label_invoker:
    link.w  %a6,#-4
    move.l  %d2,-(%a7)
    pea.l   -1(%a6)
    pea.l   label_string
    move.l  %a0,%d2
    move.l  %a0,-(%a7)
    jsr     FORMAT_STRING
    lea.l   0xc(%a7),%a7
    move.l  %d2,%d0
    move.l  -8(%a6),%d2
    unlk    %a6
    rts

|------------------------------------------------------------------
| slot1 invoker for the SECOND (key) menu item. Identical shape to
| label_invoker, own string.
|------------------------------------------------------------------
label_invoker2:
    link.w  %a6,#-4
    move.l  %d2,-(%a7)
    pea.l   -1(%a6)
    pea.l   label_string2
    move.l  %a0,%d2
    move.l  %a0,-(%a7)
    jsr     FORMAT_STRING
    lea.l   0xc(%a7),%a7
    move.l  %d2,%d0
    move.l  -8(%a6),%d2
    unlk    %a6
    rts

|------------------------------------------------------------------
| slot3 invoker: value text render. Clone of FUN_400317b2's simple
| branch + shared drawing tail (params: a6+0x8..0x18 same as original).
| param_3=$10(a6) draw ctx, param_4=$14(a6) x, param_5=$18(a6) y.
|------------------------------------------------------------------
value_invoker:
    link.w  %a6,#-0x30
    move.l  #0x40fe4278,%d0
    movem.l %d2-%d4/%a2-%a5,(%a7)
    move.l  %d0,-0x10(%a6)
    lea.l   FREE_TINYSTR,%a2
    move.l  %a6,%d2
    subq.l  #8,%d2
    move.l  %a6,%d3
    addi.l  #-0x10,%d3

    moveq   #0,%d0
    move.b  scale_state,%d0
    lsl.l   #2,%d0
    lea.l   value_strings,%a0
    move.l  0(%a0,%d0.l),%d0

    move.l  %d0,-(%a7)
    move.l  %d3,-(%a7)
    jsr     TINYSTR_WRAP
    addq.l  #8,%a7

    pea.l   0x40140ab0
    move.l  %d2,-(%a7)
    move.l  -0x10(%a6),%d4
    jsr     DRAW_FMT_A
    move.l  %d4,-(%a7)
    movea.l 0x14(%a6),%a0
    pea.l   4
    move.l  0x18(%a6),-(%a7)
    lea.l   0x18(%a0),%a0
    move.l  %a0,-(%a7)
    move.l  %d2,-(%a7)
    move.l  0x10(%a6),-(%a7)
    jsr     DRAW_TEXT
    lea.l   0x1c(%a7),%a7
    move.l  %d2,(%a7)
    jsr     DRAW_FMT_B
    move.l  %d3,-(%a7)
    jsr     (%a2)
    addq.l  #8,%a7
    movem.l -0x30(%a6),%d2-%d4/%a2-%a5
    unlk    %a6
    rts

|------------------------------------------------------------------
| slot3 invoker for the SECOND (key) menu item. Identical shape to
| value_invoker, reads key_state / key_value_strings instead.
|------------------------------------------------------------------
value_invoker2:
    link.w  %a6,#-0x30
    move.l  #0x40fe4278,%d0
    movem.l %d2-%d4/%a2-%a5,(%a7)
    move.l  %d0,-0x10(%a6)
    lea.l   FREE_TINYSTR,%a2
    move.l  %a6,%d2
    subq.l  #8,%d2
    move.l  %a6,%d3
    addi.l  #-0x10,%d3

    moveq   #0,%d0
    move.b  key_state,%d0
    lsl.l   #2,%d0
    lea.l   key_value_strings,%a0
    move.l  0(%a0,%d0.l),%d0

    move.l  %d0,-(%a7)
    move.l  %d3,-(%a7)
    jsr     TINYSTR_WRAP
    addq.l  #8,%a7

    pea.l   0x40140ab0
    move.l  %d2,-(%a7)
    move.l  -0x10(%a6),%d4
    jsr     DRAW_FMT_A
    move.l  %d4,-(%a7)
    movea.l 0x14(%a6),%a0
    pea.l   4
    move.l  0x18(%a6),-(%a7)
    lea.l   0x18(%a0),%a0
    move.l  %a0,-(%a7)
    move.l  %d2,-(%a7)
    move.l  0x10(%a6),-(%a7)
    jsr     DRAW_TEXT
    lea.l   0x1c(%a7),%a7
    move.l  %d2,(%a7)
    jsr     DRAW_FMT_B
    move.l  %d3,-(%a7)
    jsr     (%a2)
    addq.l  #8,%a7
    movem.l -0x30(%a6),%d2-%d4/%a2-%a5
    unlk    %a6
    rts

|------------------------------------------------------------------
| slot4 invoker: ROTATION handler. Real precedent (objdump-verified,
| FUN_40030d74 - item1/"Len"'s own slot4) receives the rotation delta
| as a plain signed argument at $24(sp) at entry (its own prologue
| reserves+saves 24 bytes first, then reads $36(sp), i.e. entry_sp+12
| = the 3rd stack argument), takes sign(delta), and tail-jumps into
| the generic parameter-context setter (FUN_4000d3e4) to apply it -
| that setter needs a "parameter context" object (vtable+0x28/+0x10)
| our captured TrackMenuView pointer doesn't have the shape for, so
| we deliberately do NOT reuse that tail-jump (this is exactly what
| caused two real crashes earlier: assuming a captured pointer can
| stand in for that context). Instead we clone only the safe,
| argument-reading prologue, then apply the delta with our own
| already-working advance_scale (byte write, no generic-context
| machinery) and return normally.
|------------------------------------------------------------------
new_slot4_invoker:
    lea.l   -24(%a7),%a7
    movem.l %d2-%d4/%a2-%a4,(%a7)
    move.l  36(%a7),%d4
    moveq   #0,%d0
    tst.l   %d4
    beq.b   .zero
    bgt.b   .pos
    moveq   #-1,%d0
    bra.b   .apply
.pos:
    moveq   #1,%d0
.apply:
    jsr     advance_scale
.zero:
    | live redraw, take 4: FUN_40030d74 (our slot4 template) never
    | calls FUN_400750e2/FUN_40075c4e at all - those turned out to
    | just set unread "dirty" flags with no direct effect. It only
    | ever tail-jumps into the generic setter (FUN_4000d3e4), whose
    | OWN last step is "(**(code**)(*param_1+0x10))()" - calling
    | vtable slot 0x10 (notify) directly on the "current track"
    | accessor object itself. We already know this exact object has
    | a valid vtable, since its +0x28 slot (get-storage) has been
    | called successfully via this same chain throughout this whole
    | session (every getter/setter we've used does that). Call its
    | +0x10 slot the same way instead of the flag-setting functions.
    jsr     0x400cf866
    move.l  %d0,-(%a7)
    jsr     0x4000f208
    addq.l  #4,%a7
    move.l  %d0,-(%a7)
    jsr     0x4000d0dc
    addq.l  #4,%a7
    movea.l %d0,%a0
    movea.l (%a0),%a1
    movea.l 0x10(%a1),%a1
    move.l  %a0,-(%a7)
    jsr     (%a1)
    addq.l  #4,%a7
    movem.l (%a7),%d2-%d4/%a2-%a4
    lea.l   24(%a7),%a7
    rts

|------------------------------------------------------------------
| slot2 invoker: PRESS handler. Byte-identical clone of the real
| FUN_40030176 (objdump-verified) - this is confirmed (via real
| hardware test) to fire on encoder PRESS, toggling a boolean field
| on the captured object (our "a2") via a plain EOR + tail-jump to
| the real setter FUN_4007234c. We now leave this completely
| unmodified (no value-advance call): the real UX has press select
| the item without changing its value - the actual value changes
| happen in slot4 (rotation) below, matching the real framework's
| own item1 ("Len") which uses the exact same split.
|------------------------------------------------------------------
new_slot2_invoker:
    move.l  %d2,-(%a7)
    move.l  0xc(%a7),%d2
    move.l  %d2,-(%a7)
    jsr     0x400732f8
    addq.l  #4,%a7
    moveq   #1,%d1
    mvz.b   %d0,%d0
    move.l  %d2,8(%a7)
    eor.l   %d0,%d1
    move.l  %d1,12(%a7)
    move.l  (%a7)+,%d2
    jmp     0x400732ec

|------------------------------------------------------------------
| advance_scale: apply delta (d0, +1 or -1) to scale_state, wrapping
| within 0..4. note_trigger_hook reads scale_state live, so nothing
| else needs to happen here.
|------------------------------------------------------------------
advance_scale:
    moveq   #0,%d1
    move.b  scale_state,%d1
    add.l   %d0,%d1
    cmpi.l  #0,%d1
    bge.b   .not_neg
    moveq   #4,%d1
    bra.b   .store
.not_neg:
    cmpi.l  #4,%d1
    ble.b   .store
    moveq   #0,%d1
.store:
    move.b  %d1,scale_state
    rts

|------------------------------------------------------------------
| slot2 invoker for the SECOND (key) menu item: same pure-toggle
| shape as new_slot2_invoker, no value-advance call.
|------------------------------------------------------------------
new_slot2_invoker2:
    move.l  %d2,-(%a7)
    move.l  0xc(%a7),%d2
    move.l  %d2,-(%a7)
    jsr     0x400732f8
    addq.l  #4,%a7
    moveq   #1,%d1
    mvz.b   %d0,%d0
    move.l  %d2,8(%a7)
    eor.l   %d0,%d1
    move.l  %d1,12(%a7)
    move.l  (%a7)+,%d2
    jmp     0x400732ec

|------------------------------------------------------------------
| advance_key: apply delta (d0, +1 or -1) to key_state, wrapping
| within 0..11.
|------------------------------------------------------------------
advance_key:
    moveq   #0,%d1
    move.b  key_state,%d1
    add.l   %d0,%d1
    cmpi.l  #0,%d1
    bge.b   .not_neg2
    moveq   #11,%d1
    bra.b   .store2
.not_neg2:
    cmpi.l  #11,%d1
    ble.b   .store2
    moveq   #0,%d1
.store2:
    move.b  %d1,key_state
    rts

|------------------------------------------------------------------
| slot4 invoker for the SECOND (key) menu item. Same shape as
| new_slot4_invoker, calls advance_key instead of advance_scale.
|------------------------------------------------------------------
new_slot4_invoker2:
    lea.l   -24(%a7),%a7
    movem.l %d2-%d4/%a2-%a4,(%a7)
    move.l  36(%a7),%d4
    moveq   #0,%d0
    tst.l   %d4
    beq.b   .zero2
    bgt.b   .pos2
    moveq   #-1,%d0
    bra.b   .apply2
.pos2:
    moveq   #1,%d0
.apply2:
    jsr     advance_key
.zero2:
    jsr     0x400cf866
    move.l  %d0,-(%a7)
    jsr     0x4000f208
    addq.l  #4,%a7
    move.l  %d0,-(%a7)
    jsr     0x4000d0dc
    addq.l  #4,%a7
    movea.l %d0,%a0
    movea.l (%a0),%a1
    movea.l 0x10(%a1),%a1
    move.l  %a0,-(%a7)
    jsr     (%a1)
    addq.l  #4,%a7
    movem.l (%a7),%d2-%d4/%a2-%a4
    lea.l   24(%a7),%a7
    rts

|------------------------------------------------------------------
| install_scale_menu_item: hook target. Replaces the overwritten
| first instruction of FUN_40030874's epilogue. On entry, a2 still
| holds the TrackMenuView "this" pointer (unchanged from function
| entry). Builds TWO menu items (scale type, then key) and adds
| both, then resumes the original epilogue.
|
| Closure layout, stable base register a5 (0x80 bytes reserved: two
| 0x40-byte blocks, one per item):
|   item1 (scale): closure1 @ a5+0x00 (label) closure2 @ a5+0x10
|     (interact) closure3 @ a5+0x20 (value) closure4 @ a5+0x30 (null)
|   item2 (key):   same layout at a5+0x40..0x7f
| each closure: [0]=data ptr [4]=0 [8]=manager [0xc]=invoker
|------------------------------------------------------------------
install_scale_menu_item:
    lea.l   -0x30(%a7),%a7
    movem.l %d0-%d7/%a0-%a1/%a3-%a4,(%a7)
    lea.l   -0x80(%a7),%a7
    movea.l %a7,%a5

    | --- item1: SCALE LOCK ---
    move.l  #1,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    move.l  %d0,0x00(%a5)
    clr.l   0x04(%a5)
    move.l  #GENERIC_MANAGER,%d0
    move.l  %d0,0x08(%a5)
    move.l  #label_invoker,%d0
    move.l  %d0,0x0c(%a5)

    move.l  #4,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a0
    move.l  %a2,(%a0)
    move.l  %d0,0x10(%a5)
    clr.l   0x14(%a5)
    move.l  #SLOT2_MANAGER,%d0
    move.l  %d0,0x18(%a5)
    move.l  #new_slot2_invoker,%d0
    move.l  %d0,0x1c(%a5)

    move.l  #1,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    move.l  %d0,0x20(%a5)
    clr.l   0x24(%a5)
    move.l  #GENERIC_MANAGER,%d0
    move.l  %d0,0x28(%a5)
    move.l  #value_invoker,%d0
    move.l  %d0,0x2c(%a5)

    | closure4: rotation handler (slot4). Same capture (a2) and
    | manager as closure2 - proven-safe generic 4-byte-capture
    | manager, reused here since the shape is identical.
    move.l  #4,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a0
    move.l  %a2,(%a0)
    move.l  %d0,0x30(%a5)
    clr.l   0x34(%a5)
    move.l  #SLOT2_MANAGER,%d0
    move.l  %d0,0x38(%a5)
    move.l  #new_slot4_invoker,%d0
    move.l  %d0,0x3c(%a5)

    move.l  #0x54,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a3

    move.l  #8,-(%a7)
    move.l  #0xffffffff,-(%a7)
    lea.l   0x30(%a5),%a0
    move.l  %a0,-(%a7)
    lea.l   0x20(%a5),%a0
    move.l  %a0,-(%a7)
    lea.l   0x10(%a5),%a0
    move.l  %a0,-(%a7)
    move.l  %a5,-(%a7)
    move.l  %a3,-(%a7)
    jsr     MENUITEM_CTOR
    lea.l   0x1c(%a7),%a7

    move.l  %a3,-(%a7)
    move.l  %a2,-(%a7)
    jsr     MENUVIEW_ADDITEM
    addq.l  #8,%a7

    lea.l   0x30(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    lea.l   0x20(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    lea.l   0x10(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    move.l  %a5,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7

    | --- item2: SCALE KEY, closures at a5+0x40..0x7f ---
    move.l  #1,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    move.l  %d0,0x40(%a5)
    clr.l   0x44(%a5)
    move.l  #GENERIC_MANAGER,%d0
    move.l  %d0,0x48(%a5)
    move.l  #label_invoker2,%d0
    move.l  %d0,0x4c(%a5)

    move.l  #4,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a0
    move.l  %a2,(%a0)
    move.l  %d0,0x50(%a5)
    clr.l   0x54(%a5)
    move.l  #SLOT2_MANAGER,%d0
    move.l  %d0,0x58(%a5)
    move.l  #new_slot2_invoker2,%d0
    move.l  %d0,0x5c(%a5)

    move.l  #1,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    move.l  %d0,0x60(%a5)
    clr.l   0x64(%a5)
    move.l  #GENERIC_MANAGER,%d0
    move.l  %d0,0x68(%a5)
    move.l  #value_invoker2,%d0
    move.l  %d0,0x6c(%a5)

    | closure4: rotation handler (slot4), same pattern as item1's.
    move.l  #4,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a0
    move.l  %a2,(%a0)
    move.l  %d0,0x70(%a5)
    clr.l   0x74(%a5)
    move.l  #SLOT2_MANAGER,%d0
    move.l  %d0,0x78(%a5)
    move.l  #new_slot4_invoker2,%d0
    move.l  %d0,0x7c(%a5)

    move.l  #0x54,-(%a7)
    jsr     ALLOC
    addq.l  #4,%a7
    movea.l %d0,%a3

    move.l  #8,-(%a7)
    move.l  #0xffffffff,-(%a7)
    lea.l   0x70(%a5),%a0
    move.l  %a0,-(%a7)
    lea.l   0x60(%a5),%a0
    move.l  %a0,-(%a7)
    lea.l   0x50(%a5),%a0
    move.l  %a0,-(%a7)
    lea.l   0x40(%a5),%a0
    move.l  %a0,-(%a7)
    move.l  %a3,-(%a7)
    jsr     MENUITEM_CTOR
    lea.l   0x1c(%a7),%a7

    move.l  %a3,-(%a7)
    move.l  %a2,-(%a7)
    jsr     MENUVIEW_ADDITEM
    addq.l  #8,%a7

    lea.l   0x70(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    lea.l   0x60(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    lea.l   0x50(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7
    lea.l   0x40(%a5),%a0
    move.l  %a0,-(%a7)
    jsr     FREE_CLOSURE
    addq.l  #4,%a7

    lea.l   0x80(%a7),%a7
    movem.l (%a7),%d0-%d7/%a0-%a1/%a3-%a4
    lea.l   0x30(%a7),%a7

    | resume original FUN_40030874 epilogue (the instruction we overwrote)
    movem.l 0x18(%a7),%d2-%d6/%a2-%a6
    lea.l   0x80(%a7),%a7
    rts

label_string:
    .asciz "Scl"
    .even
str_off:
    .asciz "OFF"
    .even
str_major:
    .asciz "MAJ"
    .even
str_minor:
    .asciz "MIN"
    .even
str_dorian:
    .asciz "DOR"
    .even
str_penta:
    .asciz "PEN"
    .even
value_strings:
    .long str_off
    .long str_major
    .long str_minor
    .long str_dorian
    .long str_penta

label_string2:
    .asciz "Key"
    .even
key_c:
    .asciz "C"
    .even
key_cs:
    .asciz "C#"
    .even
key_d:
    .asciz "D"
    .even
key_ds:
    .asciz "D#"
    .even
key_e:
    .asciz "E"
    .even
key_f:
    .asciz "F"
    .even
key_fs:
    .asciz "F#"
    .even
key_g:
    .asciz "G"
    .even
key_gs:
    .asciz "G#"
    .even
key_a:
    .asciz "A"
    .even
key_as:
    .asciz "A#"
    .even
key_b:
    .asciz "B"
    .even
key_value_strings:
    .long key_c
    .long key_cs
    .long key_d
    .long key_ds
    .long key_e
    .long key_f
    .long key_fs
    .long key_g
    .long key_gs
    .long key_a
    .long key_as
    .long key_b                   | was missing until samplerHN: key B (11)
                                  | read the long past the table as its name

| ---- browser: remember what was selected ----
getentry_hook:
    movel   %sp@(8),%sp@-         | re-push index
    movel   %sp@(8),%sp@-         | re-push dir
    jsr     0x4007cdd4            | a0 (struct return) untouched
    lea.l   %sp@(8),%sp
    lea.l   %sp@(-8),%sp
    movel   %d1,%sp@
    movel   %a0,%sp@(4)
    tstl    %d0
    beqs    gh_out                | no handle returned - do not dereference it
    movea.l %d0,%a0               | the 16-byte handle
    movel   %a0@,%d1
    cmpil   #-1,%d1
    beqs    gh_out                | invalid -> leave the last selection alone
    | getEntry's failure path (0x4007ce00) skips all four writes into the handle
    | and returns the same pointer, so on failure it holds stale stack garbage -
    | which is almost never exactly -1. Require a plausible hash AND size, and
    | validate both BEFORE storing either, so a half-valid handle cannot leave
    | sel_hash updated against a stale sel_size.
    movel   %a0@(4),%d1
    beqs    gh_out                | no hash
    movel   %a0@(8),%d1
    beqs    gh_out                | no size
    lea.l   sel_size,%a0
    movel   %d1,%a0@
    movea.l %d0,%a0
    movel   %a0@(4),%d1
    lea.l   sel_hash,%a0
    movel   %d1,%a0@
gh_out:
    movel   %sp@,%d1
    movea.l %sp@(4),%a0
    lea.l   %sp@(8),%sp
    rts

| ---- browser, sound lock: a sample stands in for a preset ------------------
| Hold a step, press Preset and open a file: the browser's lock path finds or
| takes a Sound Pool slot and stores the loaded sound there through the
| function at +80 of the object at browser+628 - (pool, sound, slot) -> 0 ok
| (0x400a680a) - then locks the held steps to that slot. A sample file is no
| preset, so that store fails: "Error loading preset". pool_store_hook takes
| the place of `moveal a0@(80),a0; jsr a0@` (a0 = that object): it runs the
| store, and if it fails while the file under the cursor (sel_hash) loads as
| a sample and the selected track is a Sampler, it stores instead a copy of
| the track's sound whose token names that sample - through the same stock
| store, so the pool entry and the lock are the firmware's own. On that step
| sp_lock then plays the sample.
pool_store_hook:
    movea.l %a0@(80),%a0
    movel   %a0,psh_fn
    movel   %sp@(12),%sp@-        | (pool, sound, slot) again
    movel   %sp@(12),%sp@-
    movel   %sp@(12),%sp@-
    jsr     %a0@
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    psh_ret               | a preset: stored
    lea.l   %sp@(-16),%sp
    moveml  %d2-%d4/%a2,%sp@      | args now at sp@(20) pool, (24) sound, (28) slot
    movel   %d0,%d4               | the stock's answer, unless we do better
    movel   sel_hash,%d3
    beqw    psh_no
    jsr     0x400cf866            | the selected track
    movel   %d0,%sp@-
    jsr     0x4000eb90
    movel   %d0,%sp@-
    jsr     0x40012412
    addql   #8,%sp
    movel   %d0,%d2
    cmpil   #MAX_TRK,%d2
    bccw    psh_no
    jsr     sound_obj
    tstl    %d0
    beqw    psh_no
    movea.l %d0,%a2
    mvzb    %a2@(38),%d0
    cmpil   #6,%d0
    bnew    psh_no                | not a Sampler track
    movel   %d3,%d0               | a sample? (its header is checked) - and
    jsr     ensure_loaded         | in RAM for the step from the start
    tstl    %d0
    bmiw    psh_no
    lea.l   psh_snd,%a1           | the track's sound...
    moveq   #SND_SIZE/4-1,%d0
psh_cp:
    movel   %a2@+,%a1@+
    subql   #1,%d0
    bpls    psh_cp
    lea.l   psh_snd+4,%a1         | ...naming the sample: "SMP" + 8 hex digits
    moveb   #83,%a1@+
    moveb   #77,%a1@+
    moveb   #80,%a1@+
    moveq   #28,%d1
psh_h:
    movel   %d3,%d0
    lsrl    %d1,%d0
    andil   #15,%d0
    addil   #48,%d0
    cmpil   #58,%d0
    bcss    psh_hd
    addql   #7,%d0
psh_hd:
    moveb   %d0,%a1@+
    subql   #4,%d1
    bpls    psh_h
    | The same sound already pooled (this sample, these settings)? Then lock
    | to that slot, as the stock does when its own search (0x40015226) finds
    | a preset: the lock path takes the slot from its d4 (0x400a687e), which
    | the caller had set to the slot it reserved - left empty, so still free.
    moveq   #0,%d2
psh_f:
    moveq   #68,%d0               | entry = pool + 48 + i * 68
    mulul   %d2,%d0
    addl    %sp@(20),%d0
    addil   #48,%d0
    movea.l %d0,%a2
    movel   %a2,%sp@-
    jsr     0x40013ed8            | empty?
    addql   #4,%sp
    tstb    %d0
    bnes    psh_fnx
    movea.l %a2@,%a0              | its sound
    movel   %a2,%sp@-
    movea.l %a0@(40),%a0
    jsr     %a0@
    addql   #4,%sp
    tstl    %d0
    beqs    psh_fnx
    pea     SND_SIZE
    pea     psh_snd
    movel   %d0,%sp@-
    jsr     0x400ca9cc            | memcmp
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqs    psh_reuse
psh_fnx:
    addql   #1,%d2
    cmpil   #64,%d2
    bcss    psh_f
    movel   %sp@(28),%sp@-        | stored the stock's way
    pea     psh_snd
    movel   %sp@(28),%sp@-
    movea.l psh_fn,%a0
    jsr     %a0@
    lea.l   %sp@(12),%sp
    movel   %d0,%d4
    tstl    %d0
    bnes    psh_no
    moveq   #1,%d0                | the preloader: pool sounds name samples
    movel   %d0,pl_dirty
psh_no:
    movel   %d4,%d0
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
psh_ret:
    rts
psh_reuse:
    movel   %d2,%sp@(8)           | the caller's d4, restored below: that slot
    moveq   #0,%d0                | "stored"
    moveml  %sp@,%d2-%d4/%a2
    lea.l   %sp@(16),%sp
    rts
    .balign 4
psh_fn:      .long 0
psh_snd:     .space SND_SIZE      | the sound a sample lock stores

| ---- browser: the preset parse failed - load it as a sample instead ----
preset_fail_hook:
    movel   %sp@(12),%sp@-
    movel   %sp@(12),%sp@-
    movel   %sp@(12),%sp@-
    jsr     0x400a51fa            | the real preset load
    lea.l   %sp@(12),%sp
    tstl    %d0
    beqw    pf_ret                | a genuine preset: leave everything alone

    lea.l   %sp@(-44),%sp
    moveml  %d1-%d7/%a0-%a3,%sp@
    | arg3 of the preset load is the track the browser is loading to - the
    | firmware's success path adds it as an offset at 0x400a679a. Our frame is
    | 44 bytes, so it sits at sp@(56).
    movel   %sp@(56),%d2
    andil   #0xff,%d2
    cmpil   #MAX_TRK,%d2
    bccw    pf_need
    lea.l   sel_track,%a0
    movel   %d2,%a0@
    jsr     any_sampler
    tstl    %d0
    beqw    pf_need
    lea.l   sel_hash,%a0
    movel   %a0@,%d3
    beqw    pf_bad
    lea.l   track_hash,%a0
    movel   %d3,%a0@(0,%d2:l:4)
    lea.l   track_slot,%a0
    moveq   #-1,%d0
    movel   %d0,%a0@(0,%d2:l:4)   | silence this track while it loads
    lea.l   track_pend,%a0
    movel   %d0,%a0@(0,%d2:l:4)
    jsr     refresh_tracks
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bpls    pf_okt
    jsr     rebuild_slots         | region full: compact, then retry
    jsr     refresh_tracks
    lea.l   track_slot,%a0
    movel   %a0@(0,%d2:l:4),%d0
    bmiw    pf_bad
pf_okt:
    movel   %d2,%d0               | track
    movel   %d3,%d1               | hash
    jsr     name_store            | persist it in the preset name
    lea.l   msg_buf,%a1
    lea.l   msg_ok,%a0
pf_okc:
    moveb   %a0@+,%d1
    beqs    pf_okn
    moveb   %d1,%a1@+
    bras    pf_okc
pf_okn:
    lea.l   sel_track,%a0         | tracks read 1..6 on the panel
    movel   %a0@,%d1
    addil   #49,%d1
    moveb   %d1,%a1@+
    clrb    %a1@
    braw    pf_after
pf_need:
    lea.l   msg_need,%a0
    bras    pf_msg
pf_bad:
    lea.l   fail_why,%a0
    movel   %a0@,%d1
    cmpil   #3,%d1
    beqw    pf_rdmsg              | read error: show the block it failed on
    lea.l   msg_bad,%a0
    subql   #1,%d1
    bmis    pf_msg
    lea.l   msg_e_nf,%a0
    tstl    %d1
    beqs    pf_msg
    subql   #1,%d1
    lea.l   msg_e_mem,%a0
    tstl    %d1
    beqs    pf_msg
    subql   #2,%d1
    lea.l   msg_e_fmt,%a0
    tstl    %d1
    beqs    pf_msg
    lea.l   msg_e_big,%a0
pf_msg:
    lea.l   msg_buf,%a1
pf_cp:
    moveb   %a0@+,%d1
    moveb   %d1,%a1@+
    bnes    pf_cp
    braw    pf_after

    | "Rd <block> L<len>" - which read failed, and where
pf_rdmsg:
    lea.l   msg_buf,%a1
    moveb   #82,%a1@+             | 'R'
    moveb   #100,%a1@+            | 'd'
    moveb   #32,%a1@+             | ' '
    lea.l   err_blk,%a0
    movel   %a0@,%d0
    bsrw    pf_hex8
    moveb   #10,%a1@+             | newline
    moveb   #76,%a1@+             | 'L'
    lea.l   err_len,%a0
    movel   %a0@,%d0
    bsrw    pf_hex8
    clrb    %a1@
    braw    pf_after
pf_hex8:
    moveq   #7,%d3
ph_loop:
    movel   %d3,%d2
    lsll    #2,%d2
    movel   %d0,%d1
    lsrl    %d2,%d1
    andil   #15,%d1
    cmpil   #10,%d1
    bcss    ph_dig
    addil   #55,%d1               | 'A'-10
    bras    ph_put
ph_dig:
    addil   #48,%d1               | '0'
ph_put:
    moveb   %d1,%a1@+
    subql   #1,%d3
    bpls    ph_loop
    rts
pf_after:
    moveml  %sp@,%d1-%d7/%a0-%a3
    lea.l   %sp@(44),%sp
    moveq   #1,%d0                | still "failed", so the popup shows msg_buf
pf_ret:
    | The splice at 0x400a6732 is 6 bytes over a 4-byte PC-relative jsr, so it
    | also swallowed the `movel %d3,%sp@-` that followed. Replay it here, in the
    | caller's frame, by returning manually. a1 is free: the caller reloads it
    | two instructions later (0x400a6746 lea 0x400f980c,%a1).
    movea.l %sp@+,%a1             | return address (0x400a6738)
    movel   %d3,%sp@-             | REPLAY
    jmp     %a1@

    .align 4
win_lo:     .long 0,0,0,0,0,0,0   | playback window, per track: first index
win_span:   .long 0,0,0,0,0,0,0   | ...and its length; 0 = silent
win_rev:    .long 0,0,0,0,0,0,0   | non-zero = Start > End, play backwards
win_wrap:   .long 0,0,0,0,0,0,0   | non-zero = loop mode: wrap, do not stop
atk_gain:   .long 0,0,0,0,0,0,0   | attack ramp, Q24; 16777216 = fully open
atk_step:   .long 0,0,0,0,0,0,0   | per-entry increment; 0 = no attack
    .align 2
voice_ptr:  .long 0,0,0,0,0,0,0   | this track's voice, as sampler_pre sees it
gflt_f:     .long 0,0,0,0,0,0,0   | stock machines' Filter: coefficient, 0 = bypass
gflt_q:     .long 0,0,0,0,0,0,0   | ladder feedback
gflt_mk:    .long 0,0,0,0,0,0,0   | resonance makeup, Q12
gflt_y1:    .long 0,0,0,0,0,0,0   | ladder state, Q12
gflt_y2:    .long 0,0,0,0,0,0,0
gflt_y3:    .long 0,0,0,0,0,0,0
gflt_y4:    .long 0,0,0,0,0,0,0
dial_start: .long 0,0,0,0,0,0,0   | raw Start dial, for the slice window
dial_end:   .long 0,0,0,0,0,0,0   | raw End dial, likewise
    .align 2
filt_f:     .long 0,0,0,0,0,0     | Chamberlin coefficient, Q16; 0 = bypass
filt_q:     .long 0,0,0,0,0,0     | damping, Q16; smaller = more resonant
filt_y1:    .long 0,0,0,0,0,0     | 4-pole ladder state, per track, Q12
filt_y2:    .long 0,0,0,0,0,0
filt_y3:    .long 0,0,0,0,0,0
filt_y4:    .long 0,0,0,0,0,0
    .align 2
scale_state:                      | 0=OFF 1=MAJ 2=MIN 3=DOR 4=PENTA
    .byte 0                       | OFF by default; set from the menu
key_state:
    .byte 0
    .align 2
fold_lengths:
    .byte 7,7,7,5
    .align 2
fold_tables:
    .byte 0,2,4,5,7,9,11
    .byte 0,2,3,5,7,8,10
    .byte 0,2,3,5,7,9,10
    .byte 0,2,4,7,9,0,0
    .balign 4
filt_mk:    .long 0,0,0,0,0,0     | makeup gain per track, Q12
    .align 2
filt_mkt:                         | feedback (>>7) -> makeup, half compensation
    .word 4096,4149,4201,4253,4305,4356,4407,4458
    .word 4509,4559,4609,4659,4709,4758,4806,4855
    .word 4903,4951,4998,5045,5092,5138,5185,5230
    .word 5276,5321,5366,5411,5455,5499,5543,5586
    .word 5629,5672,5715,5757,5799,5841,5883,5924
    .word 5965,6006,6047,6087,6127,6167,6207,6246
    .word 6286,6325,6363,6402,6440,6478,6516,6554
    .word 6592,6629,6666,6703,6740,6777,6813,6849
    .word 6885,6921,6957,6993,7028,7063,7098,7133
    .word 7168,7203,7237,7271,7305,7339,7373,7407
    .word 7440,7474,7507,7540,7573,7606,7639,7671
    .word 7704,7736,7768,7800,7832,7864,7896,7927
    .word 7958,7990,8021,8052,8083,8114,8145,8175
    .word 8206,8236,8266,8297,8327,8357,8387,8416
    .word 8446,8476,8505,8534,8564,8593,8598,8598
    .word 8598,8598,8598,8598,8598,8598,8598,8598
    .align 2
filt_fbmax:                       | stable feedback limit per dial, Q12
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,14974
    .word 14937,14891,14854,14822,14794,14765,14746,14721
    .word 14707,14688,14676,14666,14658,14653,14651,14648
    .word 14649,14651,14655,14661,14666,14673,14683,14693
    .word 14708,14721,14738,14758,14777,14799,14823,14851
    .word 14879,14908,14942,14975,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,15000,15000,15000,15000
    .word 15000,15000,15000,15000,13491,11984,10715,9624
    .align 2
filt_coef:                        | 1 - exp(-2*pi*fc/48000) in Q12, fc spaced
                                  | exponentially from 30 Hz to 16 kHz
    .word 16,17,18,19,20,21,22,23
    .word 24,25,26,28,29,30,32,34
    .word 35,37,39,41,43,45,47,50
    .word 52,55,58,61,64,67,70,74
    .word 78,81,85,90,94,99,104,109
    .word 115,120,126,133,139,146,153,161
    .word 169,177,186,195,205,215,226,237
    .word 249,261,273,287,301,315,331,347
    .word 364,381,399,419,439,460,482,504
    .word 528,553,579,606,634,664,694,726
    .word 759,794,830,867,906,946,987,1031
    .word 1075,1122,1169,1219,1270,1323,1377,1433
    .word 1490,1549,1610,1672,1736,1801,1867,1935
    .word 2004,2074,2145,2217,2290,2363,2437,2511
    .word 2586,2660,2734,2808,2882,2954,3026,3096
    .word 3165,3232,3298,3362,3423,3482,3538,3592

    .align 4                        | 4 BYTES: on this assembler .align n is bytes
gran_state:  .space 6*6*28          | GR_MAX grains per track, see gran_fill
gran_acc:    .space 64*4            | one block's mix, before clamping: 32
                                    | samples for granular, 64 (2x) for wavetable
gr_pos:      .long 0,0,0,0,0,0      | Position, as a sample index
gr_spray:    .long 0,0,0,0,0,0      | Spray range, in samples
gr_len:      .long 0,0,0,0,0,0      | grain length; 0 = nothing to play
gr_int:      .long 0,0,0,0,0,0      | spacing between grain starts
gr_cd:       .long 0,0,0,0,0,0      | samples until the next grain
gr_speed:    .long 0,0,0,0,0,0      | stretch: playhead speed, Q16
gr_ph:       .long 0,0,0,0,0,0      | stretch: playhead index
gr_phf:      .long 0,0,0,0,0,0      | stretch: playhead fraction, 16 bits
pk_epos:     .long 0,0,0,0,0,0      | pluck: strike position, sample index
pk_elen:     .long 0,0,0,0,0,0      | pluck: strike length
pk_damp:     .long 0,0,0,0,0,0      | pluck: Tone coefficient, Q10
pk_comp:     .long 0,0,0,0,0,0      | pluck: that lowpass's delay, Q8
pk_fb:       .long 0,0,0,0,0,0      | pluck: Feedback, Q15
pk_lp:       .long 0,0,0,0,0,0      | pluck: lowpass state
pk_wp:       .long 0,0,0,0,0,0      | pluck: delay line write position
pk_eidx:     .long 0,0,0,0,0,0      | pluck: strike read index
pk_eleft:    .long 0,0,0,0,0,0      | pluck: strike samples left
wv_shift:    .long 0,0,0,0,0,0      | wavetable: log2 frame length; 0 = silent
lf_inc:      .long 0,0,0,0,0,0      | lo-fi: hold step, Q16
lf_mask:     .long 0,0,0,0,0,0      | lo-fi: bits kept
lf_ph:       .long 0,0,0,0,0,0      | lo-fi: hold phase
lf_hold:     .long 0,0,0,0,0,0      | lo-fi: held value
fx_sel:      .long 0,0,0,0,0,0      | Effect (One shot/Loop/Slice): Filter,
                                   | Lo-fi, Tape, Vinyl, None
chn_sel:     .long 0,0,0,0,0,0      | Channels: Mono, Stereo
stu_sel:     .long 0,0,0,0,0,0      | One shot Stutter: OFF 1/4 1/8 1/16 1/32 8T 16T
lp_type:     .long 0,0,0,0,0,0      | Loop: Forward, Reverse, Ping-pong
lp_xfd:      .long 0,0,0,0,0,0      | Loop crossfade: OFF 10 25 50 100 250 ms
lp_sync:     .long 0,0,0,0,0,0      | Loop sync: OFF 1 2 4 bars
sl_md:       .long 0,0,0,0,0,0      | Slice: Equal, Transient (-> sl_cfg)
sl_ct:       .long 1,1,1,1,1,1      | Slice: 8 16 32 (-> sl_cfg)
pk_mode:     .long 0,0,0,0,0,0      | Pluck: Synth, Drum
pk_exc:      .long 0,0,0,0,0,0      | Pluck exciter: Sample, Noise, Click
os_opt:      .long 0,0,0,0,0,0      | (the old options: only the name token's
                                   | fallback still writes these)
                                   | One shot: Normal, Lo-fi, Tape, Vinyl,
                                    | Stutter 1/8, 1/16, 1/32
lp_opt:      .long 0,0,0,0,0,0      | Loop: Forward, Ping-pong, Crossfade,
                                    | Sync 1, 2, 4 bars
st_opt:      .long 0,0,0,0,0,0      | Stretch: Forward, Reverse, Once forward,
                                    | Once reverse, Sync 1, 2, 4 bars
pk_opt:      .long 0,0,0,0,0,0      | Pluck exciter: Sample, Noise, Click, Drum
pp_dir:      .long 0,0,0,0,0,0      | ping-pong: turned round
xf_span:     .long 0,0,0,0,0,0      | crossfade: the loop's true length
xf_x:        .long 0,0,0,0,0,0      | crossfade: blend length
xf_rcp:      .long 0,0,0,0,0,0      | crossfade: 65536 / blend length
st_on:       .long 0,0,0,0,0,0      | stutter: a note has started it
st_cnt:      .long 0,0,0,0,0,0      | stutter: samples to the next repeat
wow_ph:      .long 0,0,0,0,0,0      | tape/vinyl: wow phase
flu_ph:      .long 0,0,0,0,0,0      | tape: flutter phase
tp_lp:       .long 0,0,0,0,0,0      | tape: lowpass state
vn_lp:       .long 0,0,0,0,0,0      | vinyl: lowpass state
vn_cr:       .long 0,0,0,0,0,0      | vinyl: the click in progress
vn_rng:      .long 0x1f123bb5       | vinyl: noise
tv_tone:     .long 65535,65535,65535,65535,65535,65535 | tape/vinyl: Tone, Q16
tv_wear:     .long 0,0,0,0,0,0      | tape/vinyl: Wear, 0..127
pk_rng:      .long 0x9e3779b9,0x7f4a7c15,0x94d049bb,0xbf58476d,0x2545f491,0x6c8e9cf5
gf_rev:      .long 0                | this stretch block runs backwards
gr_shape:    .long 0,0,0,0,0,0      | granular: Hann, Triangle, Perc, Square
gr_dir:      .long 0,0,0,0,0,0      | granular: Forward, Reverse, Random
gr_frz:      .long 0,0,0,0,0,0      | granular: Freeze on trigger
gr_fpos:     .long 0,0,0,0,0,0      | granular: Position when the note started
gr_shapes:   .long hann_tab, tri_tab, perc_tab, sq_tab
sl_cfg:      .long 1,1,1,1,1,1      | slice option: 0..2 = 8/16/32 equal,
                                    | 3..5 = the same with transients, 6 MAN
mk_ok:       .long 0                | mk_tbl cleared since boot
mk_gen:      .long 0                | bumped by every marker change
sle_on:      .long 0                | the slice editor is up
sle_trk:     .long 0                | ...the track it edits
sle_sel:     .long 0                | ...the slice selected
sle_zoom:    .long 0                | ...the view: count >> zoom across
sle_func:    .long 0                | FUNC held
sle_dir:     .long 0                | the last move's way (sle_snap)
sle_dirty:   .long 0                | a trig key selected: redraw
sle_tap:     .long 0                | tapping: armed (or running)
sle_run:     .long 0                | ...the sample playing: presses mark
sle_t0:      .long 0                | ...since this block
sle_cnt:     .long 0                | the edited sample's length
sle_v0:      .long 0                | the view's first sample
sle_sp:      .long 0                | ...and how many
sle_held:    .space 64              | per trig key: its note + 1 while it sounds
sle_cbuf:    .space 4               | SLC's value in MAN
mk_msg:      .space 0x1c            | the UI-task message that saves them
sl_N:        .long 16,16,16,16,16,16 | slice count
sl_S:        .long 0,0,0,0,0,0      | slices in the row; 0 = not ready
sl_key:      .long 0,0,0,0,0,0      | what the row was built from
sl_tbl  = UI_BUF+0x400           | per track: slice starts, then the end (792 B,
                                 | in the region since samplerHW; only read
                                 | once sl_S says its row is built)
wv_fa:       .long 0,0,0,0,0,0      | wavetable: frame A index
wv_fb:       .long 0,0,0,0,0,0      | wavetable: frame B index
wv_m8:       .long 0,0,0,0,0,0      | wavetable: morph A -> B, Q8
wv_det:      .long 0,0,0,0,0,0      | wavetable: unison ratio - 1, Q16
wv_ph:       .space 6*3*4           | wavetable: centre, upper, lower phases
wv_trig:     .byte 0,0,0,0,0,0      | wavetable: restart, from sampler_pre
pk_init:     .byte 0,0,0,0,0,0      | pluck: delay line zeroed
pk_trig:     .byte 0,0,0,0,0,0      | pluck: strike, from sampler_pre
    .align 4
gran_seed:   .long 0x2545F491
ui_gran:     .long 0                | selected track is granular: its labels
gr_on:       .byte 0,0,0,0,0,0      | triggered since entering the mode
gr_trig:     .byte 0,0,0,0,0,0      | trigger edge, from sampler_pre
    .align 4
    .include "granular_tables.inc"
    .align 2
sampler_defaults:                 | k = 11..14 -> sound +42..+48
                                  | The p-lock LED indexes by SLOT while the page
                                  | draws in DESCRIPTOR order, so the two must
                                  | agree or the wrong dial lights up. Resonance
                                  | used to sit on slot 0x10 at page position 6,
                                  | which is why p-locking Filter lit Resonance.
                                  | Now page order == slot order.
    .word 0                       | Sample Start at the beginning
    .word 32512                   | Sample End   maximum = play to the end
    .word 32512                   | Filter       fully open
    .word 0                       | Resonance    off
track_hash:  .long 0,0,0,0,0,0     | what each track wants
track_slot:  .long -1,-1,-1,-1,-1,-1 | resolved slot; -1 = silent. Audio reads this
track_pend:  .long -1,-1,-1,-1,-1,-1 | a slot waiting for the track's next note:
                                   | the low word (-1 = silence), PEND_NOFADE
                                   | when it is the pattern's own sample; -1 none

trk_mach:    .long 0,0,0,0,0,0,0     | each track's machine, from sampler_pre
atk_key:     .long -1,-1,-1,-1,-1,-1,-1 | the Attack dial atk_step was made from
st_cache:    .long 1,1,1,1,1,1,1     | sound+72 as st_apply last decoded it
st_cres:     .long 0,0,0,0,0,0,0     | ...and what it returned
pk_clr:      .long 2048,2048,2048,2048,2048,2048 | Pluck lines cleared so far
gv_gain:     .long 32768,32768,32768,32768,32768,32768 | amp_hook's fade, Q15
track_tried: .long 0,0,0,0,0,0     | hash last attempted, so a missing file is
                                   | tried once but a new selection retries
slot_hash:   .space 4*MAX_SLOT     | resident samples, shared between tracks
slot_base:   .space 4*MAX_SLOT
slot_count:  .space 4*MAX_SLOT
slot_size:   .space 4*MAX_SLOT     | bytes the slot occupies from its base
slot_tpat:   .fill MAX_SLOT,4,-1   | a take: the pattern it was recorded into
slot_ttrk:   .space 4*MAX_SLOT     | ...the track
slot_ttok:   .space 4*MAX_SLOT     | ...and the token it stands in for there
slot_nino:   .space 4*MAX_SLOT     | the inode still to be named (0: done)
slot_nisz:   .space 4*MAX_SLOT     | ...and the size its record gave
slot_nfsz:   .space 4*MAX_SLOT     | DIAG: the size the file system gave
slot_npth:   .fill MAX_SLOT,4,-2   | DIAG: the path's offset in PATH_BUF, -1 none
want_ino:    .long 0
want_isz:    .long 0
nm_hex:      .space 16             | "SMP" + 8 hex digits, for an unnamed file
alloc_top:   .long 0
el_slot:     .long -1              | the slot ensure_loaded is filling
el_lim:      .long 0               | the end of the gap find_gap chose
el_frag:     .long 0               | no gap even after evicting: compact
pd_mode:     .long 0               | 1: the preloader - evict only the unused
kit_ok:      .long -1              | the kit layout checked: 1 ok, 0 not, -1 not yet
want_hash:   .long 0
want_dest:   .long 0
out_bytes:   .long 0
out_count:   .long 0
sel_track:   .long 0
as_found:   .long 0
fail_why:   .long 0
err_blk:    .long 0
err_len:    .long 0
    .align 4
ld_busy:    .long 0
tok_seen:   .long 0
st_ok:      .long 0                | name_probe: this track's packed state applied
sel_hash:   .long 0
sel_size:   .long 0

msg_ok:     .asciz "Sample loaded\nto track "
msg_need:   .asciz "Select sample\nmachine first!"
msg_bad:    .asciz "Sample load\nfailed"
msg_e_nf:   .asciz "Not in sample\nindex"
msg_e_mem:  .asciz "Not enough\nmemory"
msg_e_fmt:  .asciz "Not 48kHz\nmono"
msg_e_big:  .asciz "Sample too\nlarge"
    .align 2
msg_buf:    .space 64

| ---- the DSP scratch buffer, deliberately LAST in the blob ----
| 0x400a9f58 writes 8 longs of history at +0..31 (which is why our fill starts
| at +32) and then walks the buffer with EMAC instructions whose extent we
| cannot read. It used to be a 320-byte array sitting 490 bytes BELOW
| sampler_pre - and the exception PCs we kept seeing (0x401b0f9a, 0x401b0f9e,
| 0x401b0fa2) are exactly sampler_buf+490, +494 and +498: three consecutive
| longs. Two of those three instructions (a PC-relative lea, a tstb of our own
| data) cannot fault, so they were never faulting - they were being OVERWRITTEN,
| and the fault was our own corrupted code executing.
| It now lives at the end of the blob, oversized, with a guard behind it, so
| any overrun lands in padding instead of in sampler_pre.
    | 0x400a9f58 writes 8 longs of history at +0..31 and we fill 64 longs at
    | +32..287, so 288 B are used. 512 leaves margin. It was briefly 2048+512
    | while an overrun was suspected here; the real cause was the filesystem
    | cache overwriting the blob, so the padding bought nothing.
    .align 4
sampler_buf:
    .space 512
