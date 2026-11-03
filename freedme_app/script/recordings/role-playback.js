// Review-player role notices: pause the recording for three seconds at each transition.
(() => {
  const video = document.getElementById('player');
  const shade = document.createElement('div');
  shade.id = 'role-notice';
  shade.hidden = true;
  shade.setAttribute('role', 'dialog');
  shade.setAttribute('aria-modal', 'true');
  shade.setAttribute('aria-labelledby', 'role-notice-title');
  shade.innerHTML = '<div class="role-notice-card"><span class="role-notice-icon" aria-hidden="true">↪</span><h2 id="role-notice-title"></h2><p>The demo will continue in a few seconds.</p></div>';
  const style = document.createElement('style');
  style.textContent = '#role-notice[hidden]{display:none}#role-notice{position:fixed;inset:0;z-index:10000;background:#102c4f99;display:grid;place-items:center;padding:24px;backdrop-filter:blur(3px)}.role-notice-card{max-width:560px;width:100%;background:#fff;border:2px solid #afcdec;border-radius:20px;padding:36px;text-align:center;box-shadow:0 20px 80px #102c4f55}.role-notice-card h2{font:700 clamp(24px,4vw,32px)/1.3 system-ui;color:#143858;margin:16px 0}.role-notice-card p{color:#506880;margin:0}.role-notice-icon{display:inline-grid;place-items:center;width:64px;height:64px;border-radius:50%;background:#e0edff;color:#215aa1;font:40px system-ui}';
  document.head.append(style);
  document.body.append(shade);
  let shown = new Set(), timer, priorTime = 0, busy = false;
  function reset() {
    clearTimeout(timer); shade.hidden = true; shown.clear(); priorTime = 0; busy = false;
  }
  video.addEventListener('loadstart', reset);
  video.addEventListener('seeking', () => {
    if (video.currentTime < priorTime - 0.5) {
      shown.clear();
      clearTimeout(timer); shade.hidden = true; busy = false;
    }
    priorTime = video.currentTime;
  });
  function check() {
    const now = video.currentTime;
    if (busy || video.paused || video.seeking) return;
    const slug = video.getAttribute('src').split('/').pop().replace(/\.mp4(?:\?.*)?$/, '');
    const cues = (window.FreeDMERoleCues || {})[slug] || [];
    const cue = cues.find((c, i) => !shown.has(i) && now >= c.time && now < c.time + 1.5);
    priorTime = now;
    if (!cue) return;
    shown.add(cues.indexOf(cue));
    busy = true;
    video.pause();
    shade.querySelector('h2').textContent = 'Now signing in as ' + cue.role;
    shade.hidden = false;
    timer = setTimeout(() => {
      shade.hidden = true; busy = false;
      video.play().catch(() => {});
    }, 3000);
  }
  video.addEventListener('timeupdate', check);
  video.addEventListener('play', check);
})();
