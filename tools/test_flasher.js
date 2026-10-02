// Checks the web flasher (flasher/) against build.py: the .syx it makes from
// your stock OS must be byte-identical to build.py's.
//   python3 build.py --stock STOCK.syx --flasher flasher/model-tg.json
//   node tools/test_flasher.js STOCK.syx [build/Model-TG.syx]
'use strict';
var fs = require('fs'), path = require('path');
var here = path.join(__dirname, '..', 'flasher');
require(path.join(here, 'elektron.js'));
require(path.join(here, 'patch.js'));

var stock = process.argv[2], ref = process.argv[3] || path.join(__dirname, '..', 'build', 'Model-TG.syx');
if (!stock) { console.error('usage: node tools/test_flasher.js STOCK.syx [build/Model-TG.syx]'); process.exit(2); }
var patch = JSON.parse(fs.readFileSync(path.join(here, 'model-tg.json'), 'utf8'));
var t0 = Date.now(), last = -1;
var out = globalThis.ModelTG.flash(new Uint8Array(fs.readFileSync(stock)), patch, function (f, label) {
  var pc = Math.floor(f * 10);
  if (pc !== last) { last = pc; process.stdout.write(label + ' ' + Math.round(f * 100) + '%\n'); }
});
console.log('flasher: ' + out.length + ' B in ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s');
var want = new Uint8Array(fs.readFileSync(ref));
if (out.length === want.length && globalThis.Elektron.eq(out, want)) {
  console.log('identical to ' + ref);
} else {
  var i = 0; while (i < out.length && i < want.length && out[i] === want[i]) i++;
  console.log('DIFFERS from ' + ref + ' (sizes ' + out.length + ' / ' + want.length + ', first difference at ' + i + ')');
  process.exit(1);
}
