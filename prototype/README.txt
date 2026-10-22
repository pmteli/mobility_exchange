FreeDME Interactive Design Prototype v0.1
Requirements baseline: FreeDME Requirements and Website Verification v0.9.docx
Created: 16 October 2026

OPEN
Open "FreeDME Interactive Prototype v0.1.html" in a browser. No installation or server required. All illustrations and code are embedded. The dist folder contains the editable HTML/CSS/JavaScript version.

REVIEW JOURNEYS
1. Recipient: select Review controls > Recipient / caregiver. Send sample code; enter 123456. Browse equipment and request the folding walker.
2. Donor: switch sample role; sign in with 123456. In My activity, make an offer.
3. Recipient: switch back, accept the offer to reserve. Reservation is separate from physical handoff.
4. Donor: confirm handoff. For a loan, subsequently confirm return.
5. Donor: Donate equipment > Fill sample details. Complete acknowledgments and submit.
6. Moderator: Review controls > Moderator > Enter sample staff workspace. Screen submitted equipment, record recall outcome and decision, and manage sample incident cases.
7. Loans: request a sample loan, use simulated evidence review and separately consent to named-donor disclosure. Originals are never shown to the donor.
8. Exceptions: use Review controls to advance 24/48 hours, simulate delivery failure or revoke evidence. Try cancellation and possession-confirmed reopening. Reset sample data to start again.

REQUIREMENT TRACE / REPRESENTATIVE DESIGN COVERAGE
UJ001-UJ005: browsing, submission/review, request/offer/reservation and exception journeys represented across the three sample roles.
FR023: one active request holds the item; offer and recipient acceptance are distinct.
FR024: pending reminder at 24 hours, closure at 48 hours; offer expiry at 24 hours.
FR025: cancellation/expiry do not automatically reopen the listing; possession confirmation and safety checks gate reopening.
FR036: all role, time, OTP and evidence controls are labeled design-only and must be removed from production.
FR038-FR040: sample recall review, participant acknowledgments and issue-handling screens illustrate risk controls. This is not a live recall check or legal-policy implementation.
OR001-OR003: separate reservation/handoff/return outcomes and support-case views illustrate operations; actual staffing, resource verification and launch readiness are not implemented.
DEC01-DEC06: remain unresolved and are listed on the Design decisions page. Loan examples, day limits, locations and equipment configurations are illustrative, not approved policy.

SCOPE AND LIMITATIONS
Fictional equipment, names, addresses, phone numbers, evidence and distances only. Do not enter real personal information. Data stays in this browser's local storage (or memory if storage is unavailable). Sessions are not synchronized between browsers or users. Share the HTML file, not a local file URL, with reviewers; each reviewer has a separate session.
This is a representative interaction prototype, not a full PRS implementation or production launch candidate. No backend, PostgreSQL connection, secure authentication/authorization, real OTP/SMS, uploads, address verification, map/geolocation, real recall lookup, rate limiting, data retention/deletion system or live support service is provided. No real exchanges or messages occur. Pending/offer expiry and seven-day unconfirmed-handoff follow-ups use the simulated clock; other schedules remain out of scope. Sample photo choices replace real uploads. Resources are unverified placeholders.
Role controls and local storage are deliberately inspectable. They provide no security boundary. Do not deploy this prototype as the production service.

VALIDATION
Node state-machine checks: node prototype/test.cjs (run from project root).
Passed gift and loan lifecycle, role gating, duplicate-active-request rejection, exact expiry boundaries, consent revocation, cancellation, possession confirmation, safety hold and delivery-pause checks.
Browser walkthrough passed recipient request > donor offer > recipient reservation; donor submission into review; moderator blocked unsafe publication and recorded corrections. Activity layout checked at 320px without horizontal overflow. These checks do not constitute a full accessibility, security or compliance audit.

USER DESIGN UPDATE — 18 October 2026
Reserved recipients now see the donor's fictional mobile number and instructions to contact the donor directly for pickup location and time. This explicit user decision adds direct contact after reservation alongside the historical FR009 platform SMS design; it does not implement real messaging or resolve the remaining DEC05 messaging policies. Public, nonresidential daytime pickup guidance is retained (FR039). Contact is hidden before acceptance, after cancellation, and during a messaging/security pause or safety hold. No PRS document was amended by this prototype change.

USER DESIGN UPDATE — 18 October 2026
Recipient self-service disclosure consent revocation is available only before loan handoff (pending, offered or reserved). After equipment is loaned, the control is hidden and the action rejects stale attempts. It stays unavailable after return. This explicit user decision updates the prototype; staff evidence/security invalidation controls remain separate. The PRS file has not been edited.

USER DESIGN UPDATE — 18 October 2026
Either the donor or recipient may confirm handoff after reservation. A single participant confirmation completes a gift or moves a loan to loaned; it does not require both parties. The prototype records the confirming role and timestamp and rejects duplicate confirmation. Existing records without a confirming role are shown as donor-confirmed because earlier versions only allowed donors. Moderator metrics now say participant-confirmed handoffs. This explicit user decision supersedes donor-only confirmation in the prototype; the PRS document remains unchanged.

USER DESIGN UPDATE — 18 October 2026
FR024/FR025 extension: after seven elapsed days from recipient reservation, an item still reserved without handoff confirmation creates one moderator task per reservation. It asks staff to contact both donor and recipient, check actual handoff, and record both responses/outcome. No automatic transfer or reopening occurs. Repeated checks do not duplicate or recreate a closed task. Tasks show current reservation/handoff status so staff can review later changes. Use Review controls > Advance 7 days to test. This browser-only prototype evaluates the rule on reads/mutations using the sample clock; a production scheduled worker is not implemented. The user has resolved this specific follow-up interval; other open timing decisions remain unresolved. The PRS document is unchanged.

USER DESIGN UPDATE — 19 October 2026
Equipment listing form: added New condition; replaced Maximum loan days with Loan Until native date selection (day, month, year). Required only for loans, validated after the current sample date. New dated listings show the end date and derive the request limit from it; historical sample listings retain their existing day limits. Explicit user decision extends the PRS listing workflow; PRS document remains unchanged.

USER DESIGN UPDATE — 19 October 2026
PRS section 9 and FR037: home hero headline uses container-relative font sizing and no wrapping. Verified one line without overflow at widths 320, 390, 700, 768 and 1440 CSS pixels.

USER DESIGN UPDATE — 21 October 2026
Registration simulation (PRS FR003, FR026–FR027 and section 9; subsequent user decision): Donate/Request checks a fictional mobile against a browser-local registry. Unknown mobile opens a three-field registration form (display name, approximate ZIP/town and mobile), followed by sample OTP verification. Only successful verification creates the local record and one simulated welcome message, then resumes the original donate/request journey. Existing mobile skips the registration form. No backend account or SMS is created. Sample roles and equipment remain shared demonstration data, not isolated accounts.
To test: Review controls > Sign out to try registration, then Donate Equipment or request an available item. Use 202-555-0100 through 202-555-0199 and OTP 123456. Known sample numbers: 510-555-0100 and 510-555-0101. View the welcome message under Review controls. Do not enter real personal information. Ten-minute expiry and three attempts are illustrative, not resolved production policies.
Validation: new/known user, invalid details/code, expiry, attempt limit, replay prevention, single welcome, and saved request intent tests passed. Browser donor registration returned to the donation form with location prefilled; returning recipient verification reopened the intended request dialog. Live donor registration was verified after deployment.

USER DESIGN UPDATE — 21 October 2026
Added Other equipment category at user request, extending FR004 donation submission and FR007 category filters beyond the original six-category scope. Existing moderator screening remains required (FR006/FR038). Added generic sample imagery for Other; updated homepage category count wording. PRS file unchanged; remaining DEC02 configuration decisions remain open. Existing automated checks passed; live donation menu verified.

USER DESIGN UPDATE — 21 October 2026
FR004 donation form: replaced Condition uncertain with Requires Repairs in the condition dropdown at user request. Historical sample record condition is preserved. This label change does not relax FR006/FR038 moderator screening or safety-critical defect restrictions. PRS document unchanged. Verified live dropdown and byte-for-byte deployed app.js.

USER DESIGN UPDATE — 21 October 2026
FR004: new donations replace missing-parts/defects text entry with mandatory No missing parts or defects confirmation, recorded as donor-reported. Existing listing edit disclosures are preserved. Browser required validation and submit handler both enforce confirmation. Live unchecked field verified required/valueMissing. Requires Repairs remains per prior user request; its conflict with the mandatory no-defects assertion remains an open wording/policy decision. PRS unchanged.

USER DESIGN UPDATE — 21 October 2026
User resolved the prior confirmation/condition wording conflict: new donation checkbox now requires No known missing parts; Requires Repairs remains available. Validation and newly recorded donor confirmation use the revised wording. Existing historical declarations remain intact.

USER DESIGN UPDATE — 21 October 2026
FR009/FR018 inquiry preview: available item details include Ask A Question beside the request action. Required 1–500-character question is saved against the listing, without creating a request or reservation. Donor My Activity shows pending questions and a Mark reviewed action. Generic SMS notification preview excludes question content; routine-SMS opt-out suppresses it. Actual delivery, verified participant isolation, donor replies, retry workers and delivery failure recovery are not implemented. All questions remain browser-local fictional data; visitor submissions are labeled Interested recipient in this simulation. Other FR009/FR018 requirements remain unimplemented. PRS unchanged.
Checks passed: empty/oversized question rejection, safety hold, notification opt-out, no reservation creation, donor question display. Live browser walkthrough submitted a sample question and verified it in donor My Activity.

USER DESIGN UPDATE — 21 October 2026
FR009/FR018, explicit user extension: donor pending questions now offer Answer, opening the question and required answer textarea. Saving records an answer/time, removes it from pending, and creates a generic recipient SMS preview (suppressed if routine texts are off). Recipient My Activity has Questions & Answers with pending/answered status and timestamps. Previously reviewed unanswered questions reappear in pending. No actual SMS, delivery retries or per-account data isolation: shared fictional recipient/donor roles remain. This user-requested Q&A display does not implement a delivery-failure conversation fallback. PRS unchanged.
Validation passed: donor role guard, empty answer, duplicate answer, pending removal, recipient history, opt-out. Live browser verified popup, saved answer and recipient display.

21 October 2026: equipment titles in donor equipment/request/pending-question sections and recipient request/Q&A sections now link to item details (FR008 navigation). Existing listing access restrictions remain. Live navigation verified.

21 October 2026 — FR009 inquiry preview: recipient Q&A cards include Ask Another Question for the same equipment. Each submission creates a separate question ID, pending state and independent answer history; prior answers remain intact. History refreshes immediately after submission. Existing availability/hold restrictions apply. Verified independent IDs/statuses/answers locally and live Q1 Answered alongside Q2 Awaiting answer.

21 October 2026: recipient Q&A grouped by equipment ID under one linked title, with one Ask Another Question button per equipment. Individual question IDs, statuses, timestamps and answers remain separate. Multi-item grouping checks and live two-question rendering passed (FR009 display refinement).

21 October 2026: donor My Activity uses Material-style primary tabs: Pending Questions, Your Equipment, Requests & Handoffs. Accessible tab/tabpanel associations, roving tab stops, Arrow/Home/End selection, active indicator and horizontally scrollable narrow-screen tab bar. Selected tab survives in-page renders/navigation until reload. Recipient layout unchanged. Design reference: https://github.com/material-components/material-web/blob/main/docs/components/tabs.md . Custom lightweight implementation, not a bundled Material Web component. Live all-three-panel switching and arrow-key navigation verified.

21 October 2026: Equipment-list card status labels now have transparent backgrounds and regular 400 weight, reduced by 2pt from 12pt (16px) to 10pt. Uppercase retained. Supersedes Section 9 badge styling for equipment-list cards only (FR008/FR045). Local and live computed styles verified; remote stylesheet SHA256 matches local. Backup: /home/ubuntu/freedme-demo/style-before-list-labels.css.

21 October 2026: Removed distance information from equipment cards and detail pages, including sample-distance filter, filter predicate and distance explanatory text. Town/location remains. Explicit user revision to FR007/FR008 distance presentation; no geocoding added. Live browse and detail verified; remote JS/CSS hashes match local. Backups: app.js.before-remove-distance and style.css.before-remove-distance in /home/ubuntu/freedme-demo.

21 October 2026: Removed Equipment price/$0 display from shared gift and loan details. No other equipment-price amounts/fields found in runtime pages. Free to keep / Free loan labels retained. User-directed presentation exception to FR001/FR008; free-exchange policy unchanged. Live details and remote/local app.js hash verified. Backup: /home/ubuntu/freedme-demo/app-before-remove-price.js.

21 October 2026: Removed the gift identity/address-document sentence from demo details; checked runtime pages for other occurrences. Copy-only change; verification workflow unchanged. Live text and remote/local app.js hashes verified. Backup: /home/ubuntu/freedme-demo/app-before-gift-copy.js.

21 October 2026: Loan equipment badges show Loan Until with formatted calendar date instead of maximum days (FR008/FR020). Uses stored donor date; sample wheelchair/crutches assigned fixed fictional dates Oct 30/23 2026, including matching older sample records on load. Other undated legacy entries show Date not specified. Request duration and existing handoff remaining-period fields unchanged. Local rendering checks and live list/detail verified; deployed source hash matches. Backup: /home/ubuntu/freedme-demo/app-before-loan-until-label.js.

21 October 2026: Loan badge wording simplified to FREE LOAN: UNTIL Oct 30, 2026 (stored calendar date). Date capitalization preserved. Live exact wording verified; remote files match local. Backups: app-before-loan-label-copy.js and style-before-loan-label-copy.css.

21 October 2026: Donor pending requests in Requests & Handoffs now use Approve, Decline and Unavailable action labels; Report an issue removed from these pending donor entries. Existing action behavior and other reporting paths retained. Local donor/recipient rendering checks pass; remote JS hash matches local. Backup: app-before-pending-actions.js.

21 October 2026: Approve now opens optional handoff day/time/public-location form (FR010/FR018/FR023). All three fields required if any supplied; valid future Pacific-local date/time and 200-character location limit. Saved on offered request; visible to donor/recipient while offered/reserved unless paused/held. Approval creates generic simulated SMS preview with no exact location/time; opt-out suppresses notice. No real SMS. Recipient acceptance still required; suggestion is not appointment confirmation. Checks passed for optional/incomplete/past inputs, duplicate approval, escaped location, recipient offered/reserved rendering and opt-out. Live donor form submission and recipient suggestion/SMS preview verified. Backup: /home/ubuntu/freedme-demo/app-before-handoff-suggestion.js.

21 October 2026: Recipient reserved Requests & Offers entries no longer display donor mobile or direct phone/text instruction. Removed obsolete sample-number warning. Suggested handoff, donor name and pickup safety copy retained. User-directed presentation revision to FR010. Local reserved rendering and live reserved view verified; remote/local JS hashes match. Backup: app-before-reserved-mobile-removal.js.

2026-10-21: Handoff negotiation (FR010, FR018, FR023; explicit user revision). Recipient accepts or counters donor meeting suggestions using prefilled day/time/location fields. Donor confirms or counters; changed arrangements require renewed agreement. Proposal snapshots and simulated SMS previews are retained. Stale revisions, own/duplicate acceptance, invalid/past dates, paused/closed exchanges are blocked. Meeting agreement does not confirm physical handoff or reset offer deadlines. Local checks and live recipient counterproposal/donor confirmation verified.
