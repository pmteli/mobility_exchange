// Presentation behavior only. No prototype localStorage, authentication or API mutations.
(() => {
  const preview = document.body.dataset.viewPreview === 'true';
  const dialog = document.getElementById('dialog');
  const modal = document.getElementById('modal');
  let opener, equipmentTitle;
  const sampleTitles = {1:'Folding walker',2:'Adjustable walking cane',3:'Manual wheelchair',4:'Shower chair with back',5:'Bedside commode',6:'Adjustable crutches',7:'Walker awaiting review'};
  function message(text) { const box = document.getElementById('toast'); box.textContent = text; box.hidden = false; box.classList.add('is-visible'); setTimeout(() => box.classList.remove('is-visible'), 5000); }
  function show(name) { const template = document.getElementById(name); if (!template) return; opener = document.activeElement; modal.replaceChildren(template.content.cloneNode(true));
    if (equipmentTitle && ['request_dialog','identity_dialog','question_dialog'].includes(name)) {
      const walker = document.createTreeWalker(modal, NodeFilter.SHOW_TEXT);
      while(walker.nextNode()) walker.currentNode.textContent = walker.currentNode.textContent.replaceAll('Adjustable walking cane', equipmentTitle);
    }
    dialog.showModal(); }
  function close() { dialog.close(); opener?.focus(); }
  function tabs(tab) {
    const list = tab.closest('[role=tablist]');
    list.querySelectorAll('[role=tab]').forEach(other => { const selected = other === tab; other.setAttribute('aria-selected', selected); other.tabIndex = selected ? 0 : -1; document.getElementById(other.getAttribute('aria-controls')).hidden = !selected; });
    tab.focus();
  }
  function photo(gallery, index) {
    const buttons = [...gallery.querySelectorAll('.gallery-thumb')]; if (!buttons.length) return;
    index = (index + buttons.length) % buttons.length;
    const thumb = buttons[index].querySelector('img'); const image = gallery.querySelector('.detail-image,.gallery-main');
    image.src = thumb.src; image.alt = buttons[index].getAttribute('aria-label');
    gallery.dataset.view = index;
    buttons.forEach((b, n) => b.setAttribute('aria-pressed', n === index));
    const status = gallery.querySelector('.rotator-status'); if (status) status.textContent = `${index + 1} / ${buttons.length} · ${buttons[index].textContent.trim()}`;
  }
  const toggle = document.querySelector('.mobile-menu-toggle'); const header = toggle.closest('header');
  const closeMenu = () => { toggle.setAttribute('aria-expanded','false'); header.classList.remove('mobile-menu-open'); };
  toggle.addEventListener('click', () => { const open = toggle.getAttribute('aria-expanded') !== 'true'; toggle.setAttribute('aria-expanded', String(open)); header.classList.toggle('mobile-menu-open', open); });
  document.addEventListener('click', ev => {
    if (!header.contains(ev.target) || ev.target.closest('header nav a')) closeMenu();
    const button = ev.target.closest('[data-action]'); if (!button) return;
    ev.preventDefault(); const {action, id} = button.dataset;
    const routes = {browse: '/equipment', donate: preview ? '/design-preview/donate' : '/donor/dashboard', detail: '/design-preview/item?item=' + encodeURIComponent(id), edit:'/design-preview/edit', 'cancel-edit':'/design-preview/donor'};
    if (routes[action]) { location.assign(routes[action]); return; }
    if (action === 'close') { close(); return; }
    if (action.endsWith('-tab')) { tabs(button); return; }
    if (action === 'share-drafts') { show('share_dialog'); return; }
    if (action === 'photo' || action === 'detailphoto') { const gallery = button.closest('[data-gallery],.detail-gallery'); photo(gallery, Number(action === 'photo' ? id.split(':')[1] : id)); return; }
    if (action === 'rotate') { const gallery = button.closest('.detail-gallery'); photo(gallery, Number(gallery.dataset.view || 0) + Number(id)); return; }
    const dialogs = {request:'request_dialog', 'begin-evidence':'identity_dialog', 'ask-question':'question_dialog', 'answer-question':'answer_dialog', offer:'approval_dialog', review:'review_dialog'};
    if (dialogs[action] && preview) { if (action !== 'begin-evidence') equipmentTitle=sampleTitles[id]; show(dialogs[action]); return; }
    if (action === 'share') { navigator.clipboard?.writeText(location.href).then(() => message('Link copied.'), () => message('Copy the URL from your browser to share this page.')); return; }
    if (action === 'category') { document.querySelectorAll('.category-row .chip').forEach(chip => chip.classList.toggle('active',chip===button)); const cats=['Walkers','Canes','Shower chairs','Commodes','Crutches','Manual wheelchairs']; document.querySelectorAll('[data-gallery]').forEach(card => { const number=Number(card.querySelector('.gallery-main').src.match(/\/(\d)\.svg/)?.[1]); card.hidden=id!=='All equipment'&&cats[number]!==id; }); return; }
    message('View preview only. This action is not connected to a backend service.');
  });
  document.addEventListener('keydown', ev => {
    if (ev.key==='Escape') closeMenu();
    const tab=ev.target.closest('[role=tab]');
    if(tab && ['ArrowLeft','ArrowRight','Home','End'].includes(ev.key)){ev.preventDefault();const all=[...tab.closest('[role=tablist]').querySelectorAll('[role=tab]')];let n=all.indexOf(tab);n=ev.key==='Home'?0:ev.key==='End'?all.length-1:(n+(ev.key==='ArrowRight'?1:-1)+all.length)%all.length;tabs(all[n]);}
    const gallery=ev.target.closest('.swipe-area')?.closest('.detail-gallery');if(gallery&&['ArrowLeft','ArrowRight'].includes(ev.key)){ev.preventDefault();photo(gallery,Number(gallery.dataset.view||0)+(ev.key==='ArrowRight'?1:-1));}
  });
  let touch;
  document.addEventListener('pointerdown',ev=>{const area=ev.target.closest('.swipe-area');if(area)touch={x:ev.clientX,y:ev.clientY,area};});
  document.addEventListener('pointerup',ev=>{if(!touch)return;const dx=ev.clientX-touch.x,dy=ev.clientY-touch.y;const gallery=touch.area.closest('.detail-gallery');if(Math.abs(dx)>45&&Math.abs(dx)>Math.abs(dy))photo(gallery,Number(gallery.dataset.view||0)+(dx<0?1:-1));touch=null;});
  document.addEventListener('pointercancel',()=>{touch=null;});
  document.addEventListener('change',ev=>{if(ev.target.matches('[data-loan-toggle]')){const field=ev.target.form.querySelector('[data-loan-field]'),input=field.querySelector('input');field.hidden=ev.target.value!=='loan';input.disabled=field.hidden;input.required=!field.hidden;}if(ev.target.matches('#donate-form :is(select,md-outlined-select)[name=kind]')){const field=document.getElementById('loan-until-field'),input=field.querySelector('input');field.hidden=ev.target.value!=='loan';input.disabled=field.hidden;input.required=!field.hidden;}});
  document.addEventListener('submit',ev=>{if(preview||ev.target.closest('dialog')){ev.preventDefault();message('Preview only. Your entries have not been saved or sent.');}});
  dialog.addEventListener('close',()=>opener?.focus());
})();

// Each selected image is checked privately before listing submission.
(() => {
 const input = document.querySelector('[data-equipment-upload]'); if (!input) return;
 const previews = document.querySelector('[data-upload-previews]');
 const error = document.getElementById('photo-upload-error');
 const photoErrors = document.querySelector('[data-photo-errors]');
 const endpoint = input.closest('[data-screening-url]').dataset.screeningUrl;
 let files = [...input.files], queue = Promise.resolve();
 const checks = new WeakMap();
 const syncFiles = () => { const data = new DataTransfer(); files.forEach(file => data.items.add(file)); input.files = data.files; };
 const valid = file => ['image/jpeg','image/png'].includes(file.type) && file.size > 0 && file.size <= 5*1024*1024;
 const check = file => {
  checks.set(file, {state:'checking', message:'Checking image…'});
  queue = queue.then(async () => {
   if (!files.includes(file)) return;
   const body = new FormData(); body.append('photo',file);
   const controller = new AbortController(); const timer = setTimeout(()=>controller.abort(),35000);
   try {
    const response = await fetch(endpoint,{method:'POST',credentials:'same-origin',headers:{'X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content,'Accept':'application/json'},body,signal:controller.signal});
    const result = await response.json();
    checks.set(file, ['accepted','needs_review','rejected','unavailable'].includes(result.state) ? result : {state:'unavailable',message:'Unable to check image. Please retry.'});
   } catch (_) { checks.set(file,{state:'unavailable',message:'Image check failed. Check your connection or sign in again, then retry.'}); }
   finally { clearTimeout(timer); render(); }
  });
 };
 const render = () => {
  previews.replaceChildren(); photoErrors.replaceChildren(); syncFiles();
  const kept = [...document.querySelectorAll('.existing-photo input[type=checkbox]')].filter(c => !c.checked).length;
  const invalid = files.some(f => !valid(f));
  const blocked = files.some(f=>!['accepted','needs_review'].includes(checks.get(f)?.state));
  const message = invalid ? 'Choose JPEG or PNG photos up to 5 MB each.' : files.length + kept > 5 ? 'Keep at most five photos. Remove an existing or selected photo.' : blocked ? 'Finish image checks or remove flagged photos before submitting.' : '';
  input.setCustomValidity(message); error.textContent = message;
  files.forEach((file, index) => {
   const box = document.createElement('div'); box.className = 'selected-photo';
   if (valid(file)) {
    const img = document.createElement('img'); img.alt = `Selected photo ${index+1}`;
    const reader = new FileReader(); reader.addEventListener('load', () => { img.src = reader.result; }); reader.readAsDataURL(file); box.append(img);
   }
   const label = document.createElement('span'); label.textContent = `Image ${kept + index + 1}`; box.append(label);
   const result = checks.get(file);
   const failed = ['rejected','unavailable'].includes(result?.state) || !valid(file);
   if (['accepted','rejected'].includes(result?.state)) {
    const accepted = result.state === 'accepted';
    const marker = document.createElement('span'); marker.className = accepted ? 'photo-accepted-marker' : 'photo-rejected-marker';
    marker.setAttribute('role','img'); marker.setAttribute('aria-label', accepted ? 'Accepted image' : 'Rejected image');
    marker.textContent = accepted ? '✓' : '✕'; box.append(marker);
   }
   const status = document.createElement('span'); status.className = 'photo-screening-status'; status.setAttribute('role','status');
   if (['accepted','rejected'].includes(result?.state)) status.classList.add(`photo-status-${result.state}`);
   status.textContent = result?.state === 'accepted' ? 'ACCEPTED' : result?.state === 'rejected' ? 'REJECTED' : failed ? 'Check failed' : result?.message || 'Waiting for check'; box.append(status);
   if (failed) {
    const detail = document.createElement('p'); detail.className = 'error-text';
    detail.textContent = `Image ${kept + index + 1}: ${result?.message || 'Choose a JPEG or PNG photo up to 5 MB.'}`;
    photoErrors.append(detail);
   }
   if (result?.state==='unavailable' || (!result && valid(file))) {
    const retry = document.createElement('button'); retry.type='button'; retry.textContent='Retry check';
    retry.addEventListener('click',()=>{check(file);render();}); box.append(retry);
   }
   const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = 'Remove'; remove.setAttribute('aria-label', `Remove selected photo ${index+1}`);
   remove.addEventListener('click', () => { files.splice(index, 1); render(); });
   box.append(remove); previews.append(box);
  });
 };
 input.addEventListener('change', () => {
  const added=[];
  for (const file of input.files) {
   if (!files.some(existing => existing.name === file.name && existing.size === file.size && existing.lastModified === file.lastModified)) {files.push(file);added.push(file);}
  }
  if (files.length <=5) added.filter(valid).forEach(check);
  render();
 });
 input.addEventListener('cancel', syncFiles);
 document.querySelectorAll('.existing-photo input[type=checkbox]').forEach(c=>c.addEventListener('change',render));
})();

// Keep required-field guidance consistent in full-page forms and inserted dialogs.
(() => {
  function refreshRequiredFields() {
    const targets = new Set();
    document.querySelectorAll('form').forEach(form => {
      const controls = [...form.querySelectorAll('input:not([type=hidden]):not([type=submit]), select, md-outlined-select, textarea')];
      if (!controls.length) return; // Action-only forms such as Sign Out.
      if (!form.querySelector(':scope > .required-fields-note')) {
        const note = document.createElement('p');
        note.className = 'required-fields-note';
        note.textContent = 'Fields marked with * are mandatory';
        form.prepend(note);
      }
      controls.forEach(control => {
        if (control.disabled || control.closest('[hidden]')) return;
        if (control.required || control.getAttribute('aria-required') === 'true') {
          [...(control.labels || [])].forEach(label => targets.add(label));
        }
      });
      form.querySelectorAll('[data-required-group] > legend').forEach(legend => targets.add(legend));
    });
    document.querySelectorAll('.required-field-star').forEach(star => {
      if (!targets.has(star.parentElement)) star.remove();
    });
    targets.forEach(label => {
      if (!label.querySelector(':scope > .required-field-star')) {
        const star = document.createElement('span');
        star.className = 'required-field-star';
        star.textContent = ' *';
        star.setAttribute('aria-hidden', 'true');
        const nested = label.querySelector('input:not([type=checkbox]):not([type=radio]), textarea, select, md-outlined-select');
        if (nested && nested.parentElement === label) label.insertBefore(star, nested);
        else label.append(star);
      }
    });
  }
  refreshRequiredFields();
  new MutationObserver(refreshRequiredFields).observe(document.body, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['required', 'disabled', 'hidden', 'aria-required']
  });
})();

// Approximate-location combobox: local suggestions, no geolocation or external calls.
(() => {
  function setupLocations() {
    document.querySelectorAll('input[list="east-bay-locations"]').forEach(input => {
      const source = document.getElementById(input.getAttribute('list'));
      if (!source) return;
      const options = Array.from(source.options, option => ({value: option.value, county: option.label}));
      input.removeAttribute('list');
      const wrapper = document.createElement('div');
      wrapper.className = 'location-combobox';
      input.before(wrapper); wrapper.append(input);
      const menu = document.createElement('div');
      menu.id = `${input.id || input.name}-suggestions`;
      menu.className = 'location-suggestions'; menu.role = 'listbox'; menu.hidden = true;
      wrapper.append(menu);
      input.setAttribute('role', 'combobox'); input.setAttribute('aria-autocomplete', 'list');
      input.setAttribute('aria-controls', menu.id); input.setAttribute('aria-expanded', 'false');
      let active = -1, matches = [];
      const close = () => { menu.hidden = true; input.setAttribute('aria-expanded','false'); input.removeAttribute('aria-activedescendant'); active = -1; };
      const choose = index => { input.value = matches[index].value; close(); input.dispatchEvent(new Event('change', {bubbles:true})); };
      function show() {
        const terms = input.value.toLowerCase().trim().split(/\s+/).filter(Boolean);
        matches = options.filter(option => terms.every(term => `${option.value} ${option.county}`.toLowerCase().includes(term)));
        menu.replaceChildren(); active = -1; input.removeAttribute('aria-activedescendant');
        matches.forEach((option,index) => {
          const row = document.createElement('div'); row.role = 'option'; row.id = `${menu.id}-${index}`;
          row.setAttribute('aria-selected','false');
          const title = document.createElement('span'); title.textContent = option.value;
          const county = document.createElement('small'); county.textContent = option.county;
          row.append(title,county);
          row.addEventListener('mousedown', event => event.preventDefault());
          row.addEventListener('click', () => choose(index)); menu.append(row);
        });
        if (!matches.length) { const empty = document.createElement('div'); empty.className = 'location-empty'; empty.textContent = 'No matching town or ZIP code. Check your spelling or enter your town name.'; menu.append(empty); }
        menu.hidden = false; input.setAttribute('aria-expanded','true');
      }
      input.addEventListener('input', show); input.addEventListener('focus', show); input.addEventListener('click',show);
      input.addEventListener('blur',close);
      input.addEventListener('keydown', event => {
        if (event.key === 'Escape') { close(); return; }
        if (event.key === 'Enter' && !menu.hidden && active >= 0) { event.preventDefault(); choose(active); return; }
        if (!['ArrowDown','ArrowUp'].includes(event.key)) return;
        event.preventDefault(); if (menu.hidden) show(); if (!matches.length) return;
        active = event.key === 'ArrowDown' ? (active + 1) % matches.length : (active <= 0 ? matches.length - 1 : active - 1);
        Array.from(menu.children).forEach((row,index) => row.setAttribute('aria-selected',String(index === active)));
        const row = menu.children[active]; input.setAttribute('aria-activedescendant', row.id); row.scrollIntoView({block:'nearest'});
      });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',setupLocations); else setupLocations();
})();
