#!/usr/bin/env python3
"""Build Model-TG for the Elektron Model:Cycles (OS 1.13) from YOUR stock
firmware plus the sources in src/.

    python3 build.py --stock model-cycles_OS1.13.syx            # -> Model-TG.syx
    python3 build.py --assemble-only                            # sources only

Nothing of Elektron's is in this repository: the stock OS is read from the
.syx you give it, unpacked and repacked with elektron-firmware-tool
(https://github.com/mischa85/elektron-firmware-tool). See docs/BUILD.md.

Layout of the image:
  stock section 3 (ends 0x401aa140)
  + zeros   0x401aa140..0x401ab750   (NOTHING of ours below 0x401ab750)
  + ONE blob at 0x401ab750, linked from three objects in this order:
        src/model_tg.s      the Sampler, its modes, pages and effects
        src/phase1.s        boot clear, lookups, trampoline
        src/track_table.s   trampoline continuation
  + stock-area patches, each asserted against the stock bytes it replaces
  + the vendored tweaks in tweaks/, also asserted
"""
import struct, subprocess, sys, os, argparse, shutil, hashlib
BASE=0x40000400
STOCK_END=0x401aa140          # where stock Cycles OS 1.13 ends
# section 3 (MAIN OS) of the unmodified model-cycles_OS1.13.syx, decompressed
STOCK_SHA256="cc99d4f0175d34d1e91d046e6ec85a5e8ab58ab9edbb3c24406acd48cb99ee98"
REPO=os.path.dirname(os.path.abspath(__file__))
_ap=argparse.ArgumentParser(description="Build Model-TG from your own stock "
                            "Model:Cycles OS 1.13 firmware.")
_ap.add_argument("--stock", help="your unmodified model-cycles_OS1.13.syx")
_ap.add_argument("--out", default="Model-TG.syx",
                 help="the firmware to write (default: %(default)s)")
_ap.add_argument("--tool", default=os.environ.get("ELEKTRON_FIRMWARE_TOOL",
                 "elektron-firmware-tool"), help="path to elektron-firmware-tool")
_ap.add_argument("--no-tweaks", action="store_true",
                 help="leave out the vendored tweaks (tweaks/)")
_ap.add_argument("--modded-cycles", metavar="FILE",
                 help="also write Model-TG as a tweak file for the Modded-Cycles web "
                      "flasher (docs/PAYLOAD.md); it contains stock bytes, so it is "
                      "never committed or attached to a release")
_ap.add_argument("--flasher", metavar="FILE",
                 help="also write the patch file the Model-TG web flasher applies "
                      "(flasher/model-tg.json); it holds only Model-TG's own bytes "
                      "and is checked for runs of stock bytes (docs/FLASHER.md)")
_ap.add_argument("--check-flasher", metavar="FILE",
                 help="with --assemble-only: check that FILE's appended code is exactly "
                      "what src/ assembles to, and that it was made from committed source")
_ap.add_argument("--assemble-only", action="store_true",
                 help="assemble, link and self-check src/ only - no stock firmware needed")
args=_ap.parse_args()
if not args.assemble_only and not args.stock:
    _ap.error("--stock is required (or --assemble-only)")
if args.modded_cycles and os.path.abspath(args.modded_cycles).startswith(os.path.join(REPO,"flasher")+os.sep):
    _ap.error("--modded-cycles output holds stock bytes: never write it into flasher/ (it is published)")
if args.no_tweaks:
    os.environ["NO_TWEAKS"]="1"
src="model_tg.s"
proto=os.path.join(REPO,"src")
BUILD=os.path.join(REPO,"build"); os.makedirs(BUILD,exist_ok=True)
out=os.path.join(BUILD,"Model-TG.bin")
# the ColdFire binutils: m68k-elf-* or a distribution's m68k-linux-gnu-*
CROSS=os.environ.get("CROSS") or next((c for c in ("m68k-elf-","m68k-linux-gnu-")
                                       if shutil.which(c+"as")), "m68k-elf-")
elf=os.path.join(BUILD,"_b.elf"); binf=os.path.join(BUILD,"_b.bin")
STOCK_BIN=os.path.join(BUILD,"stock","section_3_MAIN_OS.bin")
if not args.assemble_only:
    # section 3 (the main OS) out of YOUR stock .syx
    subprocess.run([args.tool,"-i",args.stock,"-d","3","-o",os.path.join(BUILD,"stock")],
                   check=True,stdout=subprocess.DEVNULL)

# ---- ONE blob, linked from three objects ------------------------------------
# Phase 1 used to be assembled on its own at 0x401aa140, straight after stock.
# That address is inside 0x401a7750..0x401ab750, a 16 KiB buffer the filesystem
# copies to disk to blank every newly allocated chunk (0x40079462, 0x400794ce)
# and which it relies on being ZERO. With our code in it, new chunks got our
# code instead. And a "holepunch" patch had made the boot clear start AFTER our
# blob, on the false premise that the blob sat at the start of the cleared
# region - so 0x4019b590..(blob) went uncleared from samplerW to samplerEF.
# Now: sampler_voice first, so its layout and persistent state are exactly what
# they were; Phase 1 and the trampoline tail appended after it; the boot clear
# skips exactly [blob_start, reserved_end), both supplied at link time.
BLOB=0x401ab750   # the first cache block's start. Until samplerHN the blob began
                  # 752 B in, at 0x401aba40, only because an older, separate
                  # blob once ended there; nothing else uses that gap
ZERO_BUF=(0x401a7750,0x401ab750)
CACHE_BASE=0x401ab750
assert BLOB>=CACHE_BASE, "nothing of ours may live below the first cache block"
def _as(srcfile,tag):
    o=os.path.join(BUILD,f"_{tag}.o")
    subprocess.run([CROSS+"as","-march=cfv4e","-o",o,srcfile],cwd=proto,check=True)
    return o
_objs=[_as(src,"b"), _as("phase1.s","a"), _as("track_table.s","s")]
def _link(res_end):
    subprocess.run([CROSS+"ld",f"-Ttext=0x{BLOB:x}",
                    f"--defsym=blob_start=0x{BLOB:x}",f"--defsym=reserved_end=0x{res_end:x}",
                    "-o",elf,*_objs],check=True,stderr=subprocess.DEVNULL)
    subprocess.run([CROSS+"objcopy","-O","binary",elf,binf],check=True)
    return open(binf,'rb').read()
# reserved_end is only an operand, so the size cannot depend on it: link once
# to measure, once for real, and check that held.
_probe=_link(0)
RES_END=BLOB+((len(_probe)+15)&~15)
_real=_link(RES_END)
assert len(_real)==len(_probe), "blob size changed between the two link passes"
print(f"  one blob: {len(_real):,} B at 0x{BLOB:08x}, reserved_end 0x{RES_END:08x}")
# Every stack frame must be freed with the size it was allocated with. Scoping
# by label gives false positives (local labels like pf_ret: look like functions),
# so just require that each allocation size has a matching free size somewhere -
# enough to catch "allocate 48, free 40", which silently leaks the audio stack.
import re as _re
_txt=open(f"{proto}/{src}").read()
_neg={int(m) for m in _re.findall(r'lea\.l\s+%sp@\(-(\d+)\),%sp', _txt)}
_pos={int(m) for m in _re.findall(r'lea\.l\s+%sp@\((\d+)\),%sp', _txt)}
_bad=sorted(_neg - _pos)
if _bad:
    raise SystemExit(f"stack imbalance: allocated {_bad} with no matching free")
print(f"  stack frames balanced ({sorted(_neg)})")
# The fill loop and the filter must address the SAME window. The decimator is
# handed sampler_buf+0 and uses the first 32 bytes as overlap history, so both
# start at +32. Working from +0 silently mangles every block - it is the bug
# that made the filter sound like bit crushing - so the count is pinned here:
# a bare `sampler_buf,%a1` fails the build. Back to two now that the attack
# ramp has moved out to amp_hook, which works on the decimated output instead.
# The window is written at +32 by the stereo fill's return to the mid plane,
# gran_fill's return from its side pass, the stereo helpers sx_fx_r, sx_ms2lr
# and sx_fx_back, and pluck_st / wave_st putting their output back (the
# engines themselves - lofi/tape/vinyl_apply, gran_fill, pluck_fill, wave_fill
# - take it from fx_buf / gf_dst / pk_dst / wf_dst, which start at +32). Every
# reference in any register is counted, so none can slip past at +0.
_bufs=_re.findall(r'lea\.l\s+sampler_buf(\+32)?,%a[0-7]', _txt)
if _bufs.count('') or len(_bufs)!=9:
    raise SystemExit(f"sampler_buf window mismatch: {_bufs!r} (expected nine '+32')")
print(f"  sampler_buf: fill, filter, granular, pluck, wavetable, lo-fi, tape and vinyl all at +32")
# Everything that renders a voice must reach the amp stage through amp_hook, or
# it silently loses its attack. The six stock call sites are retargeted in the
# image; our own render has to say amp_hook in the source. It said 0x400a967a
# and the Sampler was the one machine with no attack at all.
_direct=_txt.count('jsr     0x400a967a')
if _direct!=1:
    raise SystemExit(f"{_direct} direct calls to the amp stage in the source; "
                     "only amp_hook itself may call it")
print("  amp stage reached only through amp_hook")
# key_hook's dispatch must END before the modifier's handler. Losing its rts
# made every unrelated key fall through into it and latch its own up/down
# state as "held", so any key+Preset toggled the sampler mode.
_disp=_txt[_txt.index('key_hook:'):_txt.index('kh_mod:')]
_code=[l.split('|')[0].strip() for l in _disp.split('\n')]
_code=[l for l in _code if l]
if _code[-1]!='rts':
    raise SystemExit(f"key_hook's dispatch falls through into kh_mod (last: {_code[-1]!r})")
print("  key_hook dispatch ends before kh_mod")
# dial_start/dial_end feed the slice window in sampler_render, which has no
# trackData pointer of its own. They must be published BEFORE the slice-mode
# skip in the window section, or slice mode never writes them and every slice
# collapses to one sample. Pin the order.
_pub=_txt.index('lea.l   dial_start,%a1')
_skip=_txt.index('beqw    sw_done               | slice mode owns its window')
if _pub > _skip:
    raise SystemExit("dial_start is published after the slice-mode skip; "
                     "slice windows will collapse to one sample")
print("  Start/End published before the slice-mode skip")

sym={}
for line in subprocess.run([CROSS+"nm",elf],capture_output=True,text=True).stdout.splitlines():
    p=line.split()
    if len(p)==3: sym[p[2]]=int(p[0],16)
blob=open(binf,'rb').read()
# Every 16-bit branch must land on a label. gas emits an unsized `bsr` to a far
# label as bsr.w and lets the displacement wrap silently (8-bit ones do error):
# samplerGI's `bsr gflt_coef` became a call 64 KiB backwards into a data buffer
# once the blob grew past 32 KiB between the two, and faulted at boot.
_nm=subprocess.run([CROSS+"nm",elf],capture_output=True,text=True,check=True).stdout
_labels={int(l.split()[0],16) for l in _nm.splitlines() if len(l.split())==3}
_dis=subprocess.run([CROSS+"objdump","-d",elf],capture_output=True,text=True,check=True).stdout
# Tables of .long data inside the code (objdump decodes them as instructions)
# are skipped by the label that holds them.
_DATA_LABELS={'st_fields','st_fields_end','st_reset','key_value_strings',
              'rs_items','rs_desc'}   # pointer tables (menu descriptors), not code
_wrapped=[]; _in=None
for _l in _dis.splitlines():
    _h=_re.match(r'^[0-9a-f]{8} <([^>]+)>:',_l)
    if _h: _in=_h.group(1); continue
    if _in in _DATA_LABELS: continue
    _m=_re.search(r'^\s*([0-9a-f]{8}):\s+[0-9a-f]{4} [0-9a-f]{4}\s*\t(bsrw|braw|b\w\ww)\s+([0-9a-f]{6,8})',_l)
    if _m and int(_m.group(3),16) not in _labels:
        _wrapped.append(_l.strip())
if _wrapped:
    raise SystemExit("16-bit branch to no label (a wrapped displacement?):\n  "+"\n  ".join(_wrapped))
print(f"  every 16-bit branch lands on a label")
# Code must sit at an even address: a jump to an odd one faults. samplerGY's
# mach_nbuf (19 bytes, no .balign after it) left gm_val_*/gm_rot_* odd, and
# the options menu threw an exception at its first row. So any label at an
# odd address must be a string: printable, NUL-terminated.
_BYTE_DATA={'qry_yes','qry_none','key_state'}   # .byte data, not code
_odd=[]
for _l in _nm.splitlines():
    _p=_l.split()
    if len(_p)!=3 or _p[1] not in 'tT' or _p[2] in _BYTE_DATA: continue
    _a=int(_p[0],16)
    if _a%2==0 or not (BLOB<=_a<BLOB+len(blob)): continue
    _bs=blob[_a-BLOB:_a-BLOB+96]; _z=_bs.find(b'\0')
    if _z<1 or not all(32<=_c<127 or _c==10 for _c in _bs[:_z]):
        _odd.append(f"{_p[0]} {_p[2]}")
if _odd:
    raise SystemExit("labels at odd addresses that are not strings (code must be even):\n  "+"\n  ".join(_odd))
print("  every odd label is a string")
# The BSS clear resumes at reserved_end with `moveml %d4-%d7,%a0@`, a longword
# multi-register store, so reserved_end must be at least 4-byte aligned - and
# the loop steps 16 bytes at a time, so 16 is the honest requirement. Builds
# that happened to land 2-mod-4 were the ones that threw exceptions.
if len(blob) % 16:
    blob += b'\x00' * (16 - len(blob) % 16)
if args.assemble_only:
    print(f"  assembled, linked and self-checked: {len(blob):,} B blob (no image built)")
    if args.check_flasher:
        # what the web flasher publishes appends zeros up to BLOB, then the blob,
        # then zeros: so CI can prove, with no stock firmware, that the code
        # served is the code in this tree
        import json as _cjson, base64 as _cb64
        _fl=_cjson.load(open(args.check_flasher))
        _tail=_cb64.b64decode(_fl["append"]["base64"])
        _o=BLOB-STOCK_END
        assert _fl["append"]["off"]==STOCK_END-BASE, "flasher patch appends at the wrong place"
        assert _fl["stock_sha256"]==STOCK_SHA256, "flasher patch is for another stock OS"
        assert _tail[:_o]==bytes(_o) and _tail[_o+len(blob):]==bytes(len(_tail)-_o-len(blob)), \
            "flasher patch: the bytes around the code are not zeros"
        assert _tail[_o:_o+len(blob)]==blob, (f"{args.check_flasher} ({_fl['version']}) is not "
            "this source: regenerate it with build.py --stock ... --flasher")
        assert not _fl["version"].endswith("-dirty"), \
            f"{args.check_flasher} was made from uncommitted changes ({_fl['version']})"
        print(f"  {args.check_flasher} ({_fl['version']}): its code is this source's")
    sys.exit(0)
_stock=bytearray(open(STOCK_BIN,'rb').read())
if hashlib.sha256(_stock).hexdigest()!=STOCK_SHA256:
    raise SystemExit("this is not the stock Model:Cycles OS 1.13 main OS (its sha256 is "
                     f"{hashlib.sha256(_stock).hexdigest()}) - use the unmodified "
                     "model-cycles_OS1.13.syx from elektron.se")
assert BASE+len(_stock)==STOCK_END, (hex(BASE+len(_stock)), "unexpected stock size")
d=_stock+bytearray(BLOB-STOCK_END)+blob
end=BASE+len(d)
assert end==RES_END, f"image ends 0x{end:08x} but the boot clear resumes at 0x{RES_END:08x}"

# ---- Phase 1 stock-area patches -----------------------------------------
# Derived from the base image, each asserted against the STOCK bytes it
# replaces. Purposes per MERGE_PLAN: boot hook redirect, the FUN_400a24ca
# render patches, the clamp-table max, the vtable render-fn redirect, the
# FUN_4001488a clamp bytes, the FUN_4001477e write-guard byte, and the two
# table-lookup redirects. The 05->06 / 06->07 / 18->1c bytes are the machine
# count and machine-list size going from 6 machines to 7.
# The boot hook, the trampoline, the table lookup, the name table and the lazy
# init all live in the linked blob now, so their targets come from the symbols
# rather than the old fixed 0x401aa1xx..0x401aa5xx addresses.
def _p(n): return '%08x' % sym[n]
for _n in ('sampler_name_table','sampler_lazy_init_trampoline'):
    assert sym[_n]>>24==0x40, (_n, hex(sym[_n]))   # only the low 3 bytes are patched
PHASE1=[
 (0x40000531,'baff8041f9','b9'+_p('boot_extra_hook')),
 (0x40014073,'56ff7048d7','f9'+_p('log_trampoline')),
 (0x400147a5,'05','06'), (0x400148ab,'05','06'), (0x400148b3,'05','06'),
 (0x4001bbd3,'18','1c'), (0x4001bbe5,'18','1c'), (0x4001bbf3,'18','1c'),
 (0x4004df76,'7205202f0004','4ef9'+_p('table_lookup_b_fixed')),
 (0x4005a79d,'05','06'),  # LFO dest: machine->group bound
 (0x400a25e1,'05','06'), (0x400a2615,'1177e4',_p('sampler_name_table')[2:]),
 (0x400a26e9,'06','07'),
 (0x400a7df5,'05','06'),
 (0x400a7e0f,'912f0e2f0341f94011861022704c00','714e714e714e714e714e714e714e71'),
 (0x400a7e1f,'91','71'), (0x4010e5e6,'05','06'),
 # Algorithm (0x29) is the per-track machine selector: long[1]=9, so it is
 # trackData+18 / sound object+38, the byte 0x40014042 reads. Stock hides it
 # from every parameter page (long[10]=32767) AND leaves its flags word at 0,
 # so the LFO destination list - which requires bit 0x200 - skipped it. Set
 # that bit so it can be modulated. The line above already widened its max
 # from 5 to 6, so the range covers the Sampler as well.
 (0x4010e5fc,'00000000','00000200'), (0x40117931,'0a24ca',_p('sampler_lazy_init_trampoline')[2:]),
]
for _a,_from,_to in PHASE1:
    _o=_a-BASE; _f=bytes.fromhex(_from); _t=bytes.fromhex(_to)
    assert bytes(d[_o:_o+len(_f)])==_f, (hex(_a), bytes(d[_o:_o+len(_f)]).hex(), _from)
    d[_o:_o+len(_t)]=_t
print(f"  Phase 1: {len(PHASE1)} stock-area patch sites applied and asserted")

# ---- third-party tweaks (drumkilla/elektron-model-tweaks, MIT) ----------
# Vendored under ../tweaks. They patch stock section 3 the same way we do, in
# 0xff-filled space at 0x40147f22..0x40148b82 - well clear of our blob and of
# every site we touch. Each write's `old` is asserted, so if one of our patches
# ever moves onto one of theirs the build fails instead of shipping a broken
# image. Set NO_TWEAKS=1 to leave them out.
if not os.environ.get('NO_TWEAKS'):
    import json as _json, glob as _glob
    _tdir=os.path.join(REPO,'tweaks','model-cycles_OS1.13')
    _dev=_json.load(open(os.path.join(_tdir,'device.json')))
    assert _dev['section']==3 and _dev['section_len']==len(_stock), (
        "tweaks target a different section/length", _dev['section_len'], len(_stock))
    _names=[]
    for _f in sorted(_glob.glob(os.path.join(_tdir,'0*.json'))):
        _t=_json.load(open(_f))
        for _w in _t['writes']:
            _o=_w['off']; _old=bytes.fromhex(_w['old']); _new=bytes.fromhex(_w['new'])
            assert len(_old)==len(_new), (_t['id'], 'write changes length')
            assert bytes(d[_o:_o+len(_old)])==_old, (
                _t['id'], hex(BASE+_o), bytes(d[_o:_o+len(_old)]).hex(), _w['old'])
            d[_o:_o+len(_new)]=_new
        _names.append(_t['id'])
    print(f"  tweaks applied: {', '.join(_names)}")

def jmp(addr,target,extra=b''):
    o=addr-BASE
    d[o:o+6+len(extra)]=b'\x4e\xf9'+struct.pack('>I',target)+extra
    print(f"  0x{addr:08x} -> jmp 0x{target:08x}")

jmp(0x400a7da8, sym['sampler_pre'],      b'\x4e\x71')
jmp(0x400a7e02, sym['sampler_dispatch'], b'\x4e\x71'*12)
jmp(0x4008171e, sym['pad_load_hook'])
# Finer Start/End: slot 0x14 of the track-handle vtable (0x400fd134) is the
# "current + delta" step of every knob turn. fine_hook rescales small deltas for
# Start/End on Sampler tracks and then runs the original. apply_names swaps the
# two records' display formatter between these two stock functions.
_o=0x400fd148-BASE
assert struct.unpack('>I',bytes(d[_o:_o+4]))[0]==0x4000c264, bytes(d[_o:_o+4]).hex()
d[_o:_o+4]=struct.pack('>I',sym['fine_hook'])
print(f"  track-handle vtable +0x14 -> fine_hook 0x{sym['fine_hook']:08x}")
assert bytes(d[0x400456c8-BASE:0x400456c8-BASE+4])==bytes.fromhex('202f0008'), 'integer formatter moved'
assert bytes(d[0x4004a440-BASE:0x4004a440-BASE+4])==bytes.fromhex('4feffff0'), 'decimal formatter moved'
# fine_draw is transcribed from Pitch's renderer and borrows its record's
# function-object words: check the renderer and the calls/strings it uses.
assert bytes(d[0x4004dcca-BASE:0x4004dcca-BASE+4])==bytes.fromhex('4e56ffc8'), 'Pitch renderer moved'
for _a,_s in ((0x4012771e,b'999'),(0x4012772d,b'.X'),(0x4012772e,b'X'),(0x4012a9ea,b'%d'),(0x4012b9e9,b'.%d')):
    assert bytes(d[_a-BASE:_a-BASE+len(_s)+1])==_s+b'\0', (hex(_a), _s)
assert bytes.fromhex('4879'+'40a727e0') in bytes(d[0x400de244-BASE:0x400e1584-BASE]), 'Pitch renderer record moved'
# Machine-change defaults, applied where the firmware commits the change.
# 0x4001413e is 0x40014072's closing notify (`moveal a2@,a0 / clrl sp@- /
# movel a2,sp@-`, then vtable[16]); mc_commit_hook replays those three and
# jumps on to 0x40014144, so the Sampler's defaults go out with it.
assert bytes(d[0x4001413e-BASE:0x4001413e-BASE+6])==bytes.fromhex("205242a72f0a"), \
    bytes(d[0x4001413e-BASE:0x4001413e-BASE+6]).hex()
jmp(0x4001413e, sym['mc_commit_hook'])
# Granular menu: the one call that hands encoder events to the view stack,
# `jsr 0x40006158` at 0x400081ce in the main loop's encoder case, goes through
# gm_enc_gate, which gives LEVEL/DATA to the granular menu while it is open.
assert bytes(d[0x400081ce-BASE:0x400081ce-BASE+6])==bytes.fromhex("4eb940006158"), \
    bytes(d[0x400081ce-BASE:0x400081ce-BASE+6]).hex()
d[0x400081ce-BASE+2:0x400081ce-BASE+6]=struct.pack('>I',sym['gm_enc_gate'])
# gran_menu_open copies the list view's vtable group from 0x40108c78 (offset,
# typeinfo, 17 slots) and replaces slot 2; gm_key_th falls back to that slot's
# stock thunk and closes through 0x40075ba6, as Return does.
_vt=[struct.unpack('>I',bytes(d[0x40108c78-BASE+4*i:0x40108c78-BASE+4*i+4]))[0] for i in range(19)]
assert _vt[0]==0xffffffc8 and _vt[1]==0x40108bd8 and _vt[4]==0x4007598e and _vt[12]==0x40075be2, [hex(x) for x in _vt]
assert struct.unpack('>I',bytes(d[0x40108bec+0x7c-BASE:0x40108bec+0x80-BASE]))[0]==0x40075ba6
print(f"  0x400081ce -> jsr gm_enc_gate 0x{sym['gm_enc_gate']:08x}")
# The machine page's snapshot restore, 0x4001416c: its only two references,
# both in 0x400a2712, go through restore_hook, which skips it for the Sampler.
for _a,_op in ((0x400a278e,'4bf9'), (0x400a2832,'4eb9')):
    _o=_a-BASE
    assert bytes(d[_o:_o+6])==bytes.fromhex(_op+'4001416c'), (hex(_a), bytes(d[_o:_o+6]).hex())
    d[_o+2:_o+6]=struct.pack('>I',sym['restore_hook'])
    print(f"  0x{_a:08x} -> 0x4001416c now via restore_hook 0x{sym['restore_hook']:08x}")
_refs=[i for i in range(0,len(_stock)-4,2) if bytes(d[i:i+4])==bytes.fromhex('4001416c')]
assert not _refs, f"0x4001416c still referenced at {[hex(BASE+i) for i in _refs]}"
# LFO destinations: paramIdFor's `5 >= group` bound, replaced by our gate.
# The six bytes are `moveq #5,%d1 / cmpl %d2,%d1 / bccs 0x4005a6dc`, reached
# only from the bnes at 0x4005a6ce, so nothing else falls through here.
assert bytes(d[0x4005a6a6-BASE:0x4005a6a6-BASE+6])==bytes.fromhex("7205b2826430"), \
    bytes(d[0x4005a6a6-BASE:0x4005a6a6-BASE+6]).hex()
jmp(0x4005a6a6, sym['sampler_lfo_gate'])
# ...and the Amp Decay branch of the same function, which indexes the 6x32
# array by machine with no bound check at all.
assert bytes(d[0x4005a6b6-BASE:0x4005a6b6-BASE+6])==bytes.fromhex("eb8a41f940a7"), \
    bytes(d[0x4005a6b6-BASE:0x4005a6b6-BASE+6]).hex()
jmp(0x4005a6b6, sym['sampler_amp_gate'])
# Attack persistence: wrap the sound record's two save paths and its loader.
# All three share the prologue `lea %sp@(-12),%sp ; moveml %a2-%a4,%sp@`, which
# each hook replays before jumping to the body 8 bytes in.
for _a,_sym in ((0x4005afa0,'snd_save2_hook'),   # format version 2
                (0x4005b054,'snd_save1_hook'),   # format version 1
                (0x4005aecc,'snd_load_hook')):
    assert bytes(d[_a-BASE:_a-BASE+8])==bytes.fromhex("4feffff448d71c00"), \
        (hex(_a), bytes(d[_a-BASE:_a-BASE+8]).hex())
    jmp(_a, sym[_sym])
# Attack ramp for EVERY machine: retarget the six call sites of 0x400a967a,
# the amp envelope stage. The function's own first two instructions total 8
# bytes, so a 6-byte jmp would split the second one; and from inside it there
# is no clean way to regain control after the envelope has been applied. The
# tail call at 0x400aa990 is a jmp and works the same way - amp_hook returns
# straight to that function's caller.
_AMP=[0x400aa460,0x400aa792,0x400aa990,0x400aad1e,0x400ab2f2,0x400ab7a4]
for _a in _AMP:
    _op=bytes(d[_a-BASE:_a-BASE+2])
    assert _op in (b'\x4e\xb9', b'\x4e\xf9'), (hex(_a), _op.hex())
    assert struct.unpack('>I',bytes(d[_a-BASE+2:_a-BASE+6]))[0]==0x400a967a, hex(_a)
    d[_a-BASE+2:_a-BASE+6]=struct.pack('>I',sym['amp_hook'])
print(f"  {len(_AMP)} amp-stage call sites -> amp_hook 0x{sym['amp_hook']:08x}")
# Attack: repurpose param id 0x0d, one of the unused "Error" placeholders
# (ids 0x00-0x05 and 0x0a-0x0d), so param_table keeps its stock address and
# size. group 7 = common, so it exists on every machine; long[1]=23 is the
# first parameter index no group claims (0..8 are the trig params, 9..22 the
# machine and common ones), i.e. trackData+46 / sound object+66.
_ATK=0x4010dce0+0x0d*56
assert bytes(d[_ATK-BASE:_ATK-BASE+8])==bytes.fromhex("ffffffffffffffff"), \
    "param id 0x0d is not the Error placeholder any more"
d[_ATK-BASE:_ATK-BASE+56]=struct.pack('>14I',
    7,            # group: common
    23,           # long[1]: parameter index -> trackData+46
    0, 32512, 0,  # min, max, default (0 = instant attack)
    0,
    0xffffffff,   # no page slot
    0xffffffff,   # not bound to a dial
    0,
    0x600,        # flags: 0x200 puts it in the LFO destination list
    35,           # sort position: after Decay (30), before Color (40)
    sym['str_attack'], 0x40129882, sym['str_atk'])
print(f"  param id 0x0d -> Attack (k=23, trackData+46)")
# Filter and Resonance for the stock machines (Preset + Sweep / Contour): two
# more placeholders, 0x0c and 0x0b, as common parameters at indices 24 and 25
# (trackData +48/+50), laid out exactly like Attack. Sorted after it.
for _id,_k,_dflt,_sort,_ln,_sn in ((0x0c,24,32512,36,'str_gfilter','str_gflt'),
                                   (0x0b,25,0,    37,'str_greso','str_gres')):
    _E=0x4010dce0+_id*56
    assert bytes(d[_E-BASE:_E-BASE+8])==bytes.fromhex("ffffffffffffffff"), \
        f"param id 0x{_id:02x} is not the Error placeholder any more"
    d[_E-BASE:_E-BASE+56]=struct.pack('>14I', 7, _k, 0, 32512, _dflt, 0,
        0xffffffff, 0xffffffff, 0, 0x600, _sort, sym[_ln], 0x40129882, sym[_sn])
    print(f"  param id 0x{_id:02x} -> k={_k}, trackData+{2*_k}")
# ...kept out of the Sampler's LFO destination list: paramIdFor's common-map
# lookup `lea 0x40a79394,%a0` at 0x4005a6d0 goes through sampler_com_gate,
# which replays it and the `movel %a0@(0,%a2:l:4),%d0 ; bras 0x4005a6fc` after.
assert bytes(d[0x4005a6d0-BASE:0x4005a6d0-BASE+12])==bytes.fromhex("41f940a793942030ac006020"), \
    bytes(d[0x4005a6d0-BASE:0x4005a6d0-BASE+12]).hex()
jmp(0x4005a6d0, sym['sampler_com_gate'])
# Start/End waveform: slot 0x90 of the parameter view's vtable, the value popup
# 0x4001d818, goes through wf_popup (stock for everything but Sampler Start/End).
assert struct.unpack('>I',bytes(d[0x401005bc-BASE:0x401005c0-BASE]))[0]==0x4001d818, \
    bytes(d[0x401005bc-BASE:0x401005c0-BASE]).hex()
d[0x401005bc-BASE:0x401005c0-BASE]=struct.pack('>I',sym['wf_popup'])
print(f"  param view popup 0x401005bc -> wf_popup 0x{sym['wf_popup']:08x}")
# Resampling, whole output: the audio block's last call, `jsr 0x400567ba` at
# 0x40059872 (it writes the final mix to the output ring), goes through rs_out.
assert bytes(d[0x40059872-BASE:0x40059878-BASE])==bytes.fromhex("4eb9400567ba"), \
    bytes(d[0x40059872-BASE:0x40059878-BASE]).hex()
d[0x40059874-BASE:0x40059878-BASE]=struct.pack('>I',sym['rs_out'])
print(f"  0x40059872 -> jsr rs_out 0x{sym['rs_out']:08x}")
# Stereo Sampler tracks at the mixer: the main mix 0x40056610 (its one caller
# runs it for bus L, then bus R) enters through sx_mix, which sets each stereo
# track's channel to L or R first; and the per-track gain `jsr 0x40056d9c` at
# 0x4005982a goes through sx_gain, which applies it to the side channels too.
assert bytes(d[0x40056610-BASE:0x40056618-BASE])==bytes.fromhex("4fefffd848d73cfc"), \
    bytes(d[0x40056610-BASE:0x40056618-BASE]).hex()
jmp(0x40056610, sym['sx_mix'], b'\x4e\x71')
# Audio load profile: the render interrupt's vector install (0x4005966a,
# `movel #0x40058c5e,%d0` before the store to 0x400002fc) installs isr_prof,
# which stamps a timer and jumps to 0x40058c5e.
assert bytes(d[0x4005966a-BASE:0x40059676-BASE])==bytes.fromhex("203c40058c5e23c0400002fc"), \
    bytes(d[0x4005966a-BASE:0x40059676-BASE]).hex()
d[0x4005966c-BASE:0x40059670-BASE]=struct.pack('>I',sym['isr_prof'])
print(f"  render vector -> isr_prof 0x{sym['isr_prof']:08x}")
assert bytes(d[0x4005982a-BASE:0x40059830-BASE])==bytes.fromhex("4eb940056d9c"), \
    bytes(d[0x4005982a-BASE:0x40059830-BASE]).hex()
d[0x4005982c-BASE:0x40059830-BASE]=struct.pack('>I',sym['sx_gain'])
print(f"  0x4005982a -> jsr sx_gain 0x{sym['sx_gain']:08x}")
# Quick mute queues: the pad toggle in QuickMuteMenuView (0x40023550) flips a
# pending bit instead; the LED painter's mute query (0x400233bc) shows the
# pending state; the latching tweak's FUNC close (its nops at 0x40148696) and
# the view's destructors (vtable 0x40100c3c slots 0 and 1) apply it. The tweak
# must be present: its close path is where the queue is applied.
if not os.environ.get('NO_TWEAKS'):
    assert bytes(d[0x40023550-BASE:0x40023556-BASE])==bytes.fromhex('4eb940013904'), 'mute pad toggle moved'
    d[0x40023552-BASE:0x40023556-BASE]=struct.pack('>I',sym['mq_toggle'])
    assert bytes(d[0x400233bc-BASE:0x400233c2-BASE])==bytes.fromhex('49f94001263c'), 'mute LED query moved'
    d[0x400233be-BASE:0x400233c2-BASE]=struct.pack('>I',sym['mq_muted'])
    assert bytes(d[0x40148696-BASE:0x4014869c-BASE])==bytes.fromhex('4e714e714e71'), 'latching-mute tweak close path not found'
    d[0x40148696-BASE:0x4014869c-BASE]=b'\x4e\xb9'+struct.pack('>I',sym['mq_apply'])
    for _o,_old,_sym in ((0x40100c3c,0x400d8f8c,'mq_dtor0'),(0x40100c40,0x400d9030,'mq_dtor1')):
        assert struct.unpack('>I',bytes(d[_o-BASE:_o-BASE+4]))[0]==_old, hex(_o)
        d[_o-BASE:_o-BASE+4]=struct.pack('>I',sym[_sym])
    print("  quick mute: queued pads, applied on close")
# Transfer identity (CYC / SMP): the identity reply builder in 0x40084ade. Its
# list copy (from `pea 0x22`) goes through id_hook, the product number
# (`moveq #27,%d1 ; lea %sp@(40),%sp`) through id_hook2, and its name `pea`
# points at id_namebuf. The config menu's constructor epilogue gets the row.
for _a,_old,_sym in ((0x40084b8e,'487800222d48','id_hook'),
                     (0x40084c14,'721b4fef0028','id_hook2'),
                     (0x40032aee,'4cef7c7c0018','cfg_hook')):   # Device Config
    assert bytes(d[_a-BASE:_a-BASE+6])==bytes.fromhex(_old), (hex(_a), bytes(d[_a-BASE:_a-BASE+6]).hex())
    jmp(_a, sym[_sym])
assert bytes(d[0x40084be0-BASE:0x40084be6-BASE])==bytes.fromhex('4879401285c9'), 'identity name pea moved'
# SMP: sample-family requests relabelled to their raw twins on the way in (the
# factory switch's type read) and the replies back on the way out (the header
# writer's type byte).
assert bytes(d[0x4009249a-BASE:0x400924a0-BASE])==bytes.fromhex('4eb9400949d8'), 'factory type read moved'
d[0x4009249c-BASE:0x400924a0-BASE]=struct.pack('>I',sym['rpc_type'])
assert bytes(d[0x40094c9a-BASE:0x40094ca2-BASE])==bytes.fromhex('71aa00084fef0020'), 'reply type write moved'
jmp(0x40094c9a, sym['rpc_ot'], b'\x4e\x71')
d[0x40084be2-BASE:0x40084be6-BASE]=struct.pack('>I',sym['id_namebuf'])
# the Samples list id_smp_list carries, checked against... the Cycles image's
# own list, which must still be what id_hook copies in CYC mode
assert bytes(d[0x40112d40-BASE:0x40112d62-BASE])==bytes.fromhex('0102030504505251141516242526273334353743444547535455565758595a5b5c5d'), 'Cycles type list moved'
print(f"  identity reply -> id_hook/id_hook2, name -> id_namebuf; config menu -> cfg_hook")
# Track+Preset chord: wrap the KeyEvent key-code accessor, the one place a
# chord is visible regardless of which view owns the buttons. 10-byte leaf;
# are orphaned but unreachable (nothing branches into an accessor).
assert bytes(d[0x4007240c-BASE:0x4007240c-BASE+10])==bytes.fromhex("206f00042028000c4e75"), \
    bytes(d[0x4007240c-BASE:0x4007240c-BASE+10]).hex()
jmp(0x4007240c, sym['key_hook'])
# Slide trigs: a step's slide mark (bit 12) goes when the stock resets the step
assert bytes(d[0x400169f0-BASE:0x400169f8-BASE])==bytes.fromhex("4feffff448d7040c"), \
    "step reset 0x400169f0 moved"
jmp(0x400169f0, sym['sld_reset'], b'\x4e\x71')
# ...and the grid's step lights: a slide trig double-blinks (sld_led)
_o=0x40021f56-BASE
assert bytes(d[_o:_o+22])==bytes.fromhex("2f034e944879404a8cb82f0d2f002f024e964fef0014"), \
    "step-light painter 0x40021f56 moved"
d[_o:_o+22]=b'\x4e\xb9'+struct.pack('>I',sym['sld_led'])+b'\x4e\x71'*8
print("  0x40021f56 -> jsr sld_led (step lights)")
# ...and the slide itself: both calls of the trig builder - the sequencer's per
# step, and 0x40055af4's (the first step on Play, edits while playing) - go
# through sld_seq, which pops the arguments as the replaced lea did
for _a,_old in ((0x400551a6,"4ebaf7264fef0018"),(0x40055bfa,"4ebaecd24fef0018")):
    _o=_a-BASE
    assert bytes(d[_o:_o+8])==bytes.fromhex(_old), f"trig-builder call 0x{_a:08x} moved"
    d[_o:_o+8]=b'\x4e\xb9'+struct.pack('>I',sym['sld_seq'])+b'\x4e\x71'
    print(f"  0x{_a:08x} -> jsr sld_seq (slide trigs)")
# Per-machine descriptor lookup -> our own descriptor for machine 6.
# PHASE1 already rewrote 0x4004df76 to `jmp table_lookup_b_fixed`; point that
# jmp at descr_b_hook instead, which answers machine 6 and otherwise falls
# through to table_lookup_b_fixed unchanged. All three callers of 0x4004df76
# search the returned descriptor's id array to pick a dial LED.
assert bytes(d[0x4004df76-BASE:0x4004df7c-BASE])==b'\x4e\xf9'+struct.pack('>I',sym['table_lookup_b_fixed']), \
    bytes(d[0x4004df76-BASE:0x4004df7c-BASE]).hex()
d[0x4004df78-BASE:0x4004df7c-BASE]=struct.pack('>I',sym['descr_b_hook'])
print(f"  0x4004df76 -> descr_b_hook 0x{sym['descr_b_hook']:08x}")
if 'preset_fail_hook' in sym:              # browser -> sample loading
    o=0x400a6732-BASE
    # 4-byte PC-relative jsr followed by `movel %d3,%sp@-`; the 6-byte absolute
    # jsr swallows that push, which preset_fail_hook replays on the way out.
    assert bytes(d[o:o+6])==bytes.fromhex("4ebaeac62f03"), bytes(d[o:o+6]).hex()
    d[o:o+6]=b'\x4e\xb9'+struct.pack('>I',sym['preset_fail_hook'])
    print(f"  0x400a6732 -> preset_fail_hook 0x{sym['preset_fail_hook']:08x}")
    o=0x400a6752-BASE
    assert bytes(d[o:o+2])==b'\x48\x79', bytes(d[o:o+2]).hex()   # pea
    d[o+2:o+6]=struct.pack('>I',sym['msg_buf'])
    print(f"  0x400a6752 -> msg_buf 0x{sym['msg_buf']:08x}")
if 'pad_hook' in sym:                      # retrig page: pads choose tracks
    o=0x4001d180-BASE
    # `linkw %fp,#-68; moveml %d2-%d7/%a2-%a5,%sp@` - the pad-event method's
    # first two instructions, replayed by pad_hook; jmp + nop in their place
    assert bytes(d[o:o+8])==bytes.fromhex("4e56ffbc48d73cfc"), bytes(d[o:o+8]).hex()
    d[o:o+8]=b'\x4e\xf9'+struct.pack('>I',sym['pad_hook'])+b'\x4e\x71'
    print(f"  0x4001d180 -> pad_hook 0x{sym['pad_hook']:08x}")
# Stock machines: three cheaper routines (kick_mix, kick_click, kick_sum in
# sampler_voice103.s), each entered by a jmp over the stock routine's first
# instructions - the mixer's dead first loop, the Kick's click, its final sum.
for _addr,_old,_name in ((0x400a98c4,"22115c8124730800",'kick_mix'),
                         (0x400a9daa,"4feffff448d70c04",'kick_click'),
                         (0x400a956c,"2f0a226f00084280",'kick_sum')):
    if _name not in sym: continue
    _o=_addr-BASE
    assert bytes(d[_o:_o+8])==bytes.fromhex(_old), (_name, bytes(d[_o:_o+8]).hex())
    jmp(_addr, sym[_name], b'\x4e\x71')
# The effects' setup 0x4005802e moves from the output stage to just before
# the voice loop (fx_early), so its DMA runs while the voices render.
if 'fx_early' in sym:
    _o=0x4005981e-BASE
    assert bytes(d[_o:_o+6])==bytes.fromhex("4eb9400a7d4a"), bytes(d[_o:_o+6]).hex()
    d[_o+2:_o+6]=struct.pack('>I',sym['fx_early'])
    _o=0x400567d6-BASE                     # movel a3,-(sp); jsr 0x4005802e; addql #4,sp
    assert bytes(d[_o:_o+10])==bytes.fromhex("2f0b4eb94005802e588f"), bytes(d[_o:_o+10]).hex()
    d[_o:_o+10]=bytes.fromhex("a93c00000020a1c0a3c0")   # movel #32,macsr; movclrl acc0/acc1,d0
    print("  0x4005981e jsr -> fx_early; 0x400567d6 -> macsr 0x20, acc0/acc1 clear")
    # the send effects, skipped while silent (fx_a / fx_b / fx_c)
    for _a,_t,_n in ((0x4005699c,0x40057488,'fx_a'), (0x40056a2c,0x400579c4,'fx_b')):
        _o=_a-BASE
        assert bytes(d[_o:_o+6])==b'\x4e\xb9'+struct.pack('>I',_t), (_n, bytes(d[_o:_o+6]).hex())
        d[_o+2:_o+6]=struct.pack('>I',sym[_n])
    _o=0x40056a36-BASE                     # jsr 0x40057942 ; jsr 0x400573fa
    assert bytes(d[_o:_o+12])==bytes.fromhex("4eb9400579424eb9400573fa"), bytes(d[_o:_o+12]).hex()
    d[_o:_o+12]=b'\x4e\xb9'+struct.pack('>I',sym['fx_c'])+b'\x4e\x71'*3
    print("  0x4005699c/0x40056a2c/0x40056a36 -> fx_a / fx_b / fx_c")
# The master FX's Noise riser and Vinyl go on the mixed bus: mfx_master
# in place of `pea 4; pea 0x8000b990; jsr 0x400565c6`, then `subql #8,sp`
# so the `addql #8,sp` that follows stays balanced.
if 'mfx_master' in sym:
    _o=0x40056b38-BASE
    assert bytes(d[_o:_o+14])==bytes.fromhex("487800044879 8000b9904ebafa82".replace(' ','')), bytes(d[_o:_o+14]).hex()
    d[_o:_o+14]=b'\x4e\xb9'+struct.pack('>I',sym['mfx_master'])+b'\x51\x8f'+b'\x4e\x71'*3
    print("  0x40056b38 -> jsr mfx_master; subql #8,sp")
if 'chord_osc' in sym:                     # the Chord's oscillator loop
    # `moveal #0x8000caa8,%a4` at 0x400a8906, the last of its setup: exactly
    # the jmp's 6 bytes; chord_osc replays it if it falls back to stock
    _o=0x400a8906-BASE
    assert bytes(d[_o:_o+6])==bytes.fromhex("287c8000caa8"), bytes(d[_o:_o+6]).hex()
    jmp(0x400a8906, sym['chord_osc'])
if 'pool_store_hook' in sym:               # sound lock: a sample as a preset
    o=0x400a6816-BASE
    # `moveal %a0@(80),%a0; jsr %a0@` - the Sound Pool store the lock path
    # calls (0x400a680a); a0 = the object at browser+628, as the hook expects
    assert bytes(d[o:o+6])==bytes.fromhex("206800504e90"), bytes(d[o:o+6]).hex()
    d[o:o+6]=b'\x4e\xb9'+struct.pack('>I',sym['pool_store_hook'])
    print(f"  0x400a6816 -> pool_store_hook 0x{sym['pool_store_hook']:08x}")
if 'getentry_hook' in sym:                 # browser probe, when present
    o=0x400a659e-BASE
    assert bytes(d[o:o+2])==b'\x4e\xb9', bytes(d[o:o+2]).hex()
    d[o+2:o+6]=struct.pack('>I',sym['getentry_hook'])
    print(f"  0x400a659e -> getentry_hook 0x{sym['getentry_hook']:08x}")
o=0x4001bbe8-BASE                      # pea <page_machine_list>
d[o:o+4]=struct.pack('>I',sym['page_machine_list'])
print(f"  0x4001bbe8 -> page_machine_list 0x{sym['page_machine_list']:08x}")
# ---- param_table: use the stock copy in place ----------------------------
# The stock table is at 0x4010dce0, inside the image and clear of the
# filesystem cache. An earlier generation copied it into the blob at
# 0x401afa40 and re-pointed ~30 base sites -- to change ONE byte. Point those
# sites back and patch the byte here, which reclaims 4,256 B of blob.
PT_OLD, PT_NEW = 0x401afa40, 0x4010dce0
assert sym['param_table']==PT_NEW, f"param_table is 0x{sym['param_table']:08x}, expected 0x{PT_NEW:08x}"
_pat=struct.pack('>I',PT_OLD)
_sites=[i for i in range(0,BLOB-BASE-4,2) if bytes(d[i:i+4])==_pat]
assert not _sites, f"unexpected relocated param_table refs from stock: {len(_sites)}"
print(f"  param_table: stock already points at 0x{PT_NEW:08x}; nothing to relocate")
# the single entry that differs from stock: entry 41, offset 14
# The base already carries this edit (an earlier generation patched the stock
# table in place AND made the copy), so accept either state and assert the
# result. That makes the relocation of ~30 sites pure redundancy.
_o=PT_NEW+2310-BASE
assert d[_o] in (0x05,0x06), f"param_table byte at +2310 is 0x{d[_o]:02x}, expected 0x05 or 0x06"
_was=d[_o]; d[_o]=0x06
print(f"  param_table[41]+14: 0x{_was:02x} -> 0x06 (in place, stock table)")
if 'tick_hook' in sym:                     # KeyboardView slot 2: input-driven
    o=0x400ff9cc-BASE                      # fallback if led_hook ever declines
    assert struct.unpack('>I',bytes(d[o:o+4]))[0]==0x4001a0d2, bytes(d[o:o+4]).hex()
    d[o:o+4]=struct.pack('>I',sym['tick_hook'])
    print(f"  KeyboardView slot2 0x400ff9cc -> tick_hook 0x{sym['tick_hook']:08x}")
if 'led_hook' in sym:                      # LedHandler empty virtual -> the clock
    _n=0
    for _s in (0x400ff9b8, 0x400ffa78, 0x40103070, 0x401031b4, 0x40107e18):
        o=_s-BASE
        assert struct.unpack('>I',bytes(d[o:o+4]))[0]==0x400d7648, (hex(_s), bytes(d[o:o+4]).hex())
        d[o:o+4]=struct.pack('>I',sym['led_hook']); _n+=1
    print(f"  {_n} LedHandler vtable slots -> led_hook 0x{sym['led_hook']:08x}")
if 'install_scale_menu_item' in sym:       # Scale Lock: the Scl/Key menu items
    o=0x4002f7d8-BASE
    assert bytes(d[o:o+6])==bytes.fromhex("4cef7c7c0018"), bytes(d[o:o+6]).hex()
    d[o:o+6]=b'\x4e\xf9'+struct.pack('>I',sym['install_scale_menu_item'])
    print(f"  menu epilogue 0x4002f7d8 -> install_scale_menu_item 0x{sym['install_scale_menu_item']:08x}")
if 'note_on_hook' in sym:                  # Scale Lock: note snapping
    for _a,_sym,_orig in ((0x4008173c,'note_on_hook','b083650001ce'),
                          (0x40081474,'note_off_hook','b08365000178')):
        o=_a-BASE
        assert bytes(d[o:o+6])==bytes.fromhex(_orig), (hex(_a), bytes(d[o:o+6]).hex())
        d[o:o+6]=b'\x4e\xf9'+struct.pack('>I',sym[_sym])
    print(f"  note on/off -> scale lock hooks 0x{sym['note_on_hook']:08x}/0x{sym['note_off_hook']:08x}")
o=0x4004df5c-BASE
assert bytes(d[o:o+6])==bytes.fromhex("7206202f0004"), bytes(d[o:o+6]).hex()
d[o:o+6]=b'\x4e\xf9'+struct.pack('>I',sym['descr_hook'])
print(f"  0x4004df5e -> descr_hook 0x{sym['descr_hook']:08x}")
o=0x400a7df5-BASE
assert d[o]==6, d[o]
# ---- the boot clear must cover everything below our code, like stock ------
# Stock (0x400004b2) zeroes 0x4019b590..0x423380b0. A former "holepunch" patch
# started it at reserved_end instead, leaving 0x4019b590..(blob) uncleared -
# including the filesystem's chunk-blanking buffer. Check the BUILT hook, not
# the source, since that is exactly where the mismatch hid last time.
_h=sym['boot_extra_hook']-BASE
_hook=bytes(d[_h:_h+64])
for _need,_what in ((b'\x41\xf9'+struct.pack('>I',0x4019b590),'starts at 0x4019b590'),
                    (b'\xb1\xfc'+struct.pack('>I',BLOB),      f'skips from 0x{BLOB:08x}'),
                    (b'\x20\x7c'+struct.pack('>I',RES_END),   f'resumes at 0x{RES_END:08x}'),
                    (b'\xb1\xfc'+struct.pack('>I',0x423380b0),'ends at 0x423380b0')):
    assert _need in _hook, f"built boot clear does not {_what}"
# ...and nothing of ours may sit in the chunk-blanking buffer
_zb=bytes(d[STOCK_END-BASE:ZERO_BUF[1]-BASE])
assert not any(_zb), "our bytes are inside the filesystem's zero buffer"
print(f"  boot clear 0x4019b590..0x423380b0, skipping only 0x{BLOB:08x}..0x{RES_END:08x}; "
      f"zero buffer free of our code")
# the pitch fix must survive
assert bytes(d[0x40058ee6-BASE:0x40058ee6-BASE+6])==bytes.fromhex("41f980001830")
assert bytes(d[0x40058a40-BASE:0x40058a40-BASE+6])==bytes.fromhex("0680800015ae")
print("  pitch fix (un-aliasing) intact")
# Verify every base->blob reference. The list is exhaustive: it came from a
# full binary diff of `unalias` against the diaglog62 base, so these five sites
# are all the places the base reaches into the blob. (A scan for blob-range
# values instead produces false positives - coincidental byte patterns inside
# the eSDHC driver and at odd offsets.)
CHECK=[(0x400a7daa,'sampler_pre'), (0x400a7e04,'sampler_dispatch'),
       (0x40081720,'pad_load_hook'), (0x4001bbe8,'page_machine_list'),
       (0x4004df5e,'descr_hook'), (0x4005a6a8,'sampler_lfo_gate'), (0x4004df78,'descr_b_hook'), (0x4005a6b8,'sampler_amp_gate')]
if 'getentry_hook' in sym: CHECK.append((0x400a65a0,'getentry_hook'))
if 'pool_store_hook' in sym: CHECK.append((0x400a6818,'pool_store_hook'))
if 'pad_hook' in sym: CHECK.append((0x4001d182,'pad_hook'))
for _a,_n in ((0x400a98c6,'kick_mix'),(0x400a9dac,'kick_click'),(0x400a956e,'kick_sum'),
              (0x400a8908,'chord_osc')):
    if _n in sym: CHECK.append((_a,_n))
if 'preset_fail_hook' in sym:
    CHECK += [(0x400a6734,'preset_fail_hook'), (0x400a6754,'msg_buf')]
for addr,name in CHECK:
    got=struct.unpack('>I',bytes(d[addr-BASE:addr-BASE+4]))[0]
    assert got==sym[name], f"{name}: site 0x{addr:08x} holds 0x{got:08x}, expected 0x{sym[name]:08x}"
print(f"  all {len(CHECK)} base->blob references verified against the ELF")
# ---- the render's step fraction lives in d1 for the whole fill loop -------
# Between sv_havestep and sv_filled, d1 is the Q0.32 fractional step added to
# the phase accumulator every sample. Writing anything else there pins every
# note to one pitch (the accumulator carries on almost every sample), which is
# silent corruption rather than a crash - so check it here.
_blk=_txt[_txt.index("sv_havestep:"):_txt.index("sv_filled:")]
_bad=[l.strip() for l in _blk.split("\n")
      if _re.search(r",\s*%d1\s*(\||$)", l) and not l.strip().startswith("|")
      and "lsll" not in l]
assert not _bad, f"d1 (the step fraction) is clobbered in the fill loop: {_bad}"
print("  render step fraction (d1) intact across the fill loop")

# ---- the six machine-page parameter ids must not be bound to a fixed dial -
# param_table entry layout: long[6] high half = slot, long[7] = 0xffffffff for
# a machine-page-only parameter. Resonance once used 0x1b (Reverb Send), whose
# long[7] is 0x9d because it drives the 8th dial - so moving one moved the
# other. Check every id we hand out, and that no two share a slot.
_ids=[int(m,16) for m in _re.findall(
    r"moveq\s+#0x([0-9a-fA-F]{1,2}),%d1\s*\n\s*movel\s+%d1,%a0@\(\d+\)", _txt)]
# Attack (0x0d) is written into the Decay position twice - once into our own
# variant descriptor, once into the copy dh_pass makes of a stock machine's -
# so dedupe before counting, or the slot check below sees it collide with
# itself. 7 distinct: the six page ids plus Attack.
_ids=list(dict.fromkeys(_ids))
assert len(_ids)==9, f"expected 9 distinct machine-page ids, found {len(_ids)}: {[hex(i) for i in _ids]}"
# Pitch (0x2a) and Amp Decay (0x18) are the conventional slots 1 and 2 that
# EVERY stock machine page uses, so sharing them with their dials is intended.
# The four machine-specific slots must not be dial-bound.
# Pitch and Amp Decay are the conventional slots 1 and 2 that every stock
# machine page uses, so sharing them with their dials is intended. 0x4b is
# Chord's Amp Decay duplicate; we use it rather than the common 0x18 so the
# LFO destination list, which sorts on long[10], places Decay 3rd as it does
# on every stock machine.
_CONVENTIONAL={0x2a,0x18,0x4b}
_slots={}
for _id in _ids:
    _o=PT_NEW+_id*56-BASE
    _e=struct.unpack('>14I',bytes(d[_o:_o+56]))
    assert _e[7]==0xffffffff or _id in _CONVENTIONAL, (
        f"param id 0x{_id:02x} has long[7]=0x{_e[7]:08x}, i.e. it is bound to a "
        f"fixed dial - changing that dial would move our parameter too")
    _slot=_e[6]>>16
    if _slot==0xffff:
        # no page slot: Attack, Filter, Resonance. What must not be shared then
        # is the storage index, long[1].
        _slot=('k',_e[1])
    assert _slot not in _slots, f"param ids 0x{_slots[_slot]:02x} and 0x{_id:02x} share slot {_slot}"
    _slots[_slot]=_id
print(f"  6 page ids {[hex(i) for i in _ids]} -> slots {sorted(str(s) for s in _slots)}; "
      f"{len(_ids)-len(_CONVENTIONAL & set(_ids))} machine-specific, none dial-bound, no slot shared")

# ---- reserve as many filesystem cache blocks as the blob needs -----------
# 0x401ab750 is a 16 x 16 KiB write-back cache of eMMC data (20-byte metadata
# per block at 0x401eb750, LRU doubly-linked). Our blob lives at 0x401ab750, so
# reading a directory used to memcpy 16 KiB straight over our code - the cause
# of the p401b0xxx exceptions.
#
# Usable blocks are exactly those the initialiser links into the LRU list, so
# starting that list past the blocks we occupy retires them, without touching
# the base address, the range checks or any block count. The by-index scan at
# 0x40079310 skips them too: it requires entry+8 (valid) to be non-zero, and
# nothing ever allocates them, so it stays 0 from the BSS clear.
CACHE_BASE, CACHE_ENTRY, CACHE_BLK = 0x401ab750, 0x401eb750, 16384
nres=(end-CACHE_BASE+CACHE_BLK-1)//CACHE_BLK     # blocks the blob occupies
# 5 since samplerID (the retrig page's master FX); samplerHN-IC fit in 4.
# 11 of 16 blocks stay the
# filesystem's; our own sample loading reads the eMMC directly, not through it.
assert 1<=nres<=6, f"blob spans {nres} cache blocks - too much of the cache"
# head = first entry we do NOT occupy; the prev-link loop starts one past it
for addr,old,newv,what in ((0x400792f2, 0x401eb750, CACHE_ENTRY+20*nres,      'LRU head'),
                           (0x400792bc, 0x401eb774, CACHE_ENTRY+20*(nres+1)+16,'prev-link loop start')):
    o=addr-BASE
    got=struct.unpack('>I',bytes(d[o:o+4]))[0]
    assert got==old, f"cache init at 0x{addr:08x} holds 0x{got:08x}, expected 0x{old:08x}"
    d[o:o+4]=struct.pack('>I',newv)
    print(f"  0x{addr:08x} -> 0x{newv:08x}  ({what}, entry {nres if addr==0x400792f2 else nres+1})")
limit=CACHE_BASE+nres*CACHE_BLK
assert end<=limit, f"blob ends 0x{end:08x}, past its reserved cache blocks (0x{limit:08x})"
print(f"  reserved {nres} of 16 cache blocks; blob ends 0x{end:08x}, limit 0x{limit:08x} "
      f"({limit-end:,} B spare)")

open(out,'wb').write(d)
assert end % 16 == 0, f"reserved_end 0x{end:08x} is not 16-byte aligned"
print(f"  blob {len(blob):,} B, image {len(d):,} B, reserved_end 0x{end:08x} (16-aligned)")

# ---- the MAIN OS hash, for the release notes ------------------------------
RESULT_SHA256=hashlib.sha256(bytes(d)).hexdigest()
print(f"  MAIN OS sha256 {RESULT_SHA256}")

# ---- Model-TG as a Modded-Cycles tweak (docs/PAYLOAD.md) -------------------
# The format of 18nelli18/Modded-Cycles' tweaks/: writes of {off, old, new}
# over the stock section - "old" being the stock bytes each replaces, which
# its applyWrites checks - and one "append" whose single hex part is
# everything after the stock section (the zero gap and our blob). Because of
# "old" the file holds stock bytes: it is generated from the user's own
# stock here, by whoever hosts it, and never committed or attached to a
# release. It is replayed the way that builder does before it is written,
# and must reproduce this image exactly.
if args.modded_cycles:
    import json as _pjson
    _st=bytes(_stock); _img=bytes(d)
    _writes=[]; _i=0
    while _i<len(_st):
        if _img[_i]!=_st[_i]:
            _j=_i
            while _j<len(_st) and _img[_j]!=_st[_j]: _j+=1
            _writes.append({"off":_i,"old":_st[_i:_j].hex(),"new":_img[_i:_j].hex()}); _i=_j
        else: _i+=1
    try:
        _ver=subprocess.run(["git","describe","--tags","--always","--dirty"],cwd=REPO,
                            capture_output=True,text=True,check=True).stdout.strip()
    except Exception:
        _ver="unknown"
    _at=f"0x{BASE+len(_st):08x}"
    _tail=_img[len(_st):]
    _tw={"id":"model-tg","order":30,
         "name":f"Model-TG {_ver}",
         "description":["Model-TG: the Sampler machine, resampling, retrig and master FX, and more.",
                        "Source, user guide and license: https://github.com/TinyGregAudio/Model-TG",
                        "MIT licensed (c) TinyGregAudio. Unofficial, not affiliated with Elektron."],
         "version":_ver,"source":"https://github.com/TinyGregAudio/Model-TG",
         "device":"Model:Cycles","os":"1.13","section":3,
         "result_sha256":RESULT_SHA256,
         "conflicts":["latching-mute","trig-preview","browser-scroll"],
         "writes":_writes,
         "append":{"at":_at,"dest":_at,"size":len(_tail),
                   "parts":[{"dest":_at,"hex":_tail.hex()}],"reloc":[]}}
    _chk=bytearray(_st)                        # replayed as Modded-Cycles builds
    for _w in _tw["writes"]:
        _o=_w["off"]; _old=bytes.fromhex(_w["old"]); _new=bytes.fromhex(_w["new"])
        assert bytes(_chk[_o:_o+len(_old)])==_old, f"old bytes at {_o} are not stock"
        _chk[_o:_o+len(_new)]=_new
    _ap2=bytearray(_tw["append"]["size"])
    for _p in _tw["append"]["parts"]:
        _b=bytes.fromhex(_p["hex"]); _q=int(_p["dest"],16)-int(_tw["append"]["dest"],16)
        _ap2[_q:_q+len(_b)]=_b
    _chk+=_ap2
    assert bytes(_chk)==_img, "the tweak does not reproduce the image"
    with open(args.modded_cycles,'w') as _f:
        _pjson.dump(_tw,_f,indent=1); _f.write("\n")
    print(f"  Modded-Cycles tweak {args.modded_cycles}: {len(_writes)} writes, "
          f"{len(_tail):,} B appended at {_at}; reproduces the image")

# ---- the web flasher's patch file (flasher/, docs/FLASHER.md) ---------------
# What the flasher applies to the user's own stock section 3: the changed runs
# (new bytes only - no "old"), and everything after the stock section, with
# the hashes that pin both ends. It is published, so it must hold no Elektron
# bytes: every run is searched for in the stock section, and a run of 128 or
# more stock bytes that is not a plain fill (at most two distinct 32-bit
# words: zeros, 0xff, masks) fails the build. What does match today is three
# small display routines cloned from stock on purpose (value_invoker,
# value_invoker2, gm_val; at most 93 bytes) - already public as source.
FLASHER_MAX_RUN=128
def _stock_runs(st, runs, w=8):
    idx=set(st[k:k+w] for k in range(len(st)-w+1))
    found=[]
    for off,data in runs:
        k=0
        while k+w<=len(data):
            if data[k:k+w] in idx:
                e=k+w
                while e<len(data) and data[k:e+1] in st: e+=1
                found.append((e-k,off+k,data[k:e])); k=e
            else: k+=1
    return found
def _is_fill(b):
    return len(set(b[i:i+4] for i in range(0,len(b)-3,4)))<=2
if args.flasher:
    import json as _fjson, base64 as _b64
    _st=bytes(_stock); _img=bytes(d)
    _runs=[]; _i=0
    while _i<len(_st):
        if _img[_i]!=_st[_i]:
            _j=_i
            while _j<len(_st) and _img[_j]!=_st[_j]: _j+=1
            _runs.append((_i,_img[_i:_j])); _i=_j
        else: _i+=1
    _tail=_img[len(_st):]
    _found=[f for f in _stock_runs(_st, _runs+[(len(_st),_tail)]) if not _is_fill(f[2])]
    _found.sort(reverse=True)
    _long=_found[0] if _found else (0,0,b"")
    assert _long[0]<FLASHER_MAX_RUN, (f"flasher patch holds {_long[0]} stock bytes in a row "
        f"at 0x{BASE+_long[1]:08x} - it must not carry Elektron firmware")
    try:
        _fver=subprocess.run(["git","describe","--tags","--always","--dirty"],cwd=REPO,
                             capture_output=True,text=True,check=True).stdout.strip()
    except Exception:
        _fver="unknown"
    _fl={"format":1,"name":"Model-TG","version":_fver,
         "source":"https://github.com/TinyGregAudio/Model-TG",
         "license":"MIT (c) TinyGregAudio; tweaks MIT (c) drumkilla",
         "device":"Model:Cycles","device_id":0x11,"os":"1.13","section":3,
         "stock_sha256":STOCK_SHA256,"stock_len":len(_st),
         "result_sha256":RESULT_SHA256,"result_len":len(_img),
         "writes":[{"off":o,"hex":b.hex()} for o,b in _runs],
         "append":{"off":len(_st),"base64":_b64.b64encode(_tail).decode()}}
    _chk=bytearray(_st)+bytearray(len(_tail))          # replayed as the flasher does
    for _w in _fl["writes"]:
        _b=bytes.fromhex(_w["hex"]); _chk[_w["off"]:_w["off"]+len(_b)]=_b
    _chk[len(_st):]=_b64.b64decode(_fl["append"]["base64"])
    assert hashlib.sha256(bytes(_chk)).hexdigest()==RESULT_SHA256, "the flasher patch does not reproduce the image"
    os.makedirs(os.path.dirname(os.path.abspath(args.flasher)),exist_ok=True)
    with open(args.flasher,'w') as _f:
        _fjson.dump(_fl,_f,indent=1); _f.write("\n")
    print(f"  flasher patch {args.flasher} ({_fver}): {len(_runs)} writes, {len(_tail):,} B "
          f"appended; longest stock run {_long[0]} B; reproduces the image")
    if _fver.endswith("-dirty"):
        print("  NOTE: built from uncommitted changes - not for publishing")

# ---- repack: the patched section 3 back into YOUR stock .syx ---------------
subprocess.run([args.tool,"-i",args.stock,"-c","3",out,"-o",args.out],
               check=True,stdout=subprocess.DEVNULL)
_h=hashlib.sha256(open(args.out,'rb').read()).hexdigest()
print(f"  wrote {args.out}  (sha256 {_h})")
