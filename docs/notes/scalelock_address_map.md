# Scale Lock: Model:Samples -> Model:Cycles address map

Both firmwares are the same framework compiled twice, so every Scale Lock
dependency has a direct counterpart. Each was found by matching function bytes
with embedded absolute addresses treated as wildcards, and each was then
verified a second, independent way.

| symbol            | Samples     | Cycles      | how verified |
|-------------------|-------------|-------------|--------------|
| NOTE_ON site      | 0x4008079c  | 0x4008173c  | identical prologue; same `bcsw` displacement |
| NOTE_OFF site     | 0x400804d4  | 0x40081474  | prologue identical byte for byte |
| ALLOC             | 0x4007f0c4  | 0x40080064  | unique 64-byte match |
| FREE_CLOSURE      | 0x400cacca  | 0x400cf044  | unique 64-byte match |
| MENUITEM_CTOR     | 0x40072510  | 0x400734b0  | unique 64-byte match |
| MENUVIEW_ADDITEM  | 0x40071d46  | 0x40072ce6  | unique 64-byte match |
| FORMAT_STRING     | 0x400f4bd0  | 0x400f980c  | unique; also call #1 of the menu fn |
| TINYSTR_WRAP      | 0x400f3980  | 0x400f85bc  | unique 64-byte match |
| DRAW_FMT_A        | 0x400712c0  | 0x40072260  | unique 64-byte match |
| DRAW_FMT_B        | 0x400710e0  | 0x40072080  | unique 64-byte match |
| DRAW_TEXT         | 0x40070a64  | 0x40071a04  | unique 64-byte match |
| FREE_TINYSTR      | 0x400f3120  | 0x400f7d5c  | unique; also call #3 of the menu fn |
| SLOT2_MANAGER     | 0x400306c4  | 0x4002f188  | read positionally out of the menu fn |
| GENERIC_MANAGER   | 0x40030672  | 0x4002f136  | relative to SLOT2_MANAGER; 0 byte diffs |
| SLOT2_INVOKER     | 0x40030176  | 0x4002ec3a  | relative; 0 byte diffs AND in the fuzzy candidate list |
| menu fn           | 0x40030874  | 0x4002f338  | same size (1196 B), same 10 calls in order |
| MENU HOOK site    | 0x40030d14  | 0x4002f7d8  | same offset (+0x4A0); epilogue identical |

## Notes

- `GENERIC_MANAGER` and `SLOT2_INVOKER` have **zero** references in either
  image - they are only reached through closures built at runtime, so they
  cannot be found by reference searching. Relative position from
  `SLOT2_MANAGER` plus a byte comparison is what resolves them.
- The hooked instruction at the menu site is the same on both:
  `4cef 7c7c 0018  moveml %sp@(24),%d2-%d6/%a2-%fp`
- **Difference that matters for the note hooks:** on Samples d5/d6 are dead at
  the hook point; on Cycles both are live (0x40081730 loads %fp@(20) into d5,
  0x40081738 loads %fp@(32) into d6), so they must be saved around `snap_note`.
- Cycles does NOT need the reclaimed-code-cave trick the Samples mod uses. Our
  build appends past the MAIN OS end and had ~9 KB spare.
