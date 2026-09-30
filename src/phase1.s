| Phase 1: the boot clear, the machine-list/icon lazy init, the Sampler name
| table, the two descriptor lookups and the machine-commit trampoline.
|
| This is LINKED INTO THE SAME BLOB as sampler_voice (after it), not placed at
| the old fixed address 0x401aa140. That address sat inside a 16 KiB buffer at
| 0x401a7750..0x401ab750 which the filesystem copies to disk to blank every
| newly allocated chunk (0x40079462 / 0x400794ce), relying on it being zero.
| With our code in it, new chunks were "blanked" with our code instead.
|
| THE BOOT CLEAR - what it must do, and what went wrong:
|   Stock (0x400004b2) zeroes 0x4019b590..0x423380b0 after the image tail has
|   been copied to SRAM (0x4000045c). We must do the same, skipping only our
|   own code: [blob_start, reserved_end). Both are link-time symbols
|   (--defsym), so there is no PC-relative displacement to bake in and no
|   ceiling on the blob's size.
|   A build-time "holepunch" patch replaced the skip test with "start the clear
|   at reserved_end", on the premise that our blob sat at the START of the
|   cleared region. It did not - it sat 59 KiB in - so every build from samplerW
|   to samplerEF left 0x4019b590..(blob) uncleared, including that zero buffer.
|   samplerCO's "plays once, then never" was very probably this too: it had
|   moved blob B's persistent state down into the uncleared region.
|   RULE: nothing of ours may live below 0x401ab750. Everything we own sits in
|   retired filesystem cache blocks, which nothing else touches.

    .globl  boot_extra_hook, sampler_lazy_init_trampoline, sampler_name_table
    .globl  table_lookup_a_fixed, table_lookup_b_fixed, log_trampoline
    .text
    | Guard: this is linked straight after sampler_voice, whose last item is
    | sampler_buf - driven by EMAC code whose extent we cannot read. Keep a
    | margin between it and executable code.
    .space  256

boot_extra_hook:
    lea.l   %sp@(-16),%sp
    moveml  %d4-%d7,%sp@

    | The sample region's upper 64 MiB block group, 0x4C000000-0x4FFFFFFF,
    | into the data cache, write-through (ACR1 - stock sets only ACR0, for
    | 0x40000000-0x47FFFFFF, copyback; everything else defaults to
    | cache-inhibited). Base 0x4C, mask 0x03, enabled, any mode (0xE000), CM
    | 00 write-through: memory always holds what the CPU wrote, for the eMMC's
    | DMA and anything else that reads it, and the driver pushes a DMA
    | destination's lines before reading into it (0x4008b2d8). The block below,
    | 0x4A-0x4B, holds the audio output and the eMMC bounce buffer and stays
    | uncached. Set here, before 0x40000542 enables (and invalidates) the
    | caches; nothing in stock touches ACR1 afterwards.
    movel   #0x4c03e000,%d4
    movec   %d4,%acr1
    lea.l   0x4019b590,%a0          | where stock's own clear starts (0x400004ba)
    moveq   #0,%d4
    moveq   #0,%d5
    moveq   #0,%d6
    moveq   #0,%d7
clear_loop:
    cmpal   #blob_start,%a0         | our code starts here (link-time symbol);
    bnes    do_clear                | the step is 16 and both ends are 16-aligned,
    moveal  #reserved_end,%a0       | so this is hit exactly - then skip our code
do_clear:
    cmpal   #0x423380b0,%a0
    bccs    clear_done              | a0 >= original end (unsigned)? done
    moveml  %d4-%d7,%a0@
    lea.l   16(%a0),%a0
    bras    clear_loop
clear_done:
    moveml  %sp@,%d4-%d7
    lea.l   %sp@(16),%sp

    | replay the second overwritten instruction exactly, then continue
    | normal boot at the original continuation point
    lea.l   0xfc044000,%a0
    jmp     0x4000053a

| ---------------------------------------------------------------
| Sampler-catalog logic below, unchanged from test 9
| (cycles_sampler_catalog_uihook.s) - see that file's own header
| comment for the full design rationale.
| ---------------------------------------------------------------

sampler_lazy_init_trampoline:
    movel   4(%a7),%d0             | the page being drawn: nm_tick keeps its
    movel   %d0,mp_obj             | Sampler name current and redraws it
    movel   %a2,-(%a7)
    movel   %d2,-(%a7)

    movea.l 0x40fe32cc,%a0     | a0 = table A vector "begin"
    movea.l 0x40fe32d0,%a1     | a1 = table A vector "end"
    movel   %a1,%d0
    subl    %a0,%d0             | d0 = end - begin (byte count of live elements)
    cmpil   #196,%d0            | already rebuilt to 7 elements (7 * 0x1c)?
    beqs    already_done
    bsr     build_sampler_icons
already_done:
    movel   (%a7)+,%d2
    movel   (%a7)+,%a2
    jmp     0x400a24ca

build_sampler_icons:
    | ---------- Table A (0x40fe32cc): 48x33 icons ----------
    movel   #196,-(%a7)            | 7 * 0x1c
    jsr     0x40080064             | d0 = new heap buffer
    addql   #4,%a7
    moveal  %d0,%a2                | a2 = new buffer base (table A)

    moveal  0x40fe32cc,%a0         | a0 = old buffer base (vector "begin")
    moveal  %a2,%a1                | a1 = dest cursor
    movel   #42,%d1                | 42 longwords = 168 bytes (6 icons * 0x1c)
copyA_loop:
    movel   (%a0)+,(%a1)+
    subql   #1,%d1
    bnes    copyA_loop

    lea.l   168(%a2),%a1           | icon #6 slot (Sampler)
    movel   #0x401117c8,(%a1)+     | vtable
    movel   #48,(%a1)+             | width
    movel   #33,(%a1)+             | height
    movel   #2,(%a1)+              | ceil(33/32) words per column
    movel   #sampler_icon_a_pixels,(%a1)+
    movel   #0x4016ac78,(%a1)+     | reuse existing shared palette A
    clrl    (%a1)                  | flag byte (+ pad, all zeroed)

    movel   %a2,%d2                | d2 = new buffer base, kept for arithmetic
    lea.l   0x40fe32cc,%a0
    movel   %d2,(%a0)+             | vector.begin = new buffer
    lea.l   196(%a2),%a1           | new buffer + 7*0x1c
    movel   %a1,(%a0)+             | vector.end
    movel   %a1,(%a0)               | vector.capacity_end

    | ---------- Table B (0x40fe384c): 34x34 icons ----------
    movel   #196,-(%a7)
    jsr     0x40080064
    addql   #4,%a7
    moveal  %d0,%a2                | a2 = new buffer base (table B)

    moveal  0x40fe384c,%a0
    moveal  %a2,%a1
    movel   #42,%d1
copyB_loop:
    movel   (%a0)+,(%a1)+
    subql   #1,%d1
    bnes    copyB_loop

    lea.l   168(%a2),%a1
    movel   #0x401117c8,(%a1)+
    movel   #34,(%a1)+
    movel   #34,(%a1)+
    movel   #2,(%a1)+               | ceil(34/32) words per column
    movel   #sampler_icon_b_pixels,(%a1)+
    movel   #0x4017c20c,(%a1)+     | reuse existing shared palette B
    clrl    (%a1)

    movel   %a2,%d2
    lea.l   0x40fe384c,%a0
    movel   %d2,(%a0)+
    lea.l   196(%a2),%a1
    movel   %a1,(%a0)+
    movel   %a1,(%a0)

    rts

    .align 2
sampler_name_table:
    .long   0x401300d8             | Kick
    .long   0x401300dd             | Snare
    .long   0x401300e3             | Metal
    .long   0x401300e9             | Perc
    .long   0x40129960             | Tone
    .long   0x401300ee             | Chord
    .long   mach_nbuf              | Sampler: the track's sample name (nm_tick)

sampler_name_string:
    .ascii  "Sample"
    .byte   0,0               | keep this 8 bytes: sampler_icon_a_pixels sits at
                              | +8 and everything after it is addressed by the
                              | stock-area patches, so the length must not move

    .align 2
sampler_icon_a_pixels:
    .incbin "sampler_icons/sampler_icon_A_48x33.bin"

    .align 2
sampler_icon_b_pixels:
    .incbin "sampler_icons/sampler_icon_B_34x34.bin"

| ---------------------------------------------------------------
| Fix for FUN_4004df5c / FUN_4004df76 (the per-machine-type info
| table lookup, base 0x40a71540, stride 0x4c/76 bytes). Both
| functions have no slot for machine index 6 (Sampler) and return
| an out-of-bounds/underflowed address for it, which is what causes
| the freeze when navigating onto the Sampler slot: the caller
| (FUN_40014072, the "value changed" notify) reads and rewrites
| memory through that bad pointer. This table's records are built at
| boot via string-object constructor calls (FUN_400f980c and
| friends), not plain data, so fabricating a real 7th record by hand
| is high-risk; instead alias index 6 to the already-initialized
| slot for machine 0 (Kick). Matches Phase 1's own stated scope:
| give Sampler safe/inert values, not full correctness, for fields
| outside the catalog itself.
| ---------------------------------------------------------------

table_lookup_a_fixed:              | replaces FUN_4004df5c (called with machineIndex+1)
    movel   %sp@(4),%d0
    cmpil   #7,%d0
    bnes    a_not_seven
    moveq   #1,%d0                  | alias -> slot 1 (Kick), same slot machineIndex 0 uses
a_not_seven:
    moveq   #6,%d1
    cmpl    %d0,%d1
    bccs    a_domul
    moveq   #-1,%d0
a_domul:
    moveq   #76,%d1
    mulsl   %d1,%d0
    addil   #0x40a71540,%d0
    rts

table_lookup_b_fixed:              | replaces FUN_4004df76 (called with raw machineIndex)
    movel   %sp@(4),%d0
    cmpil   #6,%d0
    bnes    b_not_six
    moveq   #0,%d0                  | alias -> raw index 0 (Kick)
b_not_six:
    moveq   #5,%d1
    cmpl    %d0,%d1
    bccs    b_remap
    moveq   #-1,%d0
    bras    b_domul
b_remap:
    lea.l   0x401091b4,%a0
    moveq   #6,%d1
    mvsb    %a0@(0,%d0:l),%d0
    cmpl    %d0,%d1
    bcss    b_invalid
    bras    b_domul
b_invalid:
    moveq   #-1,%d0
b_domul:
    moveq   #76,%d1
    mulsl   %d1,%d0
    addil   #0x40a71540,%d0
    rts

| ---------------------------------------------------------------
| Phase 2 diagnostic: log every machine-index (opcode 0x29) commit
| as a SysEx message out the MIDI OUT port. Redirects FUN_40014072's
| entry (the "value changed" notify, confirmed this session to have
| exactly one caller - FUN_4001477e, the direct/live machine-index
| write path - so no opcode filtering is needed here). Replays the
| two overwritten prologue instructions, sends the diagnostic
| message, then jumps back to resume the original function body
| unchanged so existing Phase 1 functionality (Sampler catalog
| lookups etc, all of which run through this same notify) keeps
| working exactly as before.
|
| Message 1 format (all 7-bit safe - each raw byte split into two
| nibble bytes so it can never be misread as a MIDI status byte):
|   F0 00 20 3C 7F <trackHandle:4 bytes, 8 nibbles>
|                  <kit ptr _DAT_40a7887c:4 bytes, 8 nibbles>
|                  <new machine index:1 byte, 2 nibbles> F7
| Fixed length 24 bytes.
|
| Message 2 (tag 0x7E) - added to test the still-open Phase 2
| question of whether machine assignment writes anything into the
| shared kit struct's per-track sub-record. A first, narrow version
| of this (tag 0x7E, just the tail 16 bytes at +0x2c0..0x2d0) found
| no change across 8 real machine-index commits on 2 different
| tracks - but that only tested 16 of the sub-record's 722 bytes.
| This version (tag 0x7D) covers the *entire* 0x2d2-byte sub-record,
| sent as 12 sequential 64-byte-chunk messages (the last chunk reads
| ~46 bytes past the true boundary into the next track's sub-record -
| harmless for a read-only diagnostic, just ignore the tail of chunk
| 12 when interpreting):
|   F0 00 20 3C 7D <trackIdx:2 nibbles> <chunkIndex:2 nibbles>
|                  <64 bytes, 128 nibbles> F7
| Fixed length 138 bytes per chunk, 12 chunks per commit (~1.6KB /
| ~5s of SysEx per encoder turn at standard MIDI baud - expect a
| brief UI pause after each turn during this specific test; avoid
| turning the encoder again until a turn's 12 chunks have finished
| arriving, since messages aren't queued/buffered in this hook).
| Shares one 144-byte scratch buffer with message 1 (large enough for
| the largest of the two), reused in place rather than reallocated.
| ---------------------------------------------------------------

log_trampoline:
    | Hooked at 0x40014072 (getMachine's commit path). Everything this used to
    | do between the prologue and the tail was diagnostics: it built a tag-0x7F
    | SysEx message - track handle, descriptor pointer, the machine index read
    | back through the track vtable - and sent it through 0x400826b0 on EVERY
    | call. That is a lot of MIDI for a shipped firmware.
    | What must remain: replay the two instructions the hook overwrote, then
    | reach the shadow-table update, which is the load-bearing part.
    linkw   %fp,#-144
    moveml  %d2-%d6/%a2-%a5,%sp@
    jmp     log_trampoline_tail_patch   | sampler_track_table_standalone.s:
                                        | bsr update_sampler_table ; jmp 0x4001407a

| The SysEx diagnostics that followed here - emit_byte/emit_long and the
| plock loggers plock_write_hook, plock2_hook and plock_write_log - were never
| installed in any shipped build (no hook reached them) and were removed in
| samplerHN to return a filesystem cache block. See git history for them.
