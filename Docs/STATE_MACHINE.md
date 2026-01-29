# State Machine

## Session States

```
┌──────┐   Record    ┌───────────┐   Stop     ┌──────────────┐
│ Idle │────────────>│ Recording │──────────>│ Transcribing  │
└──────┘             └───────────┘            └──────┬───────┘
   ^                                                  │
   │                                                  │ done
   │                                                  ▼
   │                                          ┌──────────────┐
   │                                          │ Summarizing   │
   │                                          └──────┬───────┘
   │                                                  │
   │                                  ┌───────────────┤
   │                                  │ success       │ unavailable
   │                                  ▼               ▼
   │                           ┌──────────┐   ┌──────────┐
   │                           │  Ready    │   │  Ready   │
   │                           │(with AI)  │   │(no AI)   │
   │                           └────┬─────┘   └────┬─────┘
   │                                │               │
   │                    ┌───────────┤               │
   │                    │ sync      │ done          │ done
   │                    ▼           │               │
   │              ┌──────────┐     │               │
   │              │ Syncing   │     │               │
   │              └────┬─────┘     │               │
   │                   │           │               │
   │         ┌─────────┤           │               │
   │         │ ok      │ fail      │               │
   │         ▼         ▼           │               │
   │   ┌──────────┐ ┌────────┐   │               │
   │   │Completed │ │ Failed  │   │               │
   │   │(synced)  │ │(retry?) │   │               │
   │   └────┬─────┘ └────┬───┘   │               │
   │        │             │       │               │
   └────────┴─────────────┴───────┴───────────────┘
                     (all -> Idle on new recording)
```

## State Enum

```swift
enum SessionState: String, Codable {
    case idle
    case recording
    case transcribing
    case summarizing
    case ready
    case syncing
    case completed
}
```

## Transitions

| From | To | Trigger |
|------|----|---------|
| `idle` | `recording` | User taps Record |
| `recording` | `transcribing` | User taps Stop -> finalize audio |
| `transcribing` | `summarizing` | Transcript text finalized |
| `summarizing` | `ready` | AI notes generated (or skipped if unavailable) |
| `ready` | `syncing` | User taps "Sync to Notion" or auto-sync |
| `ready` | `completed` | User taps "Done" (no sync) |
| `syncing` | `completed` | Sync succeeds |
| `syncing` | `ready` | Sync fails (syncState set to .failed) |
| any | `idle` | User starts a new recording |

## Sync State (Separate from Session State)

```swift
enum SyncState: String, Codable {
    case notConnected  // No Notion credentials configured
    case pending       // Queued for sync
    case synced        // Successfully synced
    case failed        // Sync failed (see lastSyncError)
}
```

The sync state is persisted on each MemoModel and is independent of the session state. A memo can be in `completed` session state with any sync state.

## UI Status Labels

| Session State | Status Label |
|---------------|-------------|
| `idle` | "Ready to Record" |
| `recording` | "Recording... 00:00" (with timer) |
| `transcribing` | "Transcribing..." |
| `summarizing` | "Generating Notes..." |
| `ready` | "Notes Ready" |
| `syncing` | "Syncing to Notion..." |
| `completed` | "Done" |
