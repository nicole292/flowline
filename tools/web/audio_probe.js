// Test-only: counts Web Audio activity and measures the real output level.
window.__audio = { contexts: 0, states: [], bufStarts: 0, workletModules: 0, errors: [], toDest: 0, peak: 0 };
(function () {
  const AC = window.AudioContext;
  window.AudioContext = function (...a) {
    const ctx = new AC(...a);
    window.__audio.contexts++;
    window.__audio.ctx = ctx;
    ctx.addEventListener("statechange", () => window.__audio.states.push(ctx.state));
    return ctx;
  };
  window.AudioContext.prototype = AC.prototype;
  const s = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) { window.__audio.bufStarts++; return s.apply(this, a); };
  const conn = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (target, ...rest) {
    const r = conn.call(this, target, ...rest);
    if (target instanceof AudioDestinationNode) {
      window.__audio.toDest++;
      if (!window.__an) {
        window.__an = this.context.createAnalyser();
        window.__an.fftSize = 2048;
        const buf = new Float32Array(2048);
        setInterval(() => {
          window.__an.getFloatTimeDomainData(buf);
          let m = 0;
          for (const v of buf) m = Math.max(m, Math.abs(v));
          window.__audio.peak = Math.max(window.__audio.peak, m);
        }, 50);
      }
      conn.call(this, window.__an);
    }
    return r;
  };
})();
