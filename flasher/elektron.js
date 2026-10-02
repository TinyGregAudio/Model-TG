/* Elektron OS .syx (ELE3 container) in JavaScript: SysEx transport, section
 * codec, checksums and the HMAC trailer - what Model-TG's flasher needs to open
 * a stock Model:Cycles OS and repack it with a new MAIN OS section.
 *
 * A port of the ELE3 path of elektron-firmware-tool
 * (https://github.com/mischa85/elektron-firmware-tool), function for function,
 * so that its output is byte-identical to the tool's (tools/test_flasher.js
 * checks that against build.py). Contains no Elektron firmware.
 *
 * MIT License
 *
 * Copyright (c) 2026 Marcel Bierling
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * The JavaScript port is part of Model-TG, MIT (c) TinyGregAudio.
 */
(function (root) {
  'use strict';

  // ---- transport (format.h) ----
  var SYX_START = 0xF0, SYX_END = 0xF7, MASK7 = 0x7F;
  var SYX_PKT = 126, SYX_HDR = 9, SYX_ENC_PAY = 116, SYX_DEC_PER_PKT = 101;
  var SYX_CKSUM_OFF = 125, PK_DEV = 3, PK_CMD = 5, PK_BLOCK = 6, PK_MARKER_BASE = 7;
  var SYX_CKSUM_SPAN = SYX_CKSUM_OFF - PK_BLOCK;
  var CMD_DATA = 0x7E, CMD_MARKER = 0x7F, MARKER_START = 1, MARKER_END = 2;
  var SYX_PREAMBLE = 8;
  // ---- ELE3 container ----
  var ELE3_COUNT_OFF = 0x1C, ELE3_TABLE_OFF = 0x20, ELE3_ENTRY_SZ = 16, ELE3_MAX_SECTIONS = 64;
  // ---- codec ----
  var BIAS = 767, REUSE_GAMMA = 2, FAR = 3328, MIN_MATCH = 2, SECT_HDR = 8, LIT_BITS = 9;

  function be32(p, o) { return ((p[o] << 24) | (p[o + 1] << 16) | (p[o + 2] << 8) | p[o + 3]) >>> 0; }
  function put32(p, o, v) { p[o] = v >>> 24 & 255; p[o + 1] = v >>> 16 & 255; p[o + 2] = v >>> 8 & 255; p[o + 3] = v & 255; }

  // ================= SHA-256 / HMAC (integrity.c) =================
  var K = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]);

  // sha256(parts...) over one or more Uint8Arrays -> Uint8Array(32)
  function sha256() {
    var h = new Uint32Array([0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]);
    var w = new Uint32Array(64), buf = new Uint8Array(64), n = 0, total = 0;
    function blk(p, o) {
      for (var i = 0; i < 16; i++) w[i] = be32(p, o + 4 * i);
      for (i = 16; i < 64; i++) {
        var x = w[i - 15], y = w[i - 2];
        var s0 = ((x >>> 7 | x << 25) ^ (x >>> 18 | x << 14) ^ (x >>> 3));
        var s1 = ((y >>> 17 | y << 15) ^ (y >>> 19 | y << 13) ^ (y >>> 10));
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (i = 0; i < 64; i++) {
        var S1 = (e >>> 6 | e << 26) ^ (e >>> 11 | e << 21) ^ (e >>> 25 | e << 7);
        var ch = (e & f) ^ (~e & g);
        var t1 = (hh + S1 + ch + K[i] + w[i]) >>> 0;
        var S0 = (a >>> 2 | a << 30) ^ (a >>> 13 | a << 19) ^ (a >>> 22 | a << 10);
        var mj = (a & b) ^ (a & c) ^ (b & c);
        var t2 = (S0 + mj) >>> 0;
        hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    function upd(d) {
      var i = 0, len = d.length;
      total += len;
      if (n) {
        while (n < 64 && i < len) buf[n++] = d[i++];
        if (n === 64) { blk(buf, 0); n = 0; }
      }
      for (; i + 64 <= len; i += 64) blk(d, i);
      while (i < len) buf[n++] = d[i++];
    }
    for (var a = 0; a < arguments.length; a++) upd(arguments[a]);
    var bits = total * 8, pad = new Uint8Array(((n < 56) ? 56 : 120) - n + 8);
    pad[0] = 0x80;
    var hi = Math.floor(bits / 4294967296), lo = bits >>> 0, pl = pad.length;
    put32(pad, pl - 8, hi); put32(pad, pl - 4, lo);
    upd(pad);
    var out = new Uint8Array(32);
    for (var k = 0; k < 8; k++) put32(out, 4 * k, h[k]);
    return out;
  }

  function hmacSha256(key, data) {
    var k = new Uint8Array(64), ip = new Uint8Array(64), op = new Uint8Array(64);
    if (key.length > 64) k.set(sha256(key)); else k.set(key);
    for (var i = 0; i < 64; i++) { ip[i] = k[i] ^ 0x36; op[i] = k[i] ^ 0x5c; }
    return sha256(op, sha256(ip, data));
  }

  function hex(u8) {
    var s = '';
    for (var i = 0; i < u8.length; i++) s += (u8[i] < 16 ? '0' : '') + u8[i].toString(16);
    return s;
  }
  function eq(a, b) {
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  // Content checksum (preamble[4:8]): acc += (k+1) ^ BE32 word k.
  function contentChecksum(c, clen) {
    var acc = 0, nw = Math.floor(clen / 4);
    for (var k = 0; k < nw; k++) acc = (acc + (((k + 1) ^ be32(c, 4 * k)) >>> 0)) >>> 0;
    return acc;
  }
  // Per-packet checksum (byte 125).
  function blockChecksum(body, base) {
    var acc = 0;
    for (var i = 0; i < SYX_CKSUM_SPAN; i++) acc += body[PK_BLOCK + i] ^ (base + i);
    return (base + acc) & MASK7;
  }

  // Key derivation: anchor, printable string, NUL, 32-byte constant.
  var ANCHOR = [0xbe, 0xf9, 0xa3, 0xf7, 0xc6, 0x71, 0x78, 0xf2];
  function deriveKey(s, cnst) {
    var rev = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) rev[i] = s[s.length - 1 - i];
    var h = sha256(s), hr = sha256(rev), key = new Uint8Array(32);
    for (i = 0; i < 32; i++) key[i] = h[i] ^ hr[i] ^ cnst[i];
    return key;
  }
  function extractKey(fw, fwlen, msg, expect) {
    outer:
    for (var i = 0; i + 8 < fwlen; i++) {
      for (var a = 0; a < 8; a++) if (fw[i + a] !== ANCHOR[a]) continue outer;
      var s = i + 8, p = s;
      while (p < fwlen && fw[p] >= 0x20 && fw[p] < 0x7f && p - s < 64) p++;
      var slen = p - s;
      if (!slen || p >= fwlen || fw[p] !== 0 || p + 1 + 32 > fwlen) continue;
      var cand = deriveKey(fw.subarray(s, p), fw.subarray(p + 1, p + 33));
      if (eq(hmacSha256(cand, msg), expect)) return cand;
    }
    return null;
  }

  // ================= section codec (decompress.c / compress.c) =================
  // apDepack(src, out, allowTrunc): src = section (8-byte header + stream).
  // Returns the length written into out, or -1.
  function apDepack(src, out, allowTrunc) {
    var ip = SECT_HDR, iend = src.length, tag = 0, err = 0;
    var op = 0, oend = out.length, lastOff = 1;
    if (ip > iend) return -1;
    function read() { if (ip >= iend) { err = 1; return 0; } return src[ip++]; }
    function getbit() {
      tag = (tag << 1) >>> 0;
      if ((tag & 0xFF) === 0) { var by = read(); tag = ((by << 1) | 1) >>> 0; return (by >> 7) & 1; }
      return (tag >>> 8) & 1;
    }
    function getgamma() {
      var v = 1;
      for (;;) { v = ((v << 1) + getbit()) >>> 0; if (getbit()) break; if (err || v > 0x02000000) break; }
      return v;
    }
    for (;;) {
      if (err) { if (allowTrunc) break; return -1; }
      if (getbit()) {
        if (op >= oend) return -1;
        if (ip >= iend) { if (allowTrunc) break; return -1; }
        out[op++] = src[ip++];
        continue;
      }
      var g = getgamma(), off;
      if (g === REUSE_GAMMA) off = lastOff;
      else {
        off = (((g << 8) >>> 0) + read()) >>> 0;
        if (err) { if (allowTrunc) break; return -1; }
        if (off === BIAS) break;
        off = (off - BIAS) >>> 0; lastOff = off;
      }
      var ba = getbit(), bb = getbit(), sl = 2 * ba + bb, L;
      if (sl) L = sl; else L = (getgamma() + 2) >>> 0;
      if (err) { if (allowTrunc) break; return -1; }
      if (off > FAR) L += 1;
      var n = L + 1;
      if (off === 0 || op < off) return -1;
      if (op + n > oend) return -1;
      var cp = op - off;
      while (n--) out[op++] = out[cp++];
    }
    return (op === 0 && !allowTrunc) ? -1 : op;
  }

  function gammaCost(v) { var nb = 0; for (; v; v >>>= 1) nb++; return 2 * (nb - 1); }
  function matchCost(off, L, lastOff) {
    var b = 1 + (off === lastOff ? 2 : gammaCost((off + BIAS) >>> 8) + 8);
    var Lb = L - 1 - (off > FAR ? 1 : 0);
    b += (Lb <= 3) ? 2 : 2 + gammaCost(Lb - 2);
    return b;
  }

  var HSIZE = 1 << 17, MAX_CHAIN = 2048, MAX_MATCH = 2048, COST_INF = 0xFFFFFFFF;

  // apPack(data, progress) -> Uint8Array section (8-byte header + stream).
  // The cost-optimal parse of compress.c, so the output is the tool's exactly;
  // match_cost is inlined (an offset's cost, plus lenCost[length field]).
  var LEN_COST = new Uint8Array(MAX_MATCH + 2);
  for (var lb = 0; lb < LEN_COST.length; lb++) LEN_COST[lb] = (lb <= 3) ? 2 : 2 + gammaCost(lb - 2);
  function apPack(data, progress) {
    var len = data.length;
    if (len === 0) return new Uint8Array(SECT_HDR);
    var head = new Int32Array(HSIZE).fill(-1), prev = new Int32Array(len);
    var cost = new Uint32Array(len + 1).fill(COST_INF), lo = new Uint32Array(len + 1);
    var from = new Int32Array(len + 1), toff = new Uint32Array(len + 1), tlen = new Uint32Array(len + 1);
    var lenCost = LEN_COST;
    cost[0] = 0; lo[0] = 1; from[0] = -1;
    var step = Math.max(1, len >> 6);
    for (var i = 0; i < len; i++) {
      if (progress && i % step === 0) progress(i / len);
      var bi = cost[i];
      if (bi === COST_INF) continue;
      var loi = lo[i];
      var cap = len - i; if (cap > MAX_MATCH) cap = MAX_MATCH;
      var nc = bi + LIT_BITS, pos = i + 1, cl, far, base;
      if (nc < cost[pos]) { cost[pos] = nc; lo[pos] = loi; from[pos] = i; toff[pos] = 0; tlen[pos] = 0; }
      if (i + 1 < len) {
        if (i >= loi) {                                  // last-offset reuse
          var a = i - loi, rl = 0;
          while (rl < cap && data[a + rl] === data[i + rl]) rl++;
          far = (loi > FAR) ? 1 : 0;
          base = bi + 3;
          for (cl = MIN_MATCH + far; cl <= rl; cl++) {
            nc = base + lenCost[cl - 1 - far]; pos = i + cl;
            if (nc < cost[pos]) { cost[pos] = nc; lo[pos] = loi; from[pos] = i; toff[pos] = loi; tlen[pos] = cl; }
          }
        }
        var hh = (data[i] << 8) ^ data[i + 1];
        var j = head[hh], chain = MAX_CHAIN, pm = 1;
        while (j >= 0 && chain-- !== 0) {
          // only a match longer than pm counts, so one that differs at pm is
          // out without a scan (pm < cap here: a match of cap ends the search)
          if (data[j + pm] !== data[i + pm]) { j = prev[j]; continue; }
          var l = 0;
          while (l < cap && data[j + l] === data[i + l]) l++;
          if (l > pm) {
            var off = i - j;
            far = (off > FAR) ? 1 : 0;
            base = bi + 1 + (off === loi ? 2 : 2 * (31 - Math.clz32((off + BIAS) >>> 8)) + 8);
            var start = pm + 1; if (start < MIN_MATCH + far) start = MIN_MATCH + far;
            for (cl = start; cl <= l; cl++) {
              nc = base + lenCost[cl - 1 - far]; pos = i + cl;
              if (nc < cost[pos]) { cost[pos] = nc; lo[pos] = off; from[pos] = i; toff[pos] = off; tlen[pos] = cl; }
            }
            pm = l;
            if (l >= cap) break;
          }
          j = prev[j];
        }
        prev[i] = head[hh]; head[hh] = i;
      }
    }
    // the path, from the end back
    var npos = 0, p;
    for (p = len; p > 0; p = from[p]) npos++;
    var path = new Uint32Array(npos || 1), k = npos;
    for (p = len; p > 0; p = from[p]) path[--k] = p;

    var out = new Uint8Array(len + (len >> 1) + 256), n = SECT_HDR, tagpos = -1, tagbits = 0;
    function putBit(bit) {
      if (tagbits === 0) { tagpos = n; out[n++] = 0; tagbits = 8; }
      if (bit) out[tagpos] |= (1 << (tagbits - 1));
      tagbits--;
    }
    function putByte(v) { out[n++] = v & 255; }
    function putGamma(v) {
      var nb = 0; for (var t = v; t; t >>>= 1) nb++;
      for (var b = nb - 2; b >= 0; b--) { putBit((v >>> b) & 1); putBit(b === 0 ? 1 : 0); }
    }
    var lastOff = 1;
    for (k = 0; k < npos; k++) {
      var at = path[k], src = from[at];
      if (tlen[at] === 0) { putBit(1); putByte(data[src]); continue; }
      var mo = toff[at], ml = tlen[at];
      putBit(0);
      if (mo === lastOff) putGamma(REUSE_GAMMA);
      else { var raw = mo + BIAS; putGamma(raw >>> 8); putByte(raw & 0xFF); lastOff = mo; }
      var lb = ml - 1 - ((mo > FAR) ? 1 : 0);
      if (lb <= 3) { putBit(lb >> 1); putBit(lb & 1); }
      else { putBit(0); putBit(0); putGamma(lb - 2); }
    }
    putBit(0); putGamma(0x1000002); putByte(0xFF);     // end of stream
    var stream = n - SECT_HDR, sum = 0;
    for (k = SECT_HDR; k < n; k++) sum = (sum + out[k]) >>> 0;
    put32(out, 0, stream); put32(out, 4, sum);
    if (progress) progress(1);
    return out.slice(0, n);
  }

  // ================= .syx in =================
  // parseSyx(Uint8Array) -> { device, base, info, preamble, container, declaredSize,
  //                            sections[{id, offset, compLen, dest}], key }
  function parseSyx(buf) {
    var fsz = buf.length, i = 0, dev = 0;
    var dec = new Uint8Array(fsz), dpos = 0, base = 0, info = null, haveBase = false;
    var pkOk = 0, pkBad = 0;
    while (i < fsz) {
      if (buf[i] !== SYX_START) { i++; continue; }
      var j = i + 1; while (j < fsz && buf[j] !== SYX_END) j++;
      if (j >= fsz) break;
      var m = buf.subarray(i + 1, j), mlen = j - (i + 1);
      if (mlen > PK_DEV && !dev) dev = m[PK_DEV];
      if (mlen === SYX_PKT && m[PK_CMD] === CMD_DATA) {
        var p = m.subarray(SYX_HDR, SYX_HDR + SYX_ENC_PAY);
        for (var k = 0; k < SYX_ENC_PAY; k += 8) {
          var ms = p[k], nd = Math.min(SYX_ENC_PAY - k - 1, 7);
          for (var q = 0; q < nd; q++) dec[dpos++] = p[k + 1 + q] | (((ms >> (6 - q)) & 1) ? 0x80 : 0);
        }
        if (haveBase) { if (blockChecksum(m, base) === m[SYX_CKSUM_OFF]) pkOk++; else pkBad++; }
      } else {
        if (mlen > PK_MARKER_BASE) { base = m[PK_MARKER_BASE]; haveBase = true; }
        if (!info && mlen >= PK_MARKER_BASE + 7 && m[PK_CMD] === CMD_MARKER)
          info = m.slice(PK_MARKER_BASE, PK_MARKER_BASE + 7);
      }
      i = j + 1;
    }
    if (!dpos) throw new Error('This is not an Elektron OS file (.syx).');
    if (pkBad) throw new Error(pkBad + ' damaged packet(s) in the file: download the OS again.');
    var e = 0;
    for (; e + 4 <= dpos; e++)
      if (dec[e] === 0x45 && dec[e + 1] === 0x4C && dec[e + 2] === 0x45 && dec[e + 3] === 0x33) break;
    if (e + 4 > dpos || e < SYX_PREAMBLE) throw new Error('Not an OS file of the kind this flasher reads (ELE3).');
    var c = dec.subarray(e, dpos), clen = dpos - e;
    var declared = be32(dec, 0), cksum = be32(dec, 4);
    if (declared > clen || contentChecksum(c, declared) !== cksum)
      throw new Error('The file fails its own checksum: download the OS again.');
    var cnt = be32(c, ELE3_COUNT_OFF);
    if (cnt > ELE3_MAX_SECTIONS) throw new Error('Bad section table.');
    var sections = [];
    for (var s = 0; s < cnt; s++) {
      var o = ELE3_TABLE_OFF + s * ELE3_ENTRY_SZ;
      sections.push({ id: be32(c, o), offset: be32(c, o + 4), compLen: be32(c, o + 8), dest: be32(c, o + 12) });
    }
    var fw = { device: dev, base: base, info: info, container: c, declaredSize: declared,
               sections: sections, key: null };
    fw.key = findKey(fw);
    return fw;
  }

  function sectionBytes(fw, sec) {
    var avail = fw.container.length - sec.offset;
    var cl = (sec.compLen && sec.compLen <= avail) ? sec.compLen : avail;
    return fw.container.subarray(sec.offset, sec.offset + cl);
  }
  var TMP_CAP = 16 << 20;
  // the decompressed section, or null if it is not compressed
  function depackSection(fw, sec) {
    var tmp = new Uint8Array(TMP_CAP);
    var dn = apDepack(sectionBytes(fw, sec), tmp, true);
    return (dn === -1 || dn === 0) ? null : tmp.slice(0, dn);
  }

  function findKey(fw) {
    var c = fw.container, csize = fw.declaredSize;
    if (csize < 36 || csize > c.length) return null;
    var msg = c.subarray(0, csize - 32), expect = c.subarray(csize - 32, csize);
    for (var s = 0; s < fw.sections.length; s++) {
      var sec = fw.sections[s];
      if (sec.offset + SECT_HDR > c.length) continue;
      var d = depackSection(fw, sec);
      if (!d) continue;
      var key = extractKey(d, d.length, msg, expect);
      if (key) return key;
    }
    return null;
  }

  function getSection(fw, id) {
    for (var s = 0; s < fw.sections.length; s++) if (fw.sections[s].id === id) return fw.sections[s];
    return null;
  }

  // ================= .syx out =================
  // buildSyx(fw, id, raw, progress): fw's .syx with section id replaced by raw
  // (decompressed) bytes, every checksum and the HMAC trailer recomputed.
  function buildSyx(fw, id, raw, progress) {
    if (!fw.key) throw new Error('No container key found in this OS: cannot rebuild it.');
    var c = fw.container, cnt = fw.sections.length, order = [], firstOff = c.length;
    for (var s = 0; s < cnt; s++) { order.push(s); if (fw.sections[s].offset < firstOff) firstOff = fw.sections[s].offset; }
    order.sort(function (a, b) { return fw.sections[a].offset - fw.sections[b].offset; });
    var nc = new Uint8Array(c.length * 2 + (4 << 20));
    nc.set(c.subarray(0, firstOff));
    var pos = firstOff;
    for (var k = 0; k < cnt; k++) {
      var si = order[k], sec = fw.sections[si], sdata;
      pos = (pos + 15) & ~15;
      if (sec.id === id && depackSection(fw, sec)) sdata = apPack(raw, progress);
      else if (sec.id === id) sdata = raw;
      else sdata = c.subarray(sec.offset, sec.offset + sec.compLen);
      nc.set(sdata, pos);
      var e = ELE3_TABLE_OFF + si * ELE3_ENTRY_SZ;
      put32(nc, e + 4, pos); put32(nc, e + 8, sdata.length);
      pos += sdata.length;
    }
    // trailer: [pad][4 zero bytes][HMAC-SHA256], the HMAC 16-byte aligned
    var hmacOff = (pos + 4 + 15) & ~15;
    nc.fill(0, pos, hmacOff);
    nc.set(hmacSha256(fw.key, nc.subarray(0, hmacOff)), hmacOff);
    var clen = hmacOff + 32;
    var preamble = new Uint8Array(SYX_PREAMBLE);
    put32(preamble, 0, clen); put32(preamble, 4, contentChecksum(nc, clen));
    return syxEncode(nc.subarray(0, clen), fw.device, preamble, fw.base, fw.info);
  }

  function encode8in7(inp, o, out) {
    var n = 0, i = 0, len = inp.length;
    while (i < len) {
      var nd = Math.min(len - i, 7), ms = 0;
      for (var q = 0; q < nd; q++) if (inp[i + q] & 0x80) ms |= 1 << (6 - q);
      out[o + n++] = ms;
      for (q = 0; q < nd; q++) out[o + n++] = inp[i + q] & MASK7;
      i += 7;
    }
    return n;
  }

  function syxEncode(container, dev, preamble, base, info) {
    var total = SYX_PREAMBLE + container.length;
    var npkt = Math.floor(total / SYX_DEC_PER_PKT) + 1, padded = npkt * SYX_DEC_PER_PKT;
    var stream = new Uint8Array(padded);
    stream.set(preamble); stream.set(container, SYX_PREAMBLE);
    var out = new Uint8Array((npkt + 2) * (SYX_PKT + 2) + 256), o = 0;
    var startBlock = info ? ((info[1] << 7) | info[2]) : 1, startSeq = info ? info[3] : 0x72;
    var dflt = [0x10, 0x00, 0x01, 0x72, 0x01, 0x06, 0x6b];
    function marker(kind) {
      out[o++] = SYX_START;
      out.set([0x00, 0x20, 0x3C, dev, 0x00, CMD_MARKER, kind], o); o += 7;
      var inf = info ? Array.prototype.slice.call(info) : dflt.slice();
      inf[0] = base; inf[4] = (npkt >> 14) & MASK7; inf[5] = (npkt >> 7) & MASK7; inf[6] = npkt & MASK7;
      out.set(inf, o); o += 7;
      out[o++] = SYX_END;
    }
    marker(MARKER_START);
    var body = new Uint8Array(SYX_PKT);
    body.set([0x00, 0x20, 0x3C, dev, 0x00, CMD_DATA]);
    for (var k = 0; k < npkt; k++) {
      var cum = startSeq + k, block = startBlock + (cum >> 7);
      body[6] = (block >> 7) & MASK7; body[7] = block & MASK7; body[8] = cum & MASK7;
      encode8in7(stream.subarray(k * SYX_DEC_PER_PKT, (k + 1) * SYX_DEC_PER_PKT), SYX_HDR, body);
      body[SYX_CKSUM_OFF] = blockChecksum(body, base);
      out[o++] = SYX_START; out.set(body, o); o += SYX_PKT; out[o++] = SYX_END;
    }
    marker(MARKER_END);
    return out.slice(0, o);
  }

  root.Elektron = {
    parseSyx: parseSyx, getSection: getSection, depackSection: depackSection,
    buildSyx: buildSyx, apPack: apPack, apDepack: apDepack,
    sha256: sha256, hex: hex, eq: eq
  };
})(typeof self !== 'undefined' ? self : typeof globalThis !== 'undefined' ? globalThis : this);
