/* Runs the flasher off the page's thread, so the page stays responsive while
 * the OS is compressed. MIT (c) TinyGregAudio. */
importScripts('elektron.js', 'patch.js');
self.onmessage = function (e) {
  try {
    var out = self.ModelTG.flash(new Uint8Array(e.data.syx), e.data.patch, function (f, label) {
      self.postMessage({ progress: f, label: label });
    });
    self.postMessage({ done: out.buffer }, [out.buffer]);
  } catch (err) {
    self.postMessage({ error: err.message || String(err) });
  }
};
