| sampler_track_table_standalone.s - Phase 2, first real feature piece
| (not a diagnostic dump): maintains a persistent, CPU-accessible
| shadow table of "which track is currently assigned Sampler (index
| 6)", updated whenever a track's DEFAULT machine commits.
|
| WHY THIS IS NEEDED: hardware-confirmed earlier this session
| (diaglog5/diaglog6) that reassigning a track's machine does NOT
| write anywhere into the shared kit struct FUN_40054c1e (the
| sequencer tick ISR) reads from - machine state lives only in the FM
| coprocessor's own persistent per-channel state, which the CPU-side
| ISR has no access to. Without our own shadow copy, the ISR has no
| way to know "is this track Sampler" at trigger time at all.
|
| SCOPE (deliberately limited for a first working version): tracks
| only the per-TRACK DEFAULT machine (via FUN_40014072's commit path,
| the plain/direct encoder-turn - already safely hooked all session as
| log_trampoline). Does NOT yet handle per-STEP P-Lock machine
| overrides (FUN_400a21a4's commit path) - a real limitation, but a
| reasonable one to defer: a track's default machine covers the common
| case, and P-Lock-to-Sampler support can be added once this base
| mechanism is proven on real hardware.
|
| Re-derives trackHandle/trackIdx/newMachineIndex independently from
| %fp@(8) (FUN_40014072's own first parameter, guaranteed stable since
| %fp itself is never touched by any hook this session) rather than
| trusting log_trampoline's own possibly-clobbered-by-then register
| state at the tail jmp - duplicates ~20 instructions already proven
| safe elsewhere in this file, but avoids a real correctness risk.
|
| Tag 0x6C (unused so far this session): F0 00 20 3C 6C <2 nibbles
| trackIdx><2 nibbles rawNewMachineIndex><2 nibbles valueWritten>
| <12 nibbles = 6 bytes, the full table after the write> F7. Fixed
| length 24 bytes - logs the write for verification, does not change
| any existing behavior.

    .globl  log_trampoline_tail_patch
    | Linked into the main blob after Phase 1. What is load-bearing here is the
    | CONTINUATION: log_trampoline jumps in and this carries on to 0x4001407a.
    | sampler_track_table itself is write-only - nothing in the image reads it
    | (no 32-bit reference anywhere; only this file's own PC-relative store) -
    | so BUILD.md's "the sequencer ISR uses it" was never true. It is kept only
    | so this change moves code without also changing behaviour. It is placed
    | LAST in the blob, so a track index past 5 writes into the retired cache
    | block's slack rather than into our code.
log_trampoline_tail_patch:
    bsr     update_sampler_table
    jmp     0x4001407a          | the ORIGINAL destination log_trampoline's
                                  | own final instruction used to jump to

update_sampler_table:
    lea.l   %sp@(-48),%sp              | reserve scratch (24 needed,
                                         | margin to 48)
    movea.l %sp,%a0                      | cursor

    | ---- re-derive machine index, exactly matching log_trampoline's
    | own already-proven-correct message-1 logic (FUN_4001477e's own
    | accessor: vtable+0x28 call, then byte at result+0x26) ----
    moveal  %fp@(8),%a1                   | a1 = trackHandle (param_1,
                                            | stable via %fp)
    moveal  %a1@,%a2                       | a2 = *trackHandle (the
                                             | object)
    movel   %fp@(8),%sp@-
    moveal  %a2@(0x28),%a2
    jsr     %a2@
    lea.l   %sp@(4),%sp
    moveal  %d0,%a2
    moveb   %a2@(0x26),%d1                  | d1 = new machine index
                                              | (raw, pre-<<8 form) -
                                              | moveb only sets the LOW
                                              | byte of d1, upper 3
                                              | bytes are stale garbage
                                              | from whatever last used
                                              | d1 (hardware-confirmed
                                              | via accessor_probe/
                                              | diaglog49 logging raw
                                              | d5 values like 0x20004
                                              | instead of clean 0x04)
    andil   #0xff,%d1                          | mask to the real byte
                                                 | value before using it
    movel   %d1,%d5                           | d5 = keep a copy for
                                                | logging later

    | ---- re-derive trackIdx, exactly matching log_trampoline's own
    | already-proven-correct division-loop logic ----
    jsr     0x400cf866                       | d0 = kit/project singleton
    movel   %fp@(8),%d2                       | d2 = trackHandle
    subl    %d0,%d2                            | d2 -= singleton
    subl    #0xd4,%d2                           | d2 -= 0xd4
    moveq   #0,%d3                               | d3 = trackIdx accumulator
sampler_track_div_loop:
    cmpl    #0x44,%d2
    bltw    sampler_track_div_done
    subl    #0x44,%d2
    addql   #1,%d3
    braw    sampler_track_div_loop
sampler_track_div_done:
                                                   | d3 = trackIdx (0-5)

    | ---- update the shadow table: sampler_track_table[trackIdx] =
    | (newMachineIndex == 6) ? 1 : 0 ----
    lea.l   sampler_track_table,%a2
    addl    %d3,%a2                            | a2 = &table[trackIdx]
    moveq   #0,%d4
    cmpil   #6,%d5
    bnew    sampler_track_write
    moveq   #1,%d4
sampler_track_write:
    moveb   %d4,%a2@

    | ---- tag-0x6C SysEx logging removed -----------------------------------
    | The table write above is the load-bearing part: it is what lets the
    | sequencer ISR know a track is a Sampler. The block that used to follow
    | built a 24-byte tag-0x6C message and sent it through 0x400826b0 on EVERY
    | default-machine commit, unconditionally - live MIDI output in a shipped
    | firmware, serving nothing for a user, and this file's own notes blame
    | heavy SysEx logging for recording misbehaviour elsewhere. The emit_byte
    | helper it used (0x401aa6e0) stays in blob A; nothing calls it now.
    lea.l   %sp@(48),%sp

    rts

    .align 4
sampler_track_table:
    .space 6          | one byte per track: 0 = not Sampler, 1 = Sampler
