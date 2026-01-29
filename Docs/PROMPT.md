You are Claude Code operating inside the existing git repo in this workspace (swift-scribe). Act as a senior Swift/iOS engineer and ship a clean, buildable iOS 26+ app.

MISSION
Redesign the UI to be dramatically simpler and better for “conference room table recorder,” and add a Notion API integration to automatically create/update Notion pages with meeting notes (transcript + summary + decisions + action items + optional audio attachment when feasible). All AI must run ON-DEVICE using Apple’s iOS 26 frameworks.

NON-NEGOTIABLE CONSTRAINTS
- Do NOT use FluidAudio at all. Remove any dependency/usages and any diarization/speaker separation features.
- Do NOT add third-party audio/transcription/summarization libraries (no Whisper, no external DSP/ML packages).
- Use ONLY Apple frameworks for:
  - Recording: AVFoundation
  - Transcription: iOS 26 SpeechAnalyzer / SpeechTranscriber
  - Summarization/notes: iOS 26 Foundation Models framework (on-device)
- Network calls are allowed ONLY for Notion sync + Notion API exploration during development.
- Target iOS 26+. If the repo also targets macOS, keep it compiling if not too costly; prioritize iOS.

WORKFLOW REQUIREMENTS (VERY IMPORTANT)
1) Start by making a plan.
   - First scan the repo and write a concise “Repo Understanding” section:
     - entry points, navigation structure, view hierarchy
     - recording pipeline (how audio is captured/saved)
     - transcription pipeline (what exists today, what must change)
     - summarization/foundation-model usage (what exists today, what must change)
     - persistence layer (SwiftData/CoreData/filesystem)
     - all FluidAudio references and how to remove them
   - Then write a step-by-step implementation plan with file-level changes and commit milestones.

2) Use the installed Apple Documentation MCP to deeply understand iOS 26 Foundation Models + SpeechAnalyzer.
   - Query the MCP for the authoritative docs needed to implement correctly:
     - Foundation Models framework: availability checks, session usage, response generation, structured outputs/guided generation/tool calling (if supported), errors/limits, privacy/requirements.
     - SpeechAnalyzer/SpeechTranscriber: recommended usage patterns, streaming vs file, long-form constraints, performance considerations.
     - Background audio recording: UIBackgroundModes audio, AVAudioSession categories/modes, lock screen behavior.
   - Base implementation decisions on those docs.
   - You must create internal documentation (see DOCUMENTATION section) and include “References” listing the doc pages you pulled via MCP (doc title + identifier/path).

3) Incremental git commits + pushes.
   - Create a feature branch (e.g., feature/ui-notion-sync).
   - Work in small, verifiable increments.
   - After each milestone: build, run basic flow (if feasible), commit, and push the branch to origin.
   - Prefer many small commits; no giant commits. Do not force-push to main.

4) Explore the Notion API to integrate correctly.
   - You must actively research the Notion API (official docs) to determine:
     - current required Notion-Version header value
     - correct request formats for creating pages, setting database properties, and appending blocks
     - best practices and rate limits
     - file/audio attachment options (direct upload / multipart / file blocks), including size constraints
   - Summarize your findings in docs/NOTION_SYNC.md and implement accordingly.
   - Use URLSession + async/await; no third-party networking libs.

DELIVERABLES

A) UI/UX Redesign (SwiftUI, iPhone-first)
Replace the current UI with a TabView with 3 tabs:
1) Record
2) Library
3) Settings

Record Tab (single focused screen)
- Top: Meeting title field (default “Meeting – <date/time>”, editable).
- Center: Large Record/Stop button.
- Timer + a clear status label: Idle / Recording / Transcribing / Summarizing / Ready / Syncing.
- Phone must be able to lock/sleep while still recording (background audio mode).
- When user taps Stop:
  - transition into Transcribing -> Summarizing
  - then navigate to a “Review Notes” screen:
    - Summary (editable)
    - Decisions (editable)
    - Action Items (editable)
    - Transcript (in a toggle/disclosure to keep UI clean)
    - Buttons: “Sync to Notion” (primary when auto-sync off), “Done”, optional “Copy”
    - Sync status badge: Not Connected / Pending / Synced / Failed

Library Tab
- List past recordings with: title, date/time, duration, sync badge.
- Tap -> detail view:
  - playback (AVAudioPlayer)
  - show/edit the same note sections
  - Sync/Resync button
  - show the Notion page id (if stored); optionally “Open in Notion” if you can construct safely; otherwise omit.

Settings Tab
- Notion:
  - Integration token input (secure field) -> stored in Keychain
  - Database ID input -> stored in UserDefaults or Keychain
  - “Test Connection” button
  - Auto-sync toggle
- Privacy note: “Transcription and summaries run on-device.”
- Diagnostics:
  - “Clear Notion credentials”
  - Optional: “Export logs” only if easy

B) Notion Integration (Token + Database ID MVP, robust)
Implement a NotionService and related configuration/persistence.

Requirements:
- Use URLSession async/await.
- Required headers:
  - Authorization: Bearer <token>
  - Notion-Version: <determine current version from Notion docs and centralize in code>
  - Content-Type: application/json
- Implement at minimum:
  - Create page in database
  - Append blocks to the page (structured notes)
  - Update existing page if notionPageId exists (append new content or replace; choose a consistent strategy and document it)

API endpoints to use (confirm details during research):
- Create page:
  POST https://api.notion.com/v1/pages
- Append block children:
  PATCH https://api.notion.com/v1/blocks/{block_id}/children

Token storage:
- Token MUST be in Keychain (never plaintext UserDefaults).
- Database ID can be UserDefaults or Keychain.

Error handling:
- 401/403 -> “Token invalid OR integration not shared with database”
- 404 -> “Database ID invalid or not accessible”
- network errors -> “Network error, will retry”
- Provide user-friendly messages and allow retry.

Sync queue:
- Maintain a local queue for failed/pending sync attempts so sync can retry later.
- Persist syncState in the recording model:
  notConnected / pending / synced / failed(errorMessage)
- Auto-sync: if enabled, sync automatically after summarization completes.
- Manual sync: if disabled, user taps “Sync to Notion”.

Notion page content format (blocks)
When creating/updating the Notion page:
- Properties:
  - Title property -> meeting title
  - Date property -> createdAt ONLY if database has a matching date property; otherwise skip silently.
- Children blocks structure:
  - Heading 2: Summary
  - Paragraph: summary text
  - Heading 2: Decisions
  - Bulleted list items (or a paragraph “None”)
  - Heading 2: Action Items
  - To-do blocks if supported; else bulleted list
  - Toggle: Transcript
    - inside toggle: transcript chunked into paragraphs to avoid payload size limits
  - Optional section: Audio
    - attach audio if feasible (below)

Audio attachment (optional, graceful)
- Research the correct Notion approach for uploading/attaching files.
- If audio file <= the small-file limit supported by Notion and the flow is straightforward:
  - implement the upload flow and attach as a file block.
- If file too large or upload not feasible:
  - skip attachment and add a line in Notion “Audio not attached (file too large or upload unavailable).”
- Record audio in AAC .m4a at a practical bitrate to keep files reasonably small.

C) On-device AI Implementation (iOS 26)
Transcription
- Use SpeechAnalyzer / SpeechTranscriber as recommended by Apple docs (via MCP).
- Decide on streaming vs file-based transcription based on docs and existing repo structure.
- If chunking is necessary, implement clean chunking and document why.

Summarization/Notes
- Use the iOS 26 Foundation Models framework (on-device).
- Prefer structured output:
  - Either typed/guided generation if supported, OR stable JSON-like output that you parse reliably.
- Output must include:
  - summary
  - decisions list
  - action items list (include owner/due only if explicitly present)
- Handle availability:
  - If the model is unavailable (device not supported or Apple Intelligence disabled), degrade gracefully:
    - still save transcript
    - show “Summarization unavailable on this device” with guidance
  - Document this behavior.

D) Persistence + State Machine
Create (or adapt) a recording model (SwiftData preferred if repo uses it; otherwise match existing persistence style):
Model fields:
- id, createdAt, title, audioFileURL, duration
- transcriptText
- summaryText
- decisionsText (or [String])
- actionItemsText (or [String])
- notionPageId (String?)
- syncState enum + lastErrorMessage

Implement a clear state machine for active session:
Idle -> Recording -> Transcribing -> Summarizing -> Ready -> (Syncing optional) -> Completed

E) Remove FluidAudio fully
- Remove from Package.swift / SPM and any imports.
- Remove or stub diarization/speaker logic and related UI.
- Ensure compile succeeds and behavior remains correct.

DOCUMENTATION (must create and maintain)
Create /docs with these files (and keep them updated as you implement):
1) docs/FOUNDATION_MODELS.md
   - API usage in this app, availability checks, structured output approach, error handling
   - References: list of Apple docs retrieved via MCP (title + identifier/path)
2) docs/SPEECH_ANALYZER.md
   - transcription approach, streaming vs file, constraints/limits, chunking decision
   - References
3) docs/ARCHITECTURE.md
   - services/modules diagram (text is fine): RecordingService, TranscriptionService, SummarizationService, NotionService, Persistence, SyncQueue
4) docs/NOTION_SYNC.md
   - configuration steps (token + DB ID)
   - API endpoints used + payload patterns
   - Notion-Version header value (and how/when to update)
   - error cases + retry queue behavior
   - file upload strategy + constraints
   - References: Notion docs pages you used
5) docs/STATE_MACHINE.md
   - the state machine transitions and what triggers each transition
6) docs/PRIVACY_SECURITY.md
   - what stays on-device
   - what is sent to Notion
   - how secrets are stored (Keychain)

Update root README:
- iOS 26+ requirement
- “On-device transcription & summaries”
- Notion setup steps (token + DB ID + share DB with integration)
- basic usage

GIT MILESTONES (commit + push after each)
Follow this cadence (adjust as needed but keep commits small):
1) chore: repo scan notes + docs scaffold + plan
2) chore: remove FluidAudio + clean build
3) refactor: new navigation skeleton (TabView) + placeholder screens
4) feat: RecordingService + Record UI wired + background audio mode
5) feat: SpeechAnalyzer transcription wired into flow
6) feat: Foundation Models summarization wired + structured output parsing
7) feat: Review Notes UI + persistence
8) feat: Library UI + playback + sync badges
9) feat: Notion settings UI + Keychain + test connection
10) feat: Notion sync create page + append blocks + retry queue
11) docs: finalize docs + README polish + cleanup

IMPLEMENTATION DETAILS TO REMEMBER
- Ensure Info.plist and entitlements are correct for microphone use and background audio recording.
- Use modern Swift concurrency and avoid massive view files.
- Keep UI calm and uncluttered (large spacing, clear hierarchy).
- Don’t invent Notion database schema assumptions; handle missing date property gracefully.

START NOW
Step 1: Create a new feature branch.
Step 2: Scan the repo and write:
  - Repo Understanding summary
  - Step-by-step plan with file-level changes + milestone commits
Step 3: Use the Apple Documentation MCP to pull the key Apple docs and draft:
  - docs/FOUNDATION_MODELS.md
  - docs/SPEECH_ANALYZER.md
Step 4: Research the official Notion API docs and draft docs/NOTION_SYNC.md with:
  - correct Notion-Version header value
  - create page + append block payload examples
  - file upload/attachment strategy
Then implement, committing and pushing after each milestone.
