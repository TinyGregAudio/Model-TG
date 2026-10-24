# Experimental MIDI OUT gate clock (OS 1.13)

The starting evidence was the static UART/GPIO report in
`../digiemu/out/model-cycles-gate/`. Its conclusion remains a hardware
limitation: controllable TXD does not establish a usable voltage at the jack.

UART9 is at `0xEC074000`. Byte commands to UCR9 (`+8`) enable TX (`0x04`),
start BREAK (`0x60`) and stop BREAK (`0x70`). Start requires TX enabled and
can wait one bit time on an empty transmitter; stop releases TXD within two
bit times. At MIDI baud, these bounds are 32 and 64 microseconds. See
[NXP MCF54418RM, §41.3.5, table 41-8](https://www.nxp.com/docs/en/reference-manual/MCF54418RM.pdf).

The stock port settings are documented in
[Model:Cycles OS 1.13 manual, §12.3](https://www.elektron.se/wp-content/uploads/2024/10/Model-Cycles-User-Manual_ENG_OS1.13_241030.pdf).
Gate clock uses that existing clock sender, requiring CLK OUT on, OUT TO
MID/M+U and OUT/THRU OUT. No extra tempo oscillator is introduced. The
stock polarity GPIO (PF3) is left alone.

## Ownership and hooks

| Address | Role |
|---|---|
| `0x40001154` | Buffered TX, after saving SR and raising IPL7: suppress new data while requested/active |
| `0x4000124E` | Byte TX, also inside IPL7: consume real-time clock/transport and suppress physical MIDI |
| `0x40001320` | Flush's UART-status read: report empty while gate owns an already drained transmitter |
| `0x4049DCA0` | Stock transmit state (idle/DMA/byte queue) |
| `0x4049DCBC` / `0x4049DCCC` | Pending buffer/byte counts |
| `0xFC0454BE` | TX DMA37 CSR; ACTIVE bit 6 |
| `0xEC074004` | UART status; TXEMP bit 3 includes FIFO and shift register |

`gate_mode` is the menu request; `gate_active` is the mode that owns TX.
Checks in the producer critical sections prevent a task preempted before
enqueue from writing after the mode changes. Both software queues keep
draining through the unmodified UART/DMA interrupts. Once the driver and
queues are idle, DMA is inactive and the UART is empty, `gate_service`
claims TX under IPL7. It disables DMA37 requests, acknowledges any stale
DMA37 completion, and masks UART interrupt source 53 (as stock does at idle).
RX DMA36 is untouched. There is no busy-wait in the audio path.

Restoring MIDI stops BREAK before clearing ownership. Nothing has entered
the FIFO while gate owns it. The next stock send can directly write a byte
or start DMA as usual; byte-queue interrupts are unmasked by the stock writer
when necessary. Buffered messages and non-clock real-time bytes are discarded
during gate mode, not queued for playback later. USB routing occurs above
these physical-port hooks and is unchanged.

Clock mode holds BREAK between pulses and releases it at the clock tick.
This puts the TXD rising edge at pulse start instead of about 5 ms later.
Start (FA) emits pulse zero immediately while playback is active and reloads
the divider. The next edge is on the divisor-th F8. Previously Start only
reset the counter, waiting for the next F8 and potentially adding one tick
(83.3 ms at 30 BPM, 20.8 ms at 120 BPM). The local stock Start path sets
playing at `0x4005508E` before sending FA at `0x400550A0`. Actual alignment
with audio still needs a hardware timing comparison; this is a test fix for
the reported tempo-dependent delay.
The audio output wrapper restores BREAK after eight 32-sample blocks
(roughly 4.7–5.3 ms, plus UART command latency). It also restores BREAK
when the stock playing flag clears, even without a transmitted Stop byte.
The default disabled path is one call, two flag reads, an OR/branch and return
per block, plus the producer checks. Actual CPU and timing must be measured.

## Validation

Run `python3 build.py --assemble-only`, then
`python3 tools/test_midi_gate.py` with Unicorn installed. The tests execute
the assembled CFV4E routines and check all clock divisions, expiry, transport,
fixed test states, deferred claims for each busy condition, command widths,
MIDI suppression during transitions, register preservation, flush and the
disabled stock continuation paths. Full builds also assert all replaced
stock bytes before patching.

The test MMIO model does not establish DMA arbitration, whole-firmware
scheduling, real UART latency, or electrical behavior. Before calling the
feature hardware-validated, measure IDLE/BREAK voltages on a TRS breakout,
check pulse polarity/width and all rates on a scope, and verify stop/start,
mode switching under TX load, restored normal MIDI, MIDI input and USB.
