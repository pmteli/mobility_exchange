// Recording-only overlay. Follows real browser pointer events, never intercepts input.
(() => {
  addEventListener('DOMContentLoaded', () => {
    const cursor = document.createElement('div');
    cursor.id = 'recording-cursor';
    cursor.setAttribute('aria-hidden', 'true');
    cursor.style = 'position:fixed;left:0;top:0;width:46px;height:46px;border:3px solid #f5b700;border-radius:50%;background:#ffdf5055;box-shadow:0 0 0 2px #ffffffcc;pointer-events:none;z-index:100001;transform:translate(-100px,-100px)';
    const arrow = document.createElement('span');
    arrow.textContent = '➤';
    arrow.style = 'position:absolute;left:15px;top:8px;color:#143858;font:bold 25px system-ui;transform:rotate(-35deg);text-shadow:1px 1px white';
    cursor.append(arrow);
    document.body.append(cursor);
    let position;
    try { position = JSON.parse(sessionStorage.getItem('recording-pointer')); } catch (_) {}
    function move(x,y) {
      cursor.style.transform = 'translate('+(x-23)+'px,'+(y-23)+'px)';
      sessionStorage.setItem('recording-pointer',JSON.stringify({x,y}));
    }
    if(position)move(position.x,position.y);
    addEventListener('pointermove', e => move(e.clientX,e.clientY), true);
    addEventListener('pointerdown', e => {
      move(e.clientX,e.clientY);
      const ripple=document.createElement('div');
      ripple.style='position:fixed;left:'+(e.clientX-23)+'px;top:'+(e.clientY-23)+'px;width:46px;height:46px;border:5px solid #ee6842;border-radius:50%;pointer-events:none;z-index:100002';
      document.body.append(ripple);
      ripple.animate([{transform:'scale(.5)',opacity:1},{transform:'scale(2)',opacity:0}],{duration:700,easing:'ease-out'});
      setTimeout(()=>ripple.remove(),700);
    }, true);
  });
})();
