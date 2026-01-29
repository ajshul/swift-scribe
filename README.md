# Swift Scribe - Conference Room Meeting Recorder for iOS 26+

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)

> **On-device transcription, AI-powered meeting notes, and Notion sync - all running locally on your iPhone.**

Swift Scribe is a privacy-first meeting recorder designed for conference room use. Record meetings, get automatic transcription and AI-generated notes (summary, decisions, action items), and sync to Notion - all without sending any data to external servers for AI processing.

## Features

- **One-tap recording** - Large record button, live transcript preview, meeting timer
- **On-device AI** - Uses iOS 26 Foundation Models for summarization (no cloud AI)
- **Structured notes** - Automatic extraction of summary, decisions, and action items
- **Notion sync** - Push meeting notes to your Notion database with one tap
- **Background recording** - Phone can lock/sleep while recording continues
- **Privacy-focused** - Audio and AI processing never leave your device

## Requirements

- **iOS 26+** (required - uses new Apple frameworks)
- **Xcode 26 Beta** with Swift 6.2+
- **Apple Intelligence enabled** on device (for AI summarization)
- Device with microphone permissions

## Installation

```bash
git clone https://github.com/seamlesscompute/swift-scribe
cd swift-scribe
open SwiftScribe.xcodeproj
```

Build and run on an iOS 26+ device or simulator.

## Usage

### Recording a Meeting

1. Open the app to the **Record** tab
2. Edit the meeting title if desired (defaults to "Meeting – [date/time]")
3. Tap the **green record button** to start
4. Speak - you'll see live transcription as you talk
5. Tap the **red stop button** when finished
6. Wait for transcription and AI summarization to complete
7. Review your notes: summary, decisions, action items, and full transcript

### Setting Up Notion Sync

1. Go to **Settings** > **Notion Integration**
2. Create a Notion integration at [notion.so/my-integrations](https://www.notion.so/my-integrations)
3. Copy your **Integration Token** (starts with `ntn_`)
4. Create or choose a Notion database for meeting notes
5. Share the database with your integration (click ... > Connections > Add your integration)
6. Copy the **Database ID** from the database URL
7. Paste both values in the app and tap **Test Connection**

### Syncing Notes

- From the **Review Notes** screen after recording, tap **Sync to Notion**
- Or from the **Library** tab, open any recording and tap **Sync to Notion**
- Enable **Auto-sync** in Settings to sync automatically after each recording

## Architecture

```
Scribe/
├── Services/
│   ├── RecordingService.swift      # AVAudioEngine recording
│   ├── TranscriptionService.swift  # SpeechAnalyzer streaming
│   ├── SummarizationService.swift  # Foundation Models AI
│   ├── NotionService.swift         # Notion API client
│   └── KeychainHelper.swift        # Secure token storage
├── Models/
│   ├── MemoModel.swift             # SwiftData persistence
│   └── AppSettings.swift           # User preferences
└── Views/
    ├── RecordTab.swift             # Recording UI
    ├── LibraryTab.swift            # Past recordings
    └── SettingsTab.swift           # Configuration
```

## Privacy

- **Audio** - Stays on device, saved to app sandbox
- **Transcription** - Processed by iOS Speech framework (on-device)
- **AI Summarization** - Uses iOS Foundation Models (on-device)
- **Notion sync** - Only syncs when you tap the button (or enable auto-sync)
- **Token storage** - Notion token stored in iOS Keychain

No data is sent to any server for AI processing. The only network calls are to Notion's API when you explicitly sync.

## Documentation

See the `docs/` folder for detailed documentation:

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Service modules and data flow
- [FOUNDATION_MODELS.md](docs/FOUNDATION_MODELS.md) - AI integration details
- [SPEECH_ANALYZER.md](docs/SPEECH_ANALYZER.md) - Transcription implementation
- [NOTION_SYNC.md](docs/NOTION_SYNC.md) - API integration and configuration
- [STATE_MACHINE.md](docs/STATE_MACHINE.md) - Recording session states
- [PRIVACY_SECURITY.md](docs/PRIVACY_SECURITY.md) - Data handling and security

## License

MIT License - see [LICENSE](LICENSE) for details.
