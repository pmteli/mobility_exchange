# Actual Rails journey recordings

These recordings operate the real Rails forms/controllers/models in a separate development instance at http://127.0.0.1:3002. The ordinary application at port 3001 and its database are not used.

## Isolation

- Compose project: `freedme-recording`; database: `freedme_recording_demo`.
- Uses existing local PostgreSQL network with a separately owned database.
- `FREEDME_RECORDING_MODE=true` is allowed only in development. AWS SDK responses are stubbed. No AWS credential directory is mounted.
- SMS uses the existing simulated gateway and records messages in the recording database.
- Evidence is a generated fictional PNG. Do not use real identity documents.
- The recording app shows a permanent sandbox banner. Video captions identify role switches and controlled clock changes.
- `clock.rb` refuses to run unless the connected database is exactly `freedme_recording_demo` and recording mode is enabled. It advances the Ruby clock for deadline processing, or passes a future timestamp to the database follow-up function. It never rewrites immutable transaction timestamps. Deadline processing may affect other due fixtures in this isolated database.

## Run

1. Build the local Rails image using the existing local Compose files.
2. Create `freedme_recording_demo` owned by `freedme_framework` on the local PG container (requires the container's database admin).
3. Start `docker compose -f compose.recording.yml up -d`. Startup migrates and seeds this dedicated database.
4. Run `node script/recordings/run.cjs` with Playwright available. The script currently defaults to the bundled Codex Playwright path and installed macOS Chrome; set `PLAYWRIGHT_MODULE` to another installed package if needed. Install Playwright's ffmpeg encoder before recording.
5. Output is written to `../output/rails-demo`; final videos are listed in `manifest.json`. Raw/interrupted clips are not part of the gallery.
6. Use `ONLY=06-questions,07-listing` to resume specific scenarios on an appropriate prepared fixture state. Completed scenarios should not be rerun against their completed transactions. For a full clean run, stop this Compose project and recreate **only** `freedme_recording_demo`; never reset the regular development database.

Every role switch clears browser cookies and performs the real mobile-number and simulated OTP sign-in flow. No authenticated sessions are reused. The recording-only prepare_sign_in.rb ages consumed OTP challenges in the isolated database to avoid waiting for demonstration rate limits; it leaves unconsumed challenges and production authentication unchanged. The UI still generates and verifies a fresh OTP for each sign-in. Sign-in completion is asserted and recorded in each video's manifest entry.

Traceability: PRS v0.10 FR003, FR004–006, FR018, FR021–025, FR043–045, plus explicit subsequent user decisions. Unresolved policy choices remain unresolved. These videos are demonstrations, not production acceptance or launch approval.

## Review package

Run `python3 script/recordings/build_gallery.py` after all recordings finish, then start/recreate the recording Compose service to mount the output folder. Open http://127.0.0.1:3002/recordings/index.html. Run `docker compose -f compose.recording.yml exec -T web bin/rails runner - < script/recordings/verify.rb` to check the expected database outcomes. Final MP4s, posters and gallery may be shared together; exclude raw/interrupted recordings and failure screenshots. See REVIEW-NOTES.txt in the output for observed workflow discrepancies.

Role changes: the review gallery pauses existing recordings for three seconds and displays a role notice using role-cues.json. These player overlays also work in the offline gallery; standalone original MP4s do not contain the overlays. Future recordings include the role pop-up directly and mark roleNoticesEmbedded in the manifest to prevent duplicate player notices.

Cursor tracking: cursor.js is injected only into the automated recording browser. It follows actual pointer events, adds a yellow halo and shows orange click ripples without intercepting input. The runner moves the pointer smoothly to controls before acting. Set RECORDING_OUTPUT to stage a new set of videos without replacing the current review library. No cursor code is added to the ordinary Rails application.

The add-equipment scenario uploads accepted-front.png and accepted-detail.png (rendered from the existing equipment illustrations), followed by rejected-non-equipment.png (the logo). The recording-only initializer returns a rejected result for the sanitized logo digest in the isolated database. The script asserts two accepted results, one rejection, blocked submission, and removal of the rejected photo before submission. Normal application moderation is unchanged.


Narration: extract_narration_timing.py reads the visible recorded captions with local Tesseract; narration-text.json contains the reviewed spoken wording. add_narration.py synthesizes the phrases locally using macOS Samantha, schedules non-overlapping speech near each action, and muxes AAC audio while copying the video stream unchanged. Output is staged in output/rails-demo-narrated with WebVTT captions and plain-text transcripts. Run timing extraction again after re-recording any video; review skipped cues and timing before publishing. No external speech service receives the video or text.

Scenario 12 extends the reserved walking-cane arrangement from scenario 02. It shows both participants' agreed pickup, advances the isolated clock to meeting_at + 24 hours, invokes the real follow-up service twice to verify deduplication, displays the recipient's simulated SMS, and follows its short link. It does not simulate an incoming YES/NO response or imply reply processing is implemented. Existing videos are retained. Traceability: FR018/FR027 plus the explicit 24-hour-after-pickup decision of 2 November 2026.
