# Architecture

## Module Diagram

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐            │
│  │ RecordTab │  │LibraryTab│  │ SettingsTab │            │
│  └────┬─────┘  └────┬─────┘  └──────┬─────┘            │
│       │              │               │                   │
│  ┌────▼─────┐  ┌────▼──────┐        │                   │
│  │ReviewNotes│  │MemoDetail │        │                   │
│  └────┬─────┘  └────┬──────┘        │                   │
└───────┼──────────────┼───────────────┼───────────────────┘
        │              │               │
┌───────▼──────────────▼───────────────▼───────────────────┐
│                     Services Layer                        │
│                                                           │
│  ┌──────────────────┐  ┌─────────────────────┐           │
│  │ RecordingService  │  │TranscriptionService │           │
│  │ (AVAudioEngine)   │──│ (SpeechAnalyzer)    │           │
│  └──────────────────┘  └─────────────────────┘           │
│                                                           │
│  ┌──────────────────────┐  ┌──────────────────┐          │
│  │SummarizationService  │  │  NotionService    │          │
│  │(Foundation Models)    │  │  (URLSession)     │          │
│  └──────────────────────┘  └──────────────────┘          │
│                                                           │
│  ┌──────────────────┐                                     │
│  │  SyncQueue        │                                    │
│  │  (retry logic)    │                                    │
│  └──────────────────┘                                     │
└───────────────────────────────────────────────────────────┘
        │
┌───────▼───────────────────────────────────────────────────┐
│                   Persistence Layer                        │
│                                                            │
│  ┌─────────────┐  ┌───────────────┐  ┌────────────────┐  │
│  │  MemoModel   │  │ KeychainHelper│  │  AppSettings   │  │
│  │  (SwiftData)  │  │ (Security)    │  │ (UserDefaults) │  │
│  └─────────────┘  └───────────────┘  └────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Services

### RecordingService
- **Framework**: AVFoundation
- **Responsibility**: Manage AVAudioEngine, capture audio buffers, write to .m4a file
- **Key**: Configures AVAudioSession for background recording, manages audio lifecycle

### TranscriptionService
- **Framework**: Speech (SpeechAnalyzer + SpeechTranscriber)
- **Responsibility**: Stream audio buffers to SpeechAnalyzer, yield finalized + volatile transcription results
- **Key**: Handles locale selection, format conversion, model availability

### SummarizationService
- **Framework**: FoundationModels
- **Responsibility**: Generate meeting notes (summary, decisions, action items) from transcript text
- **Key**: Uses @Generable for structured output, handles unavailability gracefully

### NotionService
- **Framework**: URLSession (Foundation)
- **Responsibility**: Create/update Notion pages, upload audio files, manage API communication
- **Key**: Handles authentication, rate limiting, error mapping

### SyncQueue
- **Responsibility**: Queue failed/pending sync operations, retry with exponential backoff
- **Key**: Persists in SwiftData via MemoModel.syncState, survives app restart

## Persistence

### MemoModel (SwiftData)
Primary data model with fields:
- id, createdAt, title, audioFileURL, duration
- transcriptText, summaryText, decisionsText, actionItemsText
- notionPageId, syncState, lastSyncError
- sessionState (state machine)

### KeychainHelper
- Stores Notion integration token securely
- Uses Security framework (kSecClassGenericPassword)

### AppSettings (@Observable + UserDefaults)
- Notion database ID
- Auto-sync toggle
- Theme preference

## Data Flow

### Recording Flow
```
User taps Record
  -> RecordingService.startRecording()
  -> AVAudioEngine captures buffers
  -> Buffers written to .m4a file (AAC 64kbps)
  -> Buffers forwarded to TranscriptionService
  -> TranscriptionService streams to SpeechAnalyzer
  -> UI shows live transcript (finalized + volatile text)

User taps Stop
  -> RecordingService.stopRecording()
  -> TranscriptionService.stop() - finalizes analysis
  -> SummarizationService.generateMeetingNotes()
    -> @Generable MeetingNotes for structured output
  -> MemoModel updated with transcript + AI notes
  -> Navigate to ReviewNotesView
  -> (If auto-sync enabled) -> NotionService.syncMemo()
```

### Sync Flow
```
User taps "Sync to Notion" (or auto-sync triggers)
  -> NotionService.syncMemo(memo)
  -> If no notionPageId: createPage() with full content
  -> If has notionPageId: appendBlocks() with update
  -> On success: memo.syncState = .synced, store notionPageId
  -> On failure: memo.syncState = .failed, store lastSyncError
```
