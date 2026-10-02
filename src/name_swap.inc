
| entry offset, our name/cat/short, then stock ones to restore
| Rotated with the descriptor so page order matches slot order:
|   0x2e Kick Color   slot 0x10 -> Sample Start
|   0x3e Perc Shape   slot 0x11 -> Sample End
|   0x49 Chord Sweep  slot 0x12 -> Filter
|   0x4a Chord Contour slot 0x13 -> Resonance
name_swap:
    .long 2576, str_start, str_cat, str_startsh, 0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_end,   str_cat, str_endsh,   0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_flt,   str_cat, str_fltsh,   0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_res,   str_cat, str_ressh,   0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| The same four ids, labelled for granular mode (apply_names picks the set)
gran_swap:
    .long 2576, str_gpos,  str_gcat, str_gpossh,  0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_gsize, str_gcat, str_gsizesh, 0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_gdens, str_gcat, str_gdenssh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_gspr,  str_gcat, str_gsprsh,  0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| ...and for stretch mode: Speed replaces Position
strch_swap:
    .long 2576, str_gspd,  str_gscat, str_gspdsh,  0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_gsize, str_gscat, str_gsizesh, 0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_gdens, str_gscat, str_gdenssh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_gspr,  str_gscat, str_gsprsh,  0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| ...and for pluck mode
pluck_swap:
    .long 2576, str_ppos,  str_pcat, str_ppossh,  0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_plen,  str_pcat, str_plensh,  0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_ptone, str_pcat, str_ptonesh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_pfb,   str_pcat, str_pfbsh,   0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| ...and for wavetable mode
wave_swap:
    .long 2576, str_wpos,  str_wcat, str_wpossh,  0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_wsize, str_wcat, str_wsizesh, 0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_wsmth, str_wcat, str_wsmthsh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_wdet,  str_wcat, str_wdetsh,  0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| ...and for lo-fi mode: Start and End as ever, Filter and Res are Rate/Crush
lofi_swap:
    .long 2576, str_start, str_lcat, str_startsh, 0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_end,   str_lcat, str_endsh,   0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_lrate, str_lcat, str_lratesh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_lcrsh, str_lcat, str_lcrshsh, 0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
| ...and for One shot's Tape and Vinyl: Start and End, then Tone and Wear
tv_swap:
    .long 2576, str_start, str_tvcat, str_startsh, 0x4012999c, 0x4012996f, 0x401299a7
    .long 3472, str_end,   str_tvcat, str_endsh,   0x40129a4d, 0x4012996f, 0x401299b7
    .long 4088, str_tvtone, str_tvcat, str_tvtonesh, 0x40129ab6, 0x4012996f, 0x401299c7
    .long 4144, str_tvwear, str_tvcat, str_tvwearsh, 0x40129ac2, 0x4012996f, 0x401299d9
    .long -1,0,0,0,0,0,0
