# Codebase Analysis Report

This document contains findings from a comprehensive analysis of the Swift Scribe codebase.

## Executive Summary

Swift Scribe is a well-architected iOS 26+ meeting recorder with on-device AI capabilities. The codebase demonstrates good use of modern Swift features (actors, async/await, SwiftData, @Observable). However, several issues were identified that should be addressed to improve reliability, user experience, and maintainability.

**Key Findings:**
- 3 high-priority bugs/issues
- 5 medium-priority improvements needed
- 4 lower-priority enhancements recommended

---

## 1. High Priority Issues

### 1.1 TranscriptionService Cannot Be Reused

**Location:** `Scribe/Services/TranscriptionService.swift:27-31`

**Problem:** The `AsyncStream<AnalyzerInput>` is created in `init()` and can only be consumed once. After `stop()` is called, the continuation is finished and subsequent calls to `start()` will fail silently or throw errors.

**Impact:** If a user records multiple meetings without restarting the app, only the first recording will have transcription.

**Fix:** Recreate the stream and continuation in `start()` rather than in `init()`.

```swift
// Current (broken for reuse)
init() {
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    self.inputSequence = stream
    self.inputBuilder = continuation
}

// Fixed
func start() async throws {
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    self.inputSequence = stream
    self.inputBuilder = continuation
    // ... rest of setup
}
```

### 1.2 Auto-Sync Feature Not Implemented

**Location:** `Scribe/Views/SettingsTab.swift:119-123` (toggle definition) and `Scribe/Views/RecordTab.swift:206-234` (where it should be used)

**Problem:** The `NotionSettings.autoSync` toggle exists in the UI and persists to UserDefaults, but the actual auto-sync functionality is never implemented. After a recording finishes, the code never checks this setting.

**Impact:** Users who enable auto-sync expect their notes to sync automatically, but nothing happens.

**Fix:** Add auto-sync logic after AI enhancement completes in `RecordTab.stopRecording()`.

### 1.3 SyncState Enum Duplication

**Location:**
- `Scribe/Views/LibraryTab.swift:102-107`
- `Scribe/Models/MemoModel.swift:33-36` (uses it via `syncStateRaw`)

**Problem:** `SyncState` enum is defined in `LibraryTab.swift` but used by `MemoModel`. This works due to Swift's module system, but it's poor organization and could cause issues if the files are refactored.

**Impact:** Code maintainability issue; could cause compilation errors during refactoring.

**Fix:** Move `SyncState` to a dedicated file in the Models folder or into `MemoModel.swift`.

---

## 2. Medium Priority Issues

### 2.1 BufferConverter Thread Safety

**Location:** `Scribe/Helpers/BufferConversion.swift:12`

**Problem:** `BufferConverter` is a `class` with mutable state (`private var converter: AVAudioConverter?`) that can be accessed from the audio tap callback thread. This is a potential data race.

**Impact:** Potential crashes or audio corruption under certain timing conditions.

**Fix:** Convert `BufferConverter` to an actor, or use `OSAllocatedUnfairLock` to protect the `converter` property.

### 2.2 Missing Error UI for Playback Failures

**Location:** `Scribe/Views/LibraryTab.swift:256-260`

**Problem:** Playback errors are only logged with `print()`, not shown to the user.

```swift
} catch {
    print("Playback error: \(error)")  // User never sees this
}
```

**Impact:** Users don't know why playback failed; poor UX.

**Fix:** Add an `@State` error message and show an alert when playback fails.

### 2.3 No Delete Confirmation

**Location:** `Scribe/Views/LibraryTab.swift:47-50`

**Problem:** Swipe-to-delete immediately removes recordings without confirmation.

**Impact:** Users can accidentally delete important recordings with no way to recover.

**Fix:** Add a confirmation alert before deletion.

### 2.4 Inefficient Recording Timer

**Location:** `Scribe/Views/RecordTab.swift:154`

**Problem:** Timer fires every 100ms (0.1 seconds) but the UI only shows MM:SS format.

**Impact:** Unnecessary CPU usage; 10x more timer events than needed.

**Fix:** Change interval to 1.0 seconds. The timer is only used to update the display, not for accurate duration tracking (which uses `recordingStartTime`).

### 2.5 Missing Loading State in NotionSettingsView

**Location:** `Scribe/Views/SettingsTab.swift:321-326`

**Problem:** When the view appears and databases are loaded, there's no loading indicator shown initially.

**Impact:** Users may think the app is frozen while databases load.

**Fix:** Show loading state when `isLoadingDatabases` is true and the view first appears.

---

## 3. Lower Priority Issues

### 3.1 Accessibility Labels Missing

**Location:** Throughout all view files

**Problem:** Buttons and controls lack `accessibilityLabel` and `accessibilityHint` modifiers.

**Impact:** VoiceOver users cannot effectively use the app.

**Fix:** Add accessibility modifiers to all interactive elements:
- Record button: "Record meeting" / "Tap to start recording"
- Stop button: "Stop recording" / "Tap to stop and process"
- Sync button: "Sync to Notion" / "Tap to upload notes to Notion"

### 3.2 Unused Helper Code

**Location:** `Scribe/Helpers/FoundationModelsHelper.swift`

**Problem:** The entire `FoundationModelsHelper` class and `FoundationModelsSessionManager` class are never used. `SummarizationService` implements its own logic directly.

**Impact:** Dead code increases maintenance burden.

**Fix:** Either:
1. Delete the unused code, or
2. Refactor `SummarizationService` to use `FoundationModelsHelper`

### 3.3 Legacy/Unused Methods in MemoModel

**Location:** `Scribe/Models/MemoModel.swift:133-159`

**Problem:** `textBrokenUpByParagraphs()` and possibly `blank()` appear unused.

**Impact:** Dead code.

**Fix:** Remove if confirmed unused after searching all references.

### 3.4 Hardcoded Version Number

**Location:**
- `Scribe/Views/SettingsTab.swift:64`
- `Scribe/Views/SettingsView.swift:56`

**Problem:** Version "2.0.0" is hardcoded in two places instead of reading from Info.plist.

**Impact:** Version can become out of sync; maintenance burden.

**Fix:** Read from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`.

---

## 4. Security Observations

### 4.1 OAuth Client Secret (Low Risk)

**Location:** `Scribe/Services/NotionOAuthService.swift:13-14`

**Observation:** The OAuth client ID and secret are stored in source code. For a **public** Notion integration (which uses PKCE), this is acceptable as the secret is not truly secret. The TODO comment should clarify this is expected for public integrations.

### 4.2 Keychain Implementation (Good)

**Location:** `Scribe/Services/KeychainHelper.swift`

**Observation:** The Keychain implementation correctly uses:
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for security
- Proper error handling with OSStatus codes
- Service-specific keys to avoid conflicts

No changes needed.

### 4.3 Input Sanitization (Acceptable)

**Observation:** User-entered text (meeting title, transcript) is sent to Notion without HTML/markdown sanitization. This is acceptable because:
1. Notion's API handles its own sanitization
2. The content is the user's own data, not untrusted input
3. Rich text formatting in transcripts could be valuable

No changes needed, but consider escaping special characters if issues arise.

---

## 5. Architecture Observations

### 5.1 Service Layer (Good)

The separation of concerns is well-designed:
- `RecordingService` - Audio capture and playback
- `TranscriptionService` - Speech-to-text processing
- `SummarizationService` - AI text generation
- `NotionService` - API communication

Each service has a single responsibility and clear interfaces.

### 5.2 Actor Usage (Good)

`NotionService` correctly uses Swift's actor model for thread-safe API access with rate limiting. The `@MainActor` annotations on other services are appropriate for UI-bound work.

### 5.3 SwiftData Integration (Good)

The `MemoModel` correctly uses `@Model` with computed properties for array storage (decisions, actionItems as JSON strings). The `syncStateRaw` pattern for enum storage is appropriate for SwiftData compatibility.

### 5.4 Potential Improvement: State Machine

**Location:** `Scribe/Views/RecordTab.swift:246-283`

The `SessionState` enum is defined in a View file but represents core business logic. Consider moving to a dedicated `SessionStateMachine` class that encapsulates valid transitions and prevents invalid state changes.

---

## 6. Missing Features (Future Enhancements)

These are features that would enhance the app but aren't bugs:

1. **Search in Library** - Ability to search/filter recordings by title or content
2. **Edit Title After Recording** - Currently title can only be set before recording
3. **Audio Playback Scrubbing** - Seek to specific timestamps
4. **Export Options** - Export to PDF, markdown, or other formats
5. **Share Sheet Integration** - Share notes via iOS share sheet
6. **Batch Sync** - Sync multiple recordings at once
7. **Background Processing Indicator** - Show when AI is processing in background

---

## 7. Testing Recommendations

Based on the codebase analysis, the following test scenarios are recommended:

### Critical Paths
1. Record → Stop → Verify transcript saved correctly
2. Record multiple meetings in sequence without app restart
3. OAuth flow → Database selection → Sync → Verify Notion page created
4. Long recording (30+ minutes) → Verify memory usage stable

### Edge Cases
1. Empty transcript (silence only) → Should handle gracefully
2. Very long transcript → Verify summarization truncation works
3. Network failure during sync → Verify error displayed and retry available
4. App backgrounded during recording → Verify recording continues
5. Notion token expiry → Verify re-auth flow works

### Regression Tests After Fixes
1. Multiple recordings reuse TranscriptionService correctly
2. Auto-sync triggers when enabled
3. Delete confirmation prevents accidental deletion

---

## 8. Recommended Fix Priority

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| P0 | TranscriptionService reusability | Medium | High - Blocks core functionality |
| P0 | Auto-sync implementation | Low | High - Feature doesn't work |
| P1 | SyncState enum location | Low | Medium - Code organization |
| P1 | BufferConverter thread safety | Medium | Medium - Potential crashes |
| P1 | Playback error UI | Low | Medium - UX improvement |
| P2 | Delete confirmation | Low | Medium - Data safety |
| P2 | Timer optimization | Low | Low - Performance |
| P2 | Accessibility labels | Medium | Medium - Accessibility |
| P3 | Unused code cleanup | Low | Low - Maintenance |
| P3 | Version from Info.plist | Low | Low - Maintenance |

---

*Analysis completed: January 29, 2026*
