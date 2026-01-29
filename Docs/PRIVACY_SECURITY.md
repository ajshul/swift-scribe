# Privacy & Security

## What Stays On-Device

| Data | Location | Leaves Device? |
|------|----------|----------------|
| Audio recordings | App sandbox (FileManager) | Only if synced to Notion (optional) |
| Transcripts | SwiftData (on-device) | Only if synced to Notion (optional) |
| AI summaries | SwiftData (on-device) | Only if synced to Notion (optional) |
| AI processing | Foundation Models (on-device LLM) | Never |
| Speech recognition | Speech framework (on-device) | Never |

## What Is Sent to Notion (User-Initiated Only)

When the user explicitly syncs to Notion (manually or via auto-sync):
- Meeting title
- Summary text
- Decisions list
- Action items list
- Transcript text
- Audio file (if small enough and upload is feasible)
- Meeting date/time

This data is sent to Notion's servers via their API over HTTPS. Notion's privacy policy governs data once it reaches their servers.

**Auto-sync** can be enabled in Settings, but is off by default. When on, sync happens automatically after summarization completes.

## How Secrets Are Stored

### Notion Integration Token
- **Storage**: iOS Keychain (`kSecClassGenericPassword`)
- **Access**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Never** stored in UserDefaults, files, or logs
- Cleared via Settings -> "Clear Notion Credentials"

### Notion Database ID
- **Storage**: UserDefaults (not a secret - it's a UUID identifying the database)
- Cleared via Settings -> "Clear Notion Credentials"

### Keychain Implementation

```swift
// Store
SecItemAdd([
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.swift.scribe.notion",
    kSecAttrAccount: "integration-token",
    kSecValueData: tokenData,
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
] as CFDictionary, nil)

// Retrieve
SecItemCopyMatching([
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.swift.scribe.notion",
    kSecAttrAccount: "integration-token",
    kSecReturnData: true
] as CFDictionary, &result)
```

## Permissions Required

| Permission | Purpose | When Requested |
|-----------|---------|----------------|
| Microphone | Audio recording | First recording |
| Speech Recognition | On-device transcription | First recording |
| Network (outgoing) | Notion API sync | Already entitled in sandbox |

## Network Security

- All Notion API calls use HTTPS
- Token sent via `Authorization: Bearer` header (not in URL or body)
- No other network calls are made by the app
- App Transport Security (ATS) enforced

## Data Retention

- Recordings persist in SwiftData until user deletes them
- Audio files persist in app sandbox until user deletes the recording
- Keychain data persists until user clears credentials or uninstalls
- No analytics, telemetry, or crash reporting data is collected
