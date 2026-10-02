/* Model-TG web flasher: turn the user's own stock Model:Cycles OS 1.13 into
 * Model-TG, entirely on their computer. Applies the release's patch file
 * (model-tg.json, made by `build.py --flasher`) to the OS's MAIN OS section and
 * repacks it with elektron.js. Every step is checked: the stock section's
 * hash before, the patched section's hash after (the release's MAIN OS
 * sha256), and the rebuilt .syx is opened again and checked the same way
 * before it is offered.
 * MIT (c) TinyGregAudio.
 */
(function (root) {
  'use strict';
  var E = root.Elektron;

  function b64decode(s) {
    var tbl = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', map = {};
    for (var i = 0; i < 64; i++) map[tbl.charAt(i)] = i;
    s = s.replace(/[^A-Za-z0-9+/]/g, '');
    var out = new Uint8Array(Math.floor(s.length * 3 / 4)), o = 0, acc = 0, bits = 0;
    for (i = 0; i < s.length; i++) {
      acc = (acc << 6) | map[s.charAt(i)]; bits += 6;
      if (bits >= 8) { bits -= 8; out[o++] = (acc >> bits) & 255; }
    }
    return out.subarray(0, o);
  }
  function hexBytes(h) {
    var out = new Uint8Array(h.length >> 1);
    for (var i = 0; i < out.length; i++) out[i] = parseInt(h.substr(2 * i, 2), 16);
    return out;
  }

  // The stock OS's MAIN OS section, checked against the patch's stock hash.
  function stockSection(fw, patch) {
    if (fw.device !== patch.device_id)
      throw new Error('This is not a Model:Cycles OS file.');
    var sec = E.getSection(fw, patch.section), raw = sec && E.depackSection(fw, sec);
    if (!raw) throw new Error('The OS file has no readable MAIN OS section.');
    if (raw.length !== patch.stock_len || E.hex(E.sha256(raw)) !== patch.stock_sha256)
      throw new Error('This is not the unmodified Model:Cycles OS ' + patch.os +
                      '. Download it again from elektron.se and use that file as it is.');
    return raw;
  }

  // flash(syx Uint8Array, patch object, progress(fraction, label)) -> Uint8Array .syx
  function flash(syx, patch, progress) {
    progress = progress || function () {};
    if (patch.format !== 1) throw new Error('This flasher does not know this patch format.');
    progress(0, 'Reading the OS');
    var fw = E.parseSyx(syx);
    var stock = stockSection(fw, patch);
    progress(0.02, 'Patching');
    var img = new Uint8Array(patch.result_len);
    img.set(stock);
    for (var i = 0; i < patch.writes.length; i++) {
      var w = patch.writes[i];
      img.set(hexBytes(w.hex), w.off);
    }
    img.set(b64decode(patch.append.base64), patch.append.off);
    if (E.hex(E.sha256(img)) !== patch.result_sha256)
      throw new Error('The patched OS does not match this release (MAIN OS sha256).');
    var out = E.buildSyx(fw, patch.section, img, function (f) {
      progress(0.03 + 0.9 * f, 'Compressing');
    });
    progress(0.95, 'Checking the result');
    var back = E.parseSyx(out);
    var sec = E.getSection(back, patch.section), raw = sec && E.depackSection(back, sec);
    if (!back.key || !raw || E.hex(E.sha256(raw)) !== patch.result_sha256)
      throw new Error('The rebuilt OS failed its check. Nothing was saved.');
    progress(1, 'Done');
    return out;
  }

  root.ModelTG = { flash: flash };
})(typeof self !== 'undefined' ? self : typeof globalThis !== 'undefined' ? globalThis : this);
