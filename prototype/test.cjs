const assert=require('node:assert/strict');const m=require('./dist/app.js');
const reset=()=>{m.set(m.seed());const s=m.get();s.role='recipient';s.signed=true;return s;};
let s=reset();let r=m.createRequest(1);assert.throws(()=>m.createRequest(1),/no longer available/);assert.throws(()=>m.move(r.id,'offer'),/correct/);s.role='donor';m.move(r.id,'offer');assert.equal(r.state,'offered');assert.equal(r.reserved,undefined);s.role='recipient';m.move(r.id,'accept');assert.equal(s.items[0].status,'reserved');assert.equal(r.handoff,undefined);m.move(r.id,'cancel');assert.equal(s.items[0].status,'unavailable');s.role='donor';assert.throws(()=>m.reopen(1,false),/confirmation/);m.reopen(1,true);assert.equal(s.items[0].status,'available');
s=reset();r=m.createRequest(1);s.time+=48*3600000;m.expire();assert.equal(r.state,'expired');assert.equal(s.items[0].status,'unavailable');
s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.role='recipient';s.time+=24*3600000;assert.throws(()=>m.move(r.id,'accept'),/not available/);assert.equal(r.state,'expired');
s=reset();assert.throws(()=>m.createRequest(3,{loanDays:7,consent:true}),/evidence/);s.evidence='reviewed';assert.throws(()=>m.createRequest(3,{loanDays:15,consent:true}),/whole-day/);r=m.createRequest(3,{loanDays:7,consent:true});s.role='donor';r.consent=false;assert.throws(()=>m.move(r.id,'offer'),/no longer valid/);r.consent=true;m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');s.role='donor';m.move(r.id,'handoff');assert.equal(r.state,'loaned');m.move(r.id,'return');assert.equal(s.items[2].status,'unavailable');s.items[2].hold=true;assert.throws(()=>m.reopen(3,true),/safety hold/);
s=reset();r=m.createRequest(2);r.paused='delivery failure';s.role='donor';assert.throws(()=>m.move(r.id,'offer'),/hold/);
console.log('PASS: gift/loan lifecycle, role gating, one active request, expiry boundaries, consent revocation, cancellation, possession and safety holds, delivery pause.');

// Regression: inventory View/Review request must lead to actionable donor review.
s=reset();r=m.createRequest(2);s.role='donor';
assert.match(m.activity(), /data-action="detail" data-id="2">Review request/);
assert.match(m.detail(2), /data-action="offer" data-id="R-101"[^>]*>Approve & make offer/);
assert.match(m.detail(2), /Maya then has 24 hours to accept/);
r.paused='delivery failure';assert.match(m.detail(2), /data-action="offer"[^>]*disabled/);delete r.paused;
m.move(r.id,'offer');assert.match(m.detail(2), /Waiting for recipient acceptance/);assert.doesNotMatch(m.detail(2), /data-action="offer"/);assert.equal(r.reserved,undefined);
s.role='recipient';assert.doesNotMatch(m.detail(2), /Donor request review/);assert.match(m.activity(), /Accept & reserve/);
m.move(r.id,'accept');s.role='donor';assert.match(m.detail(2), /Confirm handoff/);
console.log('PASS: donor detail approval, pause guard, offered status, recipient acceptance, and handoff UI.');

// Direct donor contact is visible only to the recipient after reservation.
s=reset();r=m.createRequest(2);assert.doesNotMatch(m.activity(), /Contact donor for pickup/);
s.role='donor';m.move(r.id,'offer');s.role='recipient';assert.doesNotMatch(m.activity(), /Contact donor for pickup/);
m.move(r.id,'accept');assert.match(m.activity(), /Mobile:<\/strong>.*555-0100/);assert.match(m.activity(), /Contact the donor directly by phone or text/);assert.match(m.activity(), /public, nonresidential place/);
s.role='donor';assert.doesNotMatch(m.activity(), /Contact donor for pickup/);
s.role='recipient';r.paused='security restriction';assert.doesNotMatch(m.activity(), /Contact donor for pickup/);delete r.paused;
m.move(r.id,'cancel');assert.doesNotMatch(m.activity(), /Contact donor for pickup/);
console.log('PASS: reserved recipient donor contact, pickup guidance, and visibility guards.');

// Donated owner details show the closed status once, directly below the title.
s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');s.role='donor';m.move(r.id,'handoff');
const donatedDetail=m.detail(1);
assert.match(donatedDetail, /Folding walker<\/h1><div class="note" role="status"><strong>DONATED<\/strong>\. New requests are closed\.<\/div>/);
assert.equal((donatedDetail.match(/<strong>DONATED<\/strong>\. New requests are closed\./g)||[]).length,1);
assert.doesNotMatch(donatedDetail, /data-action="request"/);
console.log('PASS: donated status directly below donor item title, without duplicate or new-request action.');

// Reserved details show the closed status under the title without a bottom duplicate.
s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');s.role='donor';
const reservedDetail=m.detail(1);
assert.match(reservedDetail, /Folding walker<\/h1><div class="note" role="status"><strong>RESERVED<\/strong> New requests are closed<\/div>/);
assert.equal((reservedDetail.match(/New requests are closed/g)||[]).length,1);
assert.doesNotMatch(reservedDetail, /data-action="request"/);
console.log('PASS: reserved status under title without duplicate or new-request action.');

// Recipient loan handoff wording; donor and pre-handoff wording stays unchanged.
s=reset();s.evidence='reviewed';r=m.createRequest(3,{loanDays:14,consent:true});s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');
assert.match(m.activity(), /Requested period: 14 days/);
s.role='donor';m.move(r.id,'handoff');assert.match(m.activity(), /Requested by Maya/);
s.role='recipient';assert.doesNotMatch(m.activity(), /Requested by Maya/);assert.match(m.activity(), /Remaining loan period: 14 days/);
console.log('PASS: recipient loan handoff labels.');

// Recipient consent revocation is available before handoff, blocked afterward.
s=reset();s.evidence='reviewed';r=m.createRequest(3,{loanDays:14,consent:true});
assert.match(m.activity(), /Revoke disclosure consent/);m.revokeConsent(r.id);assert.equal(r.consent,false);
s=reset();s.evidence='reviewed';r=m.createRequest(3,{loanDays:14,consent:true});s.role='donor';assert.throws(()=>m.revokeConsent(r.id),/Recipient access/);m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');assert.match(m.activity(), /Revoke disclosure consent/);
s.role='donor';m.move(r.id,'handoff');s.role='recipient';assert.doesNotMatch(m.activity(), /Revoke disclosure consent/);assert.throws(()=>m.revokeConsent(r.id),/cannot be revoked/);assert.equal(r.consent,true);
s.role='donor';m.move(r.id,'return');s.role='recipient';assert.doesNotMatch(m.activity(), /Revoke disclosure consent/);assert.throws(()=>m.revokeConsent(r.id),/cannot be revoked/);
console.log('PASS: recipient consent revocation blocked after handoff, including stale actions.');

// Either participant can confirm an actual handoff once; no staff or visitor confirmation.
for(const kind of ['gift','loan'])for(const actor of ['donor','recipient']){
 s=reset();s.evidence='reviewed';r=m.createRequest(kind==='gift'?1:3,{loanDays:14,consent:true});
 assert.throws(()=>m.move(r.id,'handoff'),/not available/);
 s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');
 assert.match(m.activity(), /Confirm handoff/);s.role='donor';assert.match(m.activity(), /Confirm handoff/);
 s.role='moderator';assert.throws(()=>m.move(r.id,'handoff'),/correct signed-in/);
 s.role=actor;s.signed=false;assert.throws(()=>m.move(r.id,'handoff'),/correct signed-in/);s.signed=true;
 m.move(r.id,'handoff');assert.equal(r.handoffBy,actor);assert.equal(r.state,kind==='gift'?'completed':'loaned');
 assert.match(r.history.at(-1),new RegExp('confirmed by .*'+actor));
 const at=r.handoff;s.role=actor==='donor'?'recipient':'donor';assert.throws(()=>m.move(r.id,'handoff'),/not available/);assert.equal(r.handoff,at);assert.equal(r.handoffBy,actor);
 assert.doesNotMatch(m.activity(), /Confirm handoff/);assert.match(m.activity(),new RegExp('Handoff confirmed by '+actor));
}
console.log('PASS: either participant handoff for gifts/loans, attribution, role guards, duplicate prevention.');

// Completed gifts and returned loans omit requester copy for both participants.
for(const kind of ['gift','loan']){
 s=reset();s.evidence='reviewed';r=m.createRequest(kind==='gift'?1:3,{loanDays:14,consent:true});
 s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');m.move(r.id,'handoff');
 if(kind==='loan'){s.role='donor';m.move(r.id,'return');}
 for(const role of ['donor','recipient']){s.role=role;assert.doesNotMatch(m.activity(),/Requested by Maya/);}
}
console.log('PASS: completed item requester copy removed for donor and recipient.');

// Seven-day follow-up: exact deadline, delayed checks, no duplicate or automatic transfer.
for(const kind of ['gift','loan']){
 s=reset();s.evidence='reviewed';r=m.createRequest(kind==='gift'?1:3,{loanDays:14,consent:true});s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');
 const start=r.reserved;s.time=start+7*86400000-1;m.expire();assert.equal(s.cases.filter(c=>c.kind==='handoff_followup').length,0);
 s.time++;m.expire();const task=s.cases.find(c=>c.kind==='handoff_followup');assert.ok(task);assert.equal(task.requestId,r.id);assert.equal(task.due,start+7*86400000);assert.equal(r.state,'reserved');assert.equal(r.handoff,undefined);
 assert.match(m.followupContext(task),/Contact donor Jordan/);assert.match(m.followupContext(task),/Contact recipient Maya/);
 m.expire();s.time+=86400000;m.expire();assert.equal(s.cases.filter(c=>c.kind==='handoff_followup').length,1);
 task.state='closed';m.expire();assert.equal(s.cases.filter(c=>c.kind==='handoff_followup').length,1);
 m.move(r.id,'handoff');assert.match(m.followupContext(task),/has since been confirmed/);
}
for(const finish of ['handoff','cancel']){
 s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');m.move(r.id,finish);s.time+=8*86400000;m.expire();assert.equal(s.cases.filter(c=>c.kind==='handoff_followup').length,0);
}
s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.role='recipient';m.move(r.id,'accept');s.time+=10*86400000;m.expire();assert.equal(s.cases.filter(c=>c.kind==='handoff_followup').length,1);s.role='moderator';assert.match(m.moderator(),/Check unconfirmed handoff/);
console.log('PASS: seven-day follow-up deadline, deduplication, late checks, exclusions and current task context.');

// Expired recipient requests: retry requires reopened inventory; removal preserves history.
s=reset();r=m.createRequest(1);s.time+=48*3600000;m.expire();
assert.match(m.activity(),/Request Again/);assert.match(m.activity(),/Remove Request/);
assert.throws(()=>m.retryItem(r.id),/not available/);
m.removeExpiredRequest(r.id);assert.equal(s.requests.length,1);assert.equal(r.state,'expired');assert.doesNotMatch(m.activity(),/Remove Request/);assert.match(m.activity(),/Restore removed requests/);
s.role='donor';assert.match(m.activity(),/Expired/);assert.throws(()=>m.removeExpiredRequest(r.id),/Recipient access/);m.reopen(1,true);
s.role='recipient';m.restoreExpiredRequests();assert.match(m.activity(),/Remove Request/);assert.equal(m.retryItem(r.id),1);
const next=m.createRequest(m.retryItem(r.id));assert.notEqual(next.id,r.id);assert.equal(r.state,'expired');assert.throws(()=>m.retryItem(r.id),/not available/);assert.throws(()=>m.removeExpiredRequest(next.id),/Only expired/);
console.log('PASS: expired retry availability, soft removal, restore, history and role guards.');

// A successful repeat request replaces expired entries in the recipient list only.
s=reset();r=m.createRequest(1);s.time+=48*3600000;m.expire();
assert.throws(()=>m.createRequest(1),/no longer available/);assert.equal(r.hiddenForRecipient,undefined);
s.role='donor';m.reopen(1,true);s.role='recipient';const replacement=m.createRequest(1);
assert.equal(r.hiddenForRecipient,true);assert.equal(r.replacedBy,replacement.id);assert.equal(r.state,'expired');
assert.doesNotMatch(m.activity(),/Expired/);assert.match(m.activity(),/Pending/);
m.restoreExpiredRequests();assert.doesNotMatch(m.activity(),/Expired/);
s.role='donor';assert.match(m.activity(),/Expired/);assert.equal(s.requests.length,2);
console.log('PASS: successful re-request hides replaced expired entry, preserves history, and failed attempts leave it visible.');

// Pending donor detail status belongs directly beneath title, only once.
s=reset();r=m.createRequest(1);s.role='donor';
const pendingDetail=m.detail(1);
assert.match(pendingDetail,/Folding walker<\/h1><div class="note warn" role="status">This item is held for one requester\. New requests are closed\.<\/div>/);
assert.equal((pendingDetail.match(/New requests are closed/g)||[]).length,1);
assert.match(pendingDetail,/Approve & make offer/);
console.log('PASS: pending donor status directly below title without duplicate.');

// Expired pending requests offer owner-confirmed reopening on the detail page.
s=reset();r=m.createRequest(1);s.time+=48*3600000;m.expire();s.role='donor';
assert.equal(r.expiredFrom,'pending');assert.match(m.detail(1),/Folding walker<\/h1><section class="note warn" aria-label="Expired pending request"><strong>Pending Request Expired/);
assert.match(m.detail(1),/data-action="reopen" data-id="1">Confirm availability & make available again/);
assert.throws(()=>m.reopen(1,false),/confirmation/);m.reopen(1,true);assert.doesNotMatch(m.detail(1),/Pending Request Expired/);assert.equal(s.items[0].status,'available');
s=reset();r=m.createRequest(1);s.role='donor';m.move(r.id,'offer');s.time+=24*3600000;m.expire();assert.equal(r.expiredFrom,'offered');assert.doesNotMatch(m.detail(1),/Pending Request Expired/);
s=reset();r=m.createRequest(1);s.time+=48*3600000;m.expire();delete r.expiredFrom;s.role='donor';assert.match(m.detail(1),/Pending Request Expired/);s.items[0].hold=true;assert.throws(()=>m.reopen(1,true),/safety hold/);
console.log('PASS: pending-expiry message, legacy records, confirmation-gated reopening and offer-expiry distinction.');

s=reset();s.role='donor';assert.match(m.donate(),/Loan Until<input type="date"/);assert.match(m.donate(),/>New<\/option>/);assert.doesNotMatch(m.donate(),/Maximum loan days/);assert.equal(m.loanDaysUntil('2026-10-30'),14);assert.throws(()=>m.loanDaysUntil('2026-10-16'),/after/);assert.throws(()=>m.loanDaysUntil('2026-02-30'),/valid/);s.time+=86400000;assert.equal(m.loanDaysUntil('2026-10-30'),13);console.log('PASS: New condition, Loan Until picker and date validation.');

// Registration simulation: new/known mobiles, validation, OTP guards and saved destination.
s=reset();s.signed=false;assert.equal(m.beginAccess('donor',null,'(202) 555-0105'),undefined);
assert.throws(()=>m.prepareRegistration({mobile:'2025550105',displayName:' ',location:'Oakland'}),/display name/);
m.prepareRegistration({mobile:'2025550105',displayName:'Sam',location:'94612'});
assert.equal(s.registrationUsers.length,2);s.access.challenge={attempts:0,expires:2000,used:false};
assert.throws(()=>m.verifyRegistration('000000',1000),/Incorrect/);assert.equal(s.registrationUsers.length,2);
let reg=m.verifyRegistration('123456',1000);assert.equal(reg.role,'donor');assert.equal(reg.created,true);assert.equal(s.registrationProfile.displayName,'Sam');assert.equal(s.welcomePreviews.length,1);
assert.throws(()=>m.verifyRegistration('123456',1000),/expired/);
assert.ok(m.beginAccess('recipient',2,'+1 202 555 0105'));s.access.challenge={attempts:0,expires:2000,used:false};reg=m.verifyRegistration('123456',1000);assert.equal(reg.item,2);assert.equal(reg.created,false);assert.equal(s.registrationUsers.length,3);assert.equal(s.welcomePreviews.length,1);
m.beginAccess('recipient',1,'2025550106');m.prepareRegistration({mobile:'2025550106',displayName:'Lee',location:'Oakland'});s.access.challenge={attempts:0,expires:2000,used:false};assert.throws(()=>m.verifyRegistration('123456',2000),/expired/);
s.access.challenge={attempts:0,expires:2000,used:false};for(let j=0;j<3;j++)assert.throws(()=>m.verifyRegistration('000000',1000));assert.throws(()=>m.verifyRegistration('123456',1000),/invalidated/);assert.equal(s.registrationUsers.length,3);
console.log('PASS: registration validation, create only after OTP, known mobile reuse, one welcome preview, return intent, OTP expiry/three attempts/replay.');
