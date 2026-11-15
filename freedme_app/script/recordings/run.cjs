const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/Users/prakashteli/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path');const {execFileSync}=require('child_process');
function clock(url,mode){execFileSync('docker',['compose','-f','compose.recording.yml','exec','-T','web','bin/rails','runner','script/recordings/clock.rb',url.split('/').pop(),mode],{stdio:'pipe'});}
const base=process.env.RECORDING_BASE_URL||'http://127.0.0.1:3002',out=path.resolve(process.env.RECORDING_OUTPUT||'../output/rails-demo');
fs.mkdirSync(out,{recursive:true});
const manifest=fs.existsSync(path.join(out,'manifest.json'))?JSON.parse(fs.readFileSync(path.join(out,'manifest.json'))):[];let page,ctx,browser,title;let signIns=[];
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let pointerInstalled=false;
function instrumentPointer(p){
 if(pointerInstalled)return;pointerInstalled=true;
 const proto=Object.getPrototypeOf(p.locator('body'));
 for(const method of ['click','fill','check','selectOption','setInputFiles']){
  const original=proto[method];
  proto[method]=async function(...args){
   if(await this.isVisible()){
    await this.scrollIntoViewIfNeeded();
    const box=await this.boundingBox();
    if(box){await this.page().mouse.move(box.x+box.width/2,box.y+Math.min(box.height/2,22),{steps:8});await sleep(180);}
   }
   if(method==='click')args[0]={delay:180,...args[0]};
   return original.apply(this,args);
  };
 }
}
async function caption(text){console.log(text);await page.evaluate(text=>{sessionStorage.setItem('recording-caption',text);let e=document.getElementById('recording-caption');if(e)e.textContent=text},text);await sleep(900)}
async function go(url){await page.goto(base+url);await page.waitForLoadState('networkidle');await sleep(400)}
async function click(name){await page.getByRole('button',{name,exact:true}).click();await page.waitForLoadState('networkidle');await sleep(500)}
async function roleNotice(n){const role=({1:'donor',2:'donor',3:'recipient',4:'recipient',5:'moderator'})[n];await page.evaluate(role=>{const el=document.createElement('div');el.id='recording-role-notice';el.style='position:fixed;inset:0;z-index:100000;background:#102c4faa;display:grid;place-items:center;font-family:system-ui';const box=document.createElement('div');box.style='background:white;color:#143858;border-radius:20px;padding:48px;text-align:center;box-shadow:0 20px 80px #102c4f55';const h=document.createElement('h2');h.style='font-size:36px;margin:0 0 18px';h.textContent='Now signing in as '+role;box.append(h);const p=document.createElement('p');p.textContent='The demo will continue in a few seconds.';box.append(p);el.append(box);document.body.append(el)},role);await sleep(3000);await page.locator('#recording-role-notice').evaluate(el=>el.remove())}
async function login(n){
 await roleNotice(n);
 await ctx.clearCookies();
 execFileSync('docker',['compose','-f','compose.recording.yml','exec','-T','web','bin/rails','runner','script/recordings/prepare_sign_in.rb'],{stdio:'pipe'});
 await go('/sign-in');
 await caption('Sign in as '+({1:'Nina · Donor',2:'David · Donor',3:'Maya · Recipient',4:'Alex · Recipient',5:'Sam · Moderator'})[n]);
 await page.getByRole('heading',{name:'Sign in',exact:false}).first().waitFor();
 await page.getByLabel('Mobile phone number').fill('510555010'+n);
 await sleep(1200);
 await click('Send simulated code');
 let inbox=await ctx.newPage();await inbox.goto(base+'/test-data');
 const sms=await inbox.locator('article').filter({hasText:'+1510555010'+n}).filter({hasText:'code:'}).first().innerText();await inbox.close();
 await caption('Enter the simulated SMS code to finish signing in');
 await page.getByLabel('Six-digit code').fill(sms.match(/code: (\d+)/)[1]);
 await sleep(1200);await click('Verify and sign in');
 if(new URL(page.url()).pathname!='/activity')throw Error('Sign-in did not reach My Activity');
 if(n!==5){
 const tabs=await page.locator('[role="tablist"] [role="tab"]').allTextContents();
 const expected=['My Equipment','Requests & Handoffs','Questions & Answers','Simulated SMS'];
 if(JSON.stringify(tabs.map(t=>t.trim()))!==JSON.stringify(expected))throw Error('Outdated activity tabs: '+JSON.stringify(tabs));
 await caption('My Activity: My Equipment, Requests & Handoffs, Questions & Answers, and Simulated SMS');await sleep(3200);
 }
 signIns.push({account:n,mobileScreen:true,otpScreen:true,authenticated:true});
}

const id=n=>'019a0000-0000-7000-8000-'+String(n).padStart(12,'0');
async function sms(){await go('/activity#panel-messages');await caption('Simulated SMS · persisted by the actual Rails workflow');await page.locator('#panel-messages').scrollIntoViewIfNeeded();await sleep(1800)}
async function publish(n){if((process.env.SKIP_PUBLISH||'').split(',').includes(String(n)))return;await login(5);await go('/activity#panel-review');const card=page.locator('#panel-review article').filter({has:page.locator(`a[href="/equipment/${id(n)}"]`)});await card.scrollIntoViewIfNeeded();await caption('Moderator reviews the listing and publishes it');await card.getByLabel('Review notes').fill('Fictional demonstration listing reviewed.');await card.getByRole('button',{name:'Approve & publish (simulation)',exact:true}).click();await page.waitForLoadState('networkidle');}
async function request(n){await login(3);await go('/equipment/'+id(n));await caption('Recipient opens the equipment and requests it');await page.getByRole('link',{name:'Request this item',exact:true}).click();await page.waitForLoadState('networkidle');await choose('document_kind','Government-issued ID');await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/fictional-id.png');await page.locator('input[name=processing_consent]').check();await caption('Upload fictional evidence · AWS response is simulated in this sandbox');await click('Upload and scan');await page.getByRole('heading',{name:'Confirm your document details'}).waitFor();await caption('Review extracted name and location; consent before sending the request');await page.locator('input[name=confirmed]').check();await page.locator('input[name=consent]').check();await click('Confirm and submit request');return new URL(page.url()).pathname}
async function choose(name,label){const native=page.locator(`select[name="${name}"]`);if(await native.isVisible())return native.selectOption({label});const m=page.locator(`md-outlined-select[name="${name}"]`);await m.click();await m.getByRole('option',{name:label,exact:true}).click()}
async function approve(url){await login(1);await go(url);await caption('Donor approves and proposes a public daytime pickup');await page.getByLabel('Day and time (Pacific Time)').fill('2026-11-15T11:00');await page.locator('input[name=location]').fill('Fictional Sample Library courtyard, during opening hours');await click('Approve')}
async function record(slug,name,fn){if(process.env.ONLY&&!process.env.ONLY.split(',').includes(slug))return;title=name;signIns=[];ctx=await browser.newContext({viewport:{width:1440,height:1000},recordVideo:{dir:path.join(out,'raw'),size:{width:1440,height:1000}}});await ctx.addInitScript({path:path.join(__dirname,'cursor.js')});await ctx.addInitScript(()=>{addEventListener('DOMContentLoaded',()=>{let el=document.createElement('div');el.id='recording-caption';el.textContent=sessionStorage.getItem('recording-caption')||'Actual Rails website · fictional recording sandbox';el.style='position:fixed;bottom:0;left:0;right:0;padding:16px 24px;background:#102c4fee;color:white;font:600 20px system-ui;z-index:99999;pointer-events:none';document.body.appendChild(el);document.body.style.paddingBottom='70px'})});ctx.setDefaultTimeout(30000);ctx.setDefaultNavigationTimeout(60000);page=await ctx.newPage();instrumentPointer(page);try{await go('/');await caption(name);await fn();await caption('Scenario complete · actual Rails actions, simulated external services');await sleep(1200);const video=page.video();await ctx.close();await video.saveAs(path.join(out,slug+'.webm'));const previous=manifest.findIndex(x=>x.slug===slug);if(previous>=0)manifest.splice(previous,1);manifest.push({slug,title:name,status:'passed',roleNoticesEmbedded:true,cursorTracking:true,fullSignIn:true,signIns});fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));console.log('DONE '+slug)}catch(e){await page.screenshot({path:path.join(out,slug+'-failure.png'),fullPage:true});console.error(e);await ctx.close();throw e}}
(async()=>{browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,slowMo:60});
await record('00-review-guide','Start here · How to review and export feedback',async()=>{
 await sleep(6500);
 await go('/recordings/index.html#01-gift');
 await caption('Choose a scenario from the list, then press Play to watch the journey');await sleep(7500);
 await page.locator('#speed').selectOption('0.5');
 await caption('Use playback speed to slow the video. Pause whenever you want to leave feedback');await sleep(7500);
 await page.locator('#notes').scrollIntoViewIfNeeded();
 await caption('Enter feedback below the video. Include the timestamp and what you would change');await sleep(7500);
 await page.locator('#notes').fill('Example feedback — 00:30: The My Equipment tab is clear. Please explain the next step after approval.');
 await caption('Your notes are saved in this browser for each scenario. They are not sent automatically');await sleep(8500);
 const downloadPromise=page.waitForEvent('download');
 await page.getByRole('button',{name:'Export feedback',exact:true}).click();
 const download=await downloadPromise;const file=path.join(out,'review-guide-example-feedback.json');await download.saveAs(file);
 const exported=JSON.parse(fs.readFileSync(file));if(!exported.feedback.some(x=>x.note.includes('Example feedback')))throw Error('Feedback export failed');
 await caption('Click Export feedback to download your notes. Send that file to the FreeDME review team');await sleep(8500);
 await caption('You are ready to explore. The following recordings use fictional users and simulated SMS');await sleep(7500);
});
await record('01-gift','Free gift · request, approval and handoff',async()=>{await publish(1000);const url=await request(1000);await sms();await approve(url);await sms();await login(3);await go(url);await caption('Recipient accepts the proposed pickup');await click('Accept suggested handoff');await caption('After meeting in person, recipient confirms actual handoff');await click('Confirm actual handoff');await sms();await login(1);await go(url);await caption('Donor sees the completed transaction');});
await record('02-negotiation','Pickup negotiation · recipient proposes, donor accepts',async()=>{let url;if(process.env.RESUME_NEGOTIATION){await login(3);await go('/activity#panel-requests');await page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(1001)+'"]')}).getByRole('link',{name:'View transaction'}).click();url=new URL(page.url()).pathname;}else{await publish(1001);url=await request(1001);await approve(url);await login(3);await go(url);}await page.getByText('Suggest a different day/time or location',{exact:true}).click();await caption('Recipient counterproposes using the prefilled form');await page.getByLabel('Day and time (Pacific Time)').fill('2026-11-16T12:00');await page.locator('input[name=location]').fill('Fictional Sample Community Center entrance');await click('Send suggestion');await login(1);await go(url);await caption('Donor reviews and accepts the recipient’s alternative');await click('Accept suggested handoff');await sms();});
await record('03-declined','Donor declines a request',async()=>{await publish(1002);const url=await request(1002);await login(1);await go(url);await caption('Donor declines this request');await click('Decline');await login(3);await go(url);await caption('Recipient sees the declined status');await sms();});
await record('04-unavailable','Donor marks equipment unavailable',async()=>{await publish(1003);const url=await request(1003);await login(1);await go(url);await caption('Equipment is no longer available');await click('Unavailable');await login(3);await go(url);await sms();});
await record('05-loan','Free loan · handoff and return',async()=>{await publish(1004);const url=await request(1004);await approve(url);await login(3);await go(url);await click('Accept suggested handoff');await caption('Recipient confirms pickup; the equipment is now on loan');await click('Confirm actual handoff');await login(1);await go(url);await caption('After physical return, donor confirms equipment returned');await click('Confirm equipment returned');await sms();});

await record('06-questions','Questions and answers · both participant views',async()=>{await publish(2000);await login(3);await go('/equipment/'+id(2000)+'#ask-question');await caption('Recipient asks about the folding mechanism');await page.getByLabel('Your question').fill('Does this walker fold flat for transport?');await click('Send question');await login(2);await go('/activity#panel-questions');await caption('Donor opens the pending question and answers it');await page.getByText('Answer',{exact:true}).first().click();await page.getByLabel('Your answer').fill('Yes, the fictional sample walker folds flat.');await click('Submit answer');await login(3);await go('/activity#panel-questions');await caption('Recipient reads the answer grouped under the equipment title');await sms();});
await record('07-listing','Add equipment · accepted and rejected photos',async()=>{await login(1);await go('/donate');await caption('Donor creates a fictional equipment listing');await page.getByLabel('Listing title').fill('Demo shower chair — photo screening');await choose('listing[category_id]','Shower chairs');await choose('listing[offer_kind]','Free to keep');await choose('listing[condition_code]','New');await page.locator('#listing_public_locality').fill('Fremont');await page.getByLabel('Description',{exact:false}).fill('FICTIONAL EQUIPMENT. Adjustable-height shower chair with backrest. Review dimensions and capacity before use. Demonstration only.');await caption('Upload photo 1: the front view is accepted by simulated screening');
await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/accepted-front.png');
await page.locator('.photo-status-accepted').nth(0).waitFor();await sleep(1800);
await caption('Upload photo 2: the detail view is also accepted');
await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/accepted-detail.png');
await page.locator('.photo-status-accepted').nth(1).waitFor();await sleep(1800);
await caption('Upload photo 3: a non-equipment image is rejected in this simulation');
await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/rejected-non-equipment.png');
await page.locator('.photo-status-rejected').waitFor();
await page.locator('.photo-status-rejected').scrollIntoViewIfNeeded();
await caption('Two ACCEPTED images and one REJECTED image; remove the flagged photo before submitting');
if(await page.locator('.photo-status-accepted').count()!==2)throw Error('Expected two accepted photos');
if(await page.locator('input[type=file]').evaluate(el=>el.validity.valid))throw Error('Rejected photo must block submission');
await page.screenshot({path:path.join(out,'07-screening-check.png'),fullPage:true});await sleep(3000);
await page.getByRole('button',{name:'Remove selected photo 3',exact:true}).click();
await page.locator('.photo-status-rejected').waitFor({state:'detached'});
if(await page.locator('.selected-photo').count()!==2)throw Error('Expected only two remaining photos');
if(!await page.locator('input[type=file]').evaluate(el=>el.validity.valid))throw Error('Photo validation did not clear');
await caption('Rejected image removed; the two accepted equipment photos remain');await sleep(2000);await page.locator('#listing_no_missing_parts_affirmed').check();await page.locator('#listing_fully_functional_affirmed').check();await page.locator('#listing_truthfulness_affirmed').check();await caption('Photos accepted by simulated screening; submit for moderator review');await click('Submit for review');if(!page.url().includes('/activity')){console.log(await page.locator(':invalid').evaluateAll(es=>es.map(e=>({id:e.id,name:e.name,message:e.validationMessage}))));throw Error('Listing was not submitted: '+page.url());}await caption('Successful submission returns to Your Equipment');await sms();await login(5);await go('/activity#panel-review');const card=page.locator('#panel-review article').filter({hasText:'Demo shower chair — photo screening'});await card.scrollIntoViewIfNeeded();await card.getByLabel('Review notes').fill('Fictional recording equipment approved for this demo.');await caption('Moderator reviews disclosures and publishes the new listing');await card.getByRole('button',{name:'Approve & publish (simulation)',exact:true}).click();await page.waitForLoadState('networkidle');await login(1);await go('/activity#panel-inventory');await sms();});
await record('08-registration','New user registration · simulated OTP and welcome message',async()=>{await roleNotice(3);await go('/sign-in');await caption('An unregistered mobile number is routed to registration');await page.getByLabel('Mobile phone number').fill('5105550106');await click('Send simulated code');await page.getByLabel('Display name').fill('Casey Demo');await page.locator('#locality').fill('Fremont');await page.locator('#locality').press('ArrowDown');await page.locator('#locality').press('Enter');await page.getByLabel('Mobile phone number').fill('5105550106');await click('Verify mobile and register');const inbox=await ctx.newPage();await inbox.goto(base+'/test-data');const text=await inbox.locator('article').filter({hasText:'+15105550106'}).filter({hasText:'code:'}).first().innerText();await inbox.close();await page.getByLabel('Six-digit code').fill(text.match(/code: (\d+)/)[1]);await caption('Correct simulated OTP creates the new account');await click('Verify and sign in');await sms();});
await record('09-scan-recovery','Identity scan failure and recovery',async()=>{if(!process.env.RESUME_SCAN)await publish(2001);await login(4);await go('/equipment/'+id(2001)+'/request');await caption('An unreadable utility bill produces no extracted fields in this test');await choose('document_kind','Utility bill');await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/fictional-id.png');await page.locator('input[name=processing_consent]').check();await click('Upload and scan');await page.getByText(/We could not extract your full name/).first().waitFor();await caption('Friendly error: request is not sent to the donor');await sleep(2000);await choose('document_kind','Government-issued ID');await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/fictional-id.png');await page.locator('input[name=processing_consent]').check();await caption('Retry with the readable fictional ID fixture');await click('Upload and scan');await page.getByRole('heading',{name:'Confirm your document details'}).waitFor();await caption('Successful retry reaches requester confirmation; no request sent until consent');});
await record('10-expiry','Pending expiry · donor reopening and recipient retry',async()=>{let url;if(process.env.RESUME_EXPIRY){await login(3);await go('/activity#panel-requests');await page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(2002)+'"]')}).getByRole('link',{name:'View transaction'}).click();url=new URL(page.url()).pathname;}else{await publish(2002);url=await request(2002);}await caption('TEST CLOCK: expire only this recording transaction, without waiting 48 hours');clock(url,'expire');await go('/activity#panel-requests');await caption('Recipient sees Expired, Request Again and Remove Request');await login(2);await go('/activity#panel-inventory');const card=page.locator('#panel-inventory article').filter({has:page.locator('a[href="/equipment/'+id(2002)+'"]')});await card.scrollIntoViewIfNeeded();await card.getByRole('checkbox').check();await caption('Donor confirms actual possession and availability');await card.getByRole('button',{name:'Make available again'}).click();await page.waitForLoadState('networkidle');await login(3);await go('/activity#panel-requests');const expired=page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(2002)+'"]')});await expired.getByRole('link',{name:'Request Again'}).click();await caption('Retry rechecks identity and consent before a new request');await choose('document_kind','Government-issued ID');await page.locator('input[type=file]').setInputFiles('script/recordings/fixtures/fictional-id.png');await page.locator('input[name=processing_consent]').check();await click('Upload and scan');await page.locator('input[name=confirmed]').check();await page.locator('input[name=consent]').check();await click('Confirm and submit request');await go('/activity#panel-requests');await caption('Successful retry replaces the expired entry in the recipient view');});
await record('11-followup','Moderator follow-up · seven days without confirmed handoff',async()=>{await login(1);await go('/activity#panel-requests');const card=page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(1001)+'"]')});await card.getByRole('link',{name:'View transaction'}).click();const url=new URL(page.url()).pathname;await caption('TEST CLOCK: make this reserved recording transaction eight days old');clock(url,'followup');await login(5);await go('/activity#panel-followups');await caption('Moderator opens the unconfirmed handoff task');const task=page.locator('#panel-followups article').filter({hasText:'Adjustable walking cane'});await task.scrollIntoViewIfNeeded();await task.getByLabel('Donor contacted').check();await task.getByLabel('Recipient contacted').check();await choose('outcome','Not handed off');await task.getByLabel('Notes').fill('Fictional follow-up: both parties contacted; pickup has not happened.');await caption('Record findings without claiming a physical handoff');await task.getByRole('button',{name:'Resolve follow-up'}).click();await page.waitForLoadState('networkidle');await caption('Task resolved; the transaction is not automatically completed or reopened');});
await record('12-pickup-followup','Pickup follow-up · 24 hours after the agreed time',async()=>{
 await login(1);await go('/activity#panel-requests');
 const card=page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(1001)+'"]')});
 await card.getByRole('link',{name:'View transaction'}).click();
 const url=new URL(page.url()).pathname;
 await caption('Donor sees the agreed pickup; handoff has not been confirmed');await sleep(6500);
 await login(3);await go(url);
 await caption('Recipient sees the same agreed pickup time and public location');await sleep(6500);
 await caption('TEST CLOCK: advance to 24 hours after the agreed pickup time');await sleep(6000);clock(url,'pickup');
 await go('/activity#panel-messages');
 const message=page.locator('#panel-messages article').filter({hasText:'Thank you for using FreeDME. Did you pick up'}).filter({hasText:'walking cane'}).first();
 await message.scrollIntoViewIfNeeded();
 await caption('Recipient receives one pickup follow-up with equipment, donor, date and time');await sleep(8500);
 await caption('The message asks for YES or NO; incoming SMS replies are not connected yet');await sleep(8000);
 await message.getByRole('link').click();await page.waitForLoadState('networkidle');
 await caption('The short link opens Requests & Handoffs to review the transaction');await sleep(7000);
 await page.locator('#panel-requests article').filter({has:page.locator('a[href="/equipment/'+id(1001)+'"]')}).getByRole('link',{name:'View transaction'}).click();
 await caption('A reminder does not confirm pickup or change the equipment status');await sleep(6500);
});
await record('13-registration-area','Registration eligibility · Bay Area locations only',async()=>{
 await roleNotice(3);await go('/register');
 await caption('New member enters a display name and mobile number');
 await page.getByLabel('Display name').fill('Jordan Demo');
 await page.getByLabel('Mobile phone number').fill('5105550188');
 await page.locator('#locality').fill('Los Angeles');
 await caption('Try registering with a town outside the Bay Area');await sleep(4500);
 await click('Verify mobile and register');
 const warning='FreeDME is currently available only for Bay Area, California community members';
 await page.getByText(warning,{exact:true}).waitFor();
 if(new URL(page.url()).pathname!='/register')throw Error('Outside town was not blocked');
 await caption('Registration is blocked with the Bay Area availability message');await sleep(6500);
 await page.locator('#locality').fill('90001');
 await caption('An outside-area ZIP code is also rejected');await sleep(4000);
 await click('Verify mobile and register');await page.getByText(warning,{exact:true}).waitFor();await sleep(4500);
 await page.locator('#locality').fill('Fremont · 94536');
 await page.locator('#locality').press('Tab');
 await caption('Correct the location to Fremont, a supported Bay Area town and ZIP');await sleep(5500);
 await click('Verify mobile and register');
 await page.getByLabel('Six-digit code').waitFor();
 await caption('The eligible location can continue to simulated mobile verification');await sleep(6500);
});
await browser.close();})().catch(e=>{console.error(e);process.exit(1)});
