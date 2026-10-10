(() => {
  'use strict';
  const dialog = document.getElementById('voice-demo');
  if (!dialog) return;
  const el = id => document.getElementById(`voice-${id}`);
  const samples = [
    {name:'Folding walker', type:'walker', location:'Fremont', details:'Height adjustable, gently used'},
    {name:'Rollator walker', type:'walker', location:'Fremont', details:'Four wheels, seat and hand brakes'},
    {name:'Manual wheelchair', type:'wheelchair', location:'San Jose', details:'Standard adult chair, gently used'},
    {name:'Adjustable cane', type:'cane', location:'Dublin', details:'Single-point walking cane'}
  ];
  let results = [], pending = null, reserved = null, deliveryPending = false, recognition = null, listening = false;
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  const status = message => { el('status').textContent = message; };
  function stop() {
    if (recognition) { const old = recognition; recognition = null; old.abort(); }
    listening = false; el('mic').textContent = 'Speak';
    window.speechSynthesis?.cancel();
  }
  function say(message, user = false) {
    const row = document.createElement('p');
    row.textContent = `${user ? 'You' : 'Assistant'}: ${message}`;
    el('log').append(row); el('log').scrollTop = el('log').scrollHeight;
    if (!user && el('read').checked && window.speechSynthesis) {
      window.speechSynthesis.cancel();
      const speech = new SpeechSynthesisUtterance(message); speech.rate = 0.95;
      window.speechSynthesis.speak(speech);
    }
  }
  function select(item) {
    pending = item;
    say(`You selected ${item.name} in ${item.location}. Say Confirm to simulate a reservation, or Cancel. No actual equipment will be held.`);
    el('results').replaceChildren();
    for (const [label,command] of [['Confirm demo reservation','confirm'],['Cancel','cancel']]) {
      const b = document.createElement('button'); b.type = 'button'; b.textContent = label;
      b.addEventListener('click', () => handle(command)); el('results').append(b);
    }
  }
  function choices(options) {
    el('results').replaceChildren();
    options.forEach(([label, command]) => {
      const button = document.createElement('button');
      button.type = 'button'; button.textContent = label;
      button.addEventListener('click', () => handle(command));
      el('results').append(button);
    });
  }
  function fulfillmentChoices() {
    choices([['Request pickup and delivery', 'request delivery'], ['I will collect it', 'self pickup']]);
  }
  function handle(raw) {
    stop(); const text = raw.trim().slice(0,500); if (!text) return;
    say(text,true); const q = text.toLowerCase(); status('');
    if (q === 'cancel delivery') {
      deliveryPending=false;
      if (reserved) { fulfillmentChoices(); say('Delivery request cancelled. Your sample reservation remains. Choose self-pickup or request delivery.'); }
      return;
    }
    if (q === 'confirm delivery') {
      if (!reserved || !deliveryPending) { say('First confirm a sample reservation, then request pickup and delivery.'); return; }
      deliveryPending=false;
      choices([['I will collect it instead', 'self pickup']]);
      say(`Demo delivery request submitted for ${reserved.name} from ${reserved.location}. In a real service, the team would contact you to confirm the delivery address, accessibility needs and a suitable time, subject to volunteer availability. No pickup or delivery is scheduled, and no real request was sent. Do not enter a home address in this demo.`);
      return;
    }
    if (/\b(delivery|deliver|pickup|pick up|collect)\b/.test(q)) {
      if (!reserved) { say('Please select equipment and confirm your demo reservation before choosing pickup or delivery.'); return; }
      if (/self|collect|myself/.test(q)) {
        deliveryPending=false; el('results').replaceChildren();
        say(`Self-pickup selected for ${reserved.name} in ${reserved.location}. In the real service, complete the required waiver and book an available pickup slot in your account. No appointment has been booked in this demo.`);
        choices([['Request pickup and delivery instead', 'request delivery']]); return;
      }
      deliveryPending=true;
      say(`Would you like a volunteer to pick up ${reserved.name} from ${reserved.location} and deliver it to you? This is a sample request subject to team approval and volunteer availability. Say Confirm delivery or Cancel delivery. No personal address is needed for this demo.`);
      choices([['Confirm demo delivery request', 'confirm delivery'], ['Cancel delivery', 'cancel delivery']]); return;
    }
    if (/\b(cancel|start over|reset)\b/.test(q)) { pending=null;reserved=null;deliveryPending=false;results=[];el('results').replaceChildren();say('Cancelled. Tell me which equipment and location you would like to search.');return; }
    if (/^(yes|confirm|confirm reservation|confirm demo reservation)[.!]?$/i.test(q)) {
      if (!pending) {say('Choose an item before confirming a demo reservation.');return;}
      const item=pending;pending=null;reserved=item;deliveryPending=false;results=[];fulfillmentChoices();
      say(`Demo complete: ${item.name} in ${item.location}. Nothing was reserved and no email was sent. You can now choose self-pickup or request volunteer pickup and delivery for this sample reservation. To make a real request, use Browse actual equipment and sign in.`);return;
    }
    if (/\b(reserve|select|choose)\b/.test(q)) {
      const index = /\b(second|2|two)\b/.test(q) ? 1 : /\b(first|1|one)\b/.test(q) ? 0 : -1;
      const item = index >= 0 ? results[index] : results.find(x => q.includes(x.name.toLowerCase()));
      if(item) select(item); else say('Search first, then choose a result using its button or say Reserve the first one.');return;
    }
    pending=null;reserved=null;deliveryPending=false;
    const type = /wheel\s?chair/.test(q) ? 'wheelchair' : /walker|rollator/.test(q) ? 'walker' : /cane/.test(q) ? 'cane' : null;
    const location = ['Fremont','San Jose','Dublin'].find(x=>q.includes(x.toLowerCase()));
    if(!type && !location && !/\b(equipment|show all|available)\b/.test(q)) {say('This guided demo understands walkers, wheelchairs and canes in Fremont, San Jose or Dublin. Try Find a walker in Fremont.');return;}
    results=samples.filter(x=>(!type||x.type===type)&&(!location||x.location===location));
    el('results').replaceChildren();
    results.forEach((item,i)=>{
      const card=document.createElement('article'), title=document.createElement('strong'), detail=document.createElement('p'), b=document.createElement('button');
      title.textContent=`${i+1}. ${item.name} — ${item.location}`;detail.textContent=`Sample only · ${item.details}`;
      b.type='button';b.textContent=`Choose ${item.name}`;b.addEventListener('click',()=>select(item));card.append(title,detail,b);el('results').append(card);
    });
    say(results.length ? `I found ${results.length} sample result${results.length===1?'':'s'}. ${results.map((x,i)=>`${i+1}: ${x.name} in ${x.location}`).join('. ')}. Which would you like?` : 'No sample matches. Try a walker in Fremont, a wheelchair in San Jose, or a cane in Dublin. Actual inventory is available through Browse actual equipment.');
  }
  el('launch').addEventListener('click',()=>{dialog.showModal();document.body.classList.add('voice-open');el('input').focus();if(!el('log').children.length)say('Welcome to the Mobility Exchange demo. What equipment are you looking for?');});
  el('close').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('close',()=>{stop();document.body.classList.remove('voice-open');el('launch').focus();});
  el('form').addEventListener('submit',e=>{e.preventDefault();handle(el('input').value);el('input').value='';});
  el('stop').addEventListener('click',()=>{stop();status('Audio stopped.');});
  el('read').addEventListener('change',()=>{if(!el('read').checked)window.speechSynthesis?.cancel();});
  el('reset').addEventListener('click',()=>{stop();pending=null;reserved=null;deliveryPending=false;results=[];el('log').replaceChildren();el('results').replaceChildren();el('input').value='';status('');say('Let’s start again. What equipment and location would you like?');});
  el('mic').disabled=!SpeechRecognition;
  if(!SpeechRecognition)status('Voice recognition is unavailable in this browser. Please type your message.');
  el('mic').addEventListener('click',()=>{
    if(listening){stop();status('Microphone stopped.');return;}
    stop(); recognition=new SpeechRecognition(); const session=recognition;
    session.lang='en-US';session.interimResults=false;session.continuous=false;
    session.onresult=e=>{if(recognition===session)handle(e.results[0][0].transcript);};
    session.onerror=e=>{if(recognition!==session)return;status(e.error==='not-allowed'?'Microphone permission was denied. You can type instead.':'Could not hear you. Try again or type your message.');};
    session.onend=()=>{if(recognition===session){recognition=null;listening=false;el('mic').textContent='Speak';if(el('status').textContent==='Listening…')status('Listening ended.');}};
    try{session.start();listening=true;el('mic').textContent='Stop listening';status('Listening…');}catch{stop();status('Could not start microphone. Please type instead.');}
  });
  window.addEventListener('pagehide',stop);
})();
