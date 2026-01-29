# Speech Analyzer / SpeechTranscriber Integration

## Overview

Swift Scribe uses Apple's iOS 26 Speech framework (`SpeechAnalyzer` + `SpeechTranscriber`) for real-time, on-device speech-to-text transcription. No audio data leaves the device.

## Transcription Approach: Streaming

We use **streaming transcription** (not file-based) because:
1. Users see live text as they speak - essential for a recording app
2. Provides immediate feedback that the app is working
3. Matches the existing repo's architecture

### Pipeline

```
AVAudioEngine (mic input)
    -> Audio buffers (4096 frames)
    -> Format conversion (device format -> analyzer format)
    -> SpeechAnalyzer.start(inputSequence:)
    -> SpeechTranscriber.results (AsyncSequence)
    -> UI updates (finalized + volatile text)
```

## SpeechTranscriber Configuration

We use the `progressiveTranscription` preset for live audio:

```swift
let transcriber = SpeechTranscriber(
    locale: locale,
    preset: .progressiveTranscription
)
```

This preset includes:
- `reportingOptions: [.volatileResults]` - Shows interim results before finalization
- Optimized for live audio streams
- No `etiquetteReplacements` (we want verbatim transcription)

For time-indexed transcription (to support audio playback alignment):

```swift
let transcriber = SpeechTranscriber(
    locale: locale,
    preset: .timeIndexedProgressiveTranscription
)
```

## SpeechAnalyzer Setup

```swift
let analyzer = SpeechAnalyzer(modules: [transcriber])
let format = try await analyzer.bestAvailableAudioFormat(
    compatibleWith: [transcriber]
)
```

### Starting Analysis

```swift
// Create an AsyncSequence of audio inputs
analyzer.start(inputSequence: audioInputStream)
```

### Processing Results

```swift
for await result in transcriber.results {
    if result.isFinal {
        // Append finalized text to transcript
        finalizedTranscript += result.text.characters.map(String.init).joined()
    } else {
        // Show as volatile/interim text (visually distinct)
        volatileText = result.text.characters.map(String.init).joined()
    }
}
```

### Finishing Analysis

```swift
// When recording stops:
analyzer.finalizeAndFinishThroughEndOfInput()
```

## Audio Format Conversion

The device microphone format often differs from what SpeechAnalyzer needs. We use `AVAudioConverter` to resample:

```swift
let converter = AVAudioConverter(from: deviceFormat, to: analyzerFormat)
converter?.primeMethod = .none  // Avoid timestamp drift
```

Key considerations:
- Device typically records at 44.1 kHz or 48 kHz
- SpeechAnalyzer may need 16 kHz
- Mono is sufficient for speech recognition
- We maintain a separate recording file in the original quality

## Locale Management

Primary locale: `en-US`

Fallback chain:
1. `en-US` -> `en-GB` -> `en-CA` -> `en-AU` -> `en` -> `Locale.current`

Before transcription, we verify:
```swift
guard SpeechTranscriber.isAvailable else {
    // Speech recognition not available on this device
    return
}

let supportedLocale = SpeechTranscriber.supportedLocale(equivalentTo: locale)
```

## Constraints and Limits

| Constraint | Detail |
|-----------|--------|
| Device support | Requires iOS 26+ with Neural Engine |
| Languages | English well-supported; check `supportedLocales` for others |
| Audio quality | Best with clear speech; background noise degrades accuracy |
| Permissions | Requires microphone permission (`NSMicrophoneUsageDescription`) |
| Concurrent sessions | One active SpeechAnalyzer at a time |
| Long recordings | No hard time limit, but accuracy may degrade over very long sessions |

## Chunking Decision

**No chunking needed.** The streaming approach processes audio continuously via `inputSequence`. The SpeechAnalyzer handles internal buffering and produces results incrementally. There's no need to manually chunk audio into segments.

For very long recordings (1+ hours), we rely on the SpeechAnalyzer's internal management. If we encounter issues with very long sessions in practice, we can implement session restart with context carryover.

## Error Handling

- **Model not available**: Check `SpeechTranscriber.isAvailable` before starting
- **Locale not supported**: Fall through locale chain, show warning if no locale works
- **Permission denied**: Prompt user to enable microphone in Settings
- **Analysis failure**: Save audio file so user can attempt re-transcription later

## References

| Document | Identifier |
|----------|------------|
| SpeechAnalyzer | doc://com.apple.documentation/documentation/Speech/SpeechAnalyzer |
| SpeechTranscriber | doc://com.apple.documentation/documentation/Speech/SpeechTranscriber |
| SpeechTranscriber.Result | doc://com.apple.documentation/documentation/Speech/SpeechTranscriber/Result |
| SpeechTranscriber.Preset | doc://com.apple.documentation/documentation/Speech/SpeechTranscriber/Preset |
| SpeechTranscriber.ReportingOption | doc://com.apple.documentation/documentation/Speech/SpeechTranscriber/ReportingOption |
| SpeechTranscriber.TranscriptionOption | doc://com.apple.documentation/documentation/Speech/SpeechTranscriber/TranscriptionOption |
| SpeechAnalyzer.Options | doc://com.apple.documentation/documentation/Speech/SpeechAnalyzer/Options |
