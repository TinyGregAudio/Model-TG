
| Experimental clock on MIDI OUT, via UART9 BREAK. UCR commands follow
| MCF54418RM 41.3.5 table 41-8. BREAK drives TXD low; STOP BREAK drives it
| high. Neither establishes the external TRS voltage or load capability.
| Clock polarity: hold BREAK between pulses, release it for ~5 ms at the
| clock tick. TXD's rising edge is therefore at the start, not the expiry.
| mode: 0 MIDI, 1 quarter, 2 eighth, 3 sixteenth, 4 24 PPQN, 5 idle, 6 break.
| Only physical TX is intercepted. RX DMA36 and USB paths remain stock.
GATE_UCR = 0xec074008
GATE_USR = 0xec074004
GATE_PULSE = 8                    | ~5 ms, expired by 1500 Hz audio blocks

| Producer checks are INSIDE the stock IPL7 critical sections. Checking only
| at entry would race a mode change while a writer was preempted. Existing
| queues drain normally before gate_service claims the idle transmitter.
| A caller waiting for queue space can therefore still finish, then drop
| its data here. Do not reset queues, block the audio ISR, or change RX.
gate_tx_buffer:                   | replaces 0x40001154..0x4000115d
    tstl    gate_mode
    bnes    gtb_drop
    tstl    gate_active
    bnes    gtb_drop
    movel   %a0,%d1
    addl    %d0,%d1
    tstl    0x4049dca0
    jmp     0x4000115e
gtb_drop:
    jmp     0x40001226            | restore saved SR/d2-d5 and return

gate_tx_byte:                     | replaces 0x4000124e's tstl
    tstl    gate_mode
    bnes    gty_gate
    tstl    gate_active
    bnes    gty_gate
    tstl    0x4049dca0
    jmp     0x40001254
gty_gate:
    bsr     gate_clock            | d1 = byte; d2 holds the stock saved SR
    jmp     0x400012c4            | restore SR/d2/d3 and return

gate_flush_status:                | replaces 0x40001320's status read
    tstl    gate_active
    beqs    gfs_stock
    moveq   #8,%d0                | no MIDI pending during BREAK: TXEMP
    jmp     0x40001326
gfs_stock:
    moveb   GATE_USR,%d0
    jmp     0x40001326

| gate_line(d0 = 0 idle, 1 break). Called only with IPL7 and ownership.
| Write only on edges. Does not touch the driver polarity configuration.
gate_line:
    cmpl    gate_level,%d0
    beqs    gl_out
    movel   %d0,gate_level
    tstl    %d0
    beqs    gl_idle
    moveq   #0x60,%d0
    moveb   %d0,GATE_UCR
    rts
gl_idle:
    moveq   #0x70,%d1
    moveb   %d1,GATE_UCR
gl_out:
    rts

| Existing outgoing real-time bytes supply timing, not a second tempo
| oscillator. CLK OUT and OUT TO MID/M+U must be enabled. Only send
| while the internal sequencer plays; STOP drops the current pulse too.
| Keeps d2-d7/a2-a6, particularly the UART writer's saved SR in d2.
gate_clock:
    movel   gate_active,%d0
    beqs    gc_ret
    cmpl    gate_mode,%d0
    bnes    gc_ret                | a change is waiting for the audio hook
    cmpil   #4,%d0
    bhis    gc_ret                | fixed-level tests ignore clocks
    andil   #255,%d1
    cmpil   #0xfc,%d1
    beqs    gc_reset
    cmpil   #0xfa,%d1
    beqs    gc_start
    cmpil   #0xf8,%d1
    bnes    gc_ret
    tstl    0x40a7883c            | stock transport playing flag
    beqs    gc_reset
    tstl    gate_count
    beqs    gc_pulse
    subql   #1,gate_count
gc_ret:
    rts
gc_start:
    | Stock's local Start path sets playing before sending FA (0x4005508e,
    | 0x400550a0). Waiting for a later F8 adds a tempo-dependent startup tick.
    | Count Start as pulse zero; gc_pulse reloads divisor-1 so the next edge
    | is on the divisor-th F8, not on the first F8 after Start.
    tstl    0x40a7883c
    beqs    gc_reset
gc_pulse:
    lea.l   gate_divs,%a0
    subql   #1,%d0
    movel   %a0@(0,%d0:l:4),%d0
    subql   #1,%d0
    movel   %d0,gate_count
    moveq   #GATE_PULSE,%d0
    movel   %d0,gate_timer
    moveq   #0,%d0               | rising TXD edge at the clock tick
    braw    gate_line
gc_reset:
    clrl    gate_count
    clrl    gate_timer
    moveq   #1,%d0               | clock baseline is BREAK, including Stop
    braw    gate_line

| Once per audio block. A nonzero request blocks NEW physical MIDI sends;
| old buffers and real-time bytes finish through the stock DMA/IRQ paths.
| Claim only with both queues empty, driver idle, DMA inactive, UART empty.
| IPL7 protects this check + claim against producers and completion ISRs.
| No polling loops: a busy UART is checked again next block.
gate_service:
    movel   gate_mode,%d0
    orl     gate_active,%d0
    beqw    gs_ret
    movel   %d2,%sp@-
    movew   %sr,%d2
    movew   #0x2700,%sr
    movel   gate_mode,%d0
    cmpl    gate_active,%d0
    beqw    gs_run
    tstl    gate_active
    beqs    gs_claim
    moveq   #0x70,%d1
    moveb   %d1,GATE_UCR        | no FIFO data was accepted during gate
    clrl    gate_level
    clrl    gate_active
    clrl    gate_timer
    clrl    gate_count
gs_claim:
    tstl    %d0
    beqw    gs_done
    movel   0x4049dca0,%d1        | driver: 0 idle, 1 DMA, 2 byte queue
    orl     0x4049dcbc,%d1        | buffered MIDI waiting
    orl     0x4049dccc,%d1        | real-time/thru bytes waiting
    bnew    gs_done
    movew   0xfc0454be,%d1       | DMA37 CSR
    btst    #6,%d1               | ACTIVE: do not steal a running transfer
    bnew    gs_done
    moveb   GATE_USR,%d1
    btst    #3,%d1               | TXEMP includes FIFO + shift register
    beqw    gs_done
    moveq   #37,%d1
    moveb   %d1,0xfc044019       | CERQ: disable only TX DMA requests
    moveq   #37,%d1
    moveb   %d1,0xfc04401c       | CINT: acknowledge stale TX completion
    moveq   #53,%d1
    moveb   %d1,0xfc04c01c       | UART TX IRQ masked, as in stock idle
    moveq   #0x04,%d1
    moveb   %d1,GATE_UCR       | BREAK requires enabled transmitter
    movel   %d0,gate_active
    clrl    gate_timer
    clrl    gate_count
    clrl    gate_level
    cmpil   #5,%d0
    beqs    gs_done              | only the IDLE test holds TXD high
    moveq   #1,%d0
    bsr     gate_line
    bras    gs_done
gs_run:
    cmpil   #4,%d0
    bhis    gs_done              | fixed-level tests
    tstl    0x40a7883c
    beqs    gs_stop
    tstl    gate_timer
    beqs    gs_done
    subql   #1,gate_timer
    bnes    gs_done
    moveq   #1,%d0               | pulse over: return to BREAK
    bsr     gate_line
    bras    gs_done
gs_stop:
    bsr     gc_reset             | also works when TRANSPORT SEND is off
gs_done:
    movew   %d2,%sr
    movel   %sp@+,%d2
gs_ret:
    rts

gate_lab:
    lea.l   gate_s_lab,%a1
    jmp     gm_lab
gate_val:
    lea.l   gate_mode,%a0
    lea.l   gate_names,%a1
    jmp     gm_val
gate_rot:                        | closure, item, signed encoder delta
    movel   %sp@(12),%d0
    beqs    gr_ret
    movel   gate_mode,%d1
    tstl    %d0
    bmis    gr_dec
    addql   #1,%d1
    cmpil   #6,%d1
    bhis    gr_ret
    bras    gr_set
gr_dec:
    subql   #1,%d1
    bmis    gr_ret
gr_set:
    movel   %d1,gate_mode         | audio hook applies ownership changes
    movea.l %sp@(4),%a0
    movea.l %a0@,%a0
    movel   %a0@,%d0
    beqs    gr_ret
    addil   #0x38,%d0
    movel   %d0,%sp@-
    jsr     0x40076082
    addql   #4,%sp
gr_ret:
    rts

    .balign 4
gate_mode:   .long 0             | runtime only: MIDI on every boot
gate_active: .long 0             | nonzero only after UART drained
gate_level:  .long 0             | 0 TXD idle, 1 BREAK (not measured volts)
gate_timer:  .long 0
gate_count:  .long 0
gate_divs:   .long 24,12,6,1
gate_row:    .long gate_lab,gate_val,gate_rot,id_press
gate_names:  .long gate_s_off,gate_s_q,gate_s_e,gate_s_s,gate_s_24,gate_s_idle,gate_s_break
gate_s_lab:  .asciz "Gate Clock"
gate_s_off:  .asciz "OFF"
gate_s_q:    .asciz "1/4"
gate_s_e:    .asciz "1/8"
gate_s_s:    .asciz "1/16"
gate_s_24:   .asciz "24PPQN"
gate_s_idle: .asciz "IDLE"
gate_s_break:.asciz "BREAK"
    .balign 2
