# Foundation Models Integration

## Overview

Swift Scribe uses Apple's Foundation Models framework (iOS 26+) for **on-device** AI summarization of meeting transcripts. No data leaves the device for AI processing.

## Availability Checks

Before using the model, we check availability:

```swift
let model = SystemLanguageModel.default
guard model.isAvailable else {
    // Show "Summarization unavailable on this device"
    return
}
```

`SystemLanguageModel.Availability` can indicate:
- Model is available and ready
- Model needs to be downloaded
- Model is not supported on this hardware
- Apple Intelligence is disabled by the user

If the model is unavailable, the app degrades gracefully:
- Transcript is still saved
- UI shows "Summarization unavailable on this device. Enable Apple Intelligence in Settings."
- All other features (recording, playback, Notion sync of transcript) continue to work

## Session Usage

We create a `LanguageModelSession` with system instructions for meeting note generation:

```swift
let session = LanguageModelSession(instructions: """
    You are a meeting notes assistant. Given a transcript, extract:
    - A concise summary (2-4 sentences)
    - Key decisions made
    - Action items with owners if mentioned
    Output as structured data.
    """)
```

Sessions are stateful - each `respond(to:)` call is recorded in the transcript. We use a single request per summarization (no multi-turn).

## Structured Output with @Generable

We use the `@Generable` macro for reliable structured output instead of parsing free-form text:

```swift
@Generable
struct MeetingNotes {
    @Guide(description: "A concise 2-4 sentence summary of the meeting")
    let summary: String

    @Guide(description: "Key decisions made during the meeting")
    let decisions: [String]

    @Guide(description: "Action items identified, including owner if mentioned")
    let actionItems: [String]
}
```

This uses constrained decoding to guarantee the output matches the schema - the model cannot hallucinate invalid field names or produce malformed output.

Usage:

```swift
let response = try await session.respond(
    generating: MeetingNotes.self,
    options: GenerationOptions(temperature: 0.3)
) {
    "Extract meeting notes from this transcript:\n\n\(transcriptText)"
}
let notes = response.content
```

## Generation Options

- **Temperature 0.3**: Low variance for consistent, factual summaries
- **Sampling**: Default random sampling (not greedy) to allow some natural variation
- No `maximumResponseTokens` limit set - let the model determine appropriate length

## Error Handling

| Error | Recovery |
|-------|----------|
| `exceededContextWindowSize` | Truncate transcript to fit, retry with shorter input |
| `unsupportedLanguageOrLocale` | Show "Language not supported for summarization" |
| `guardrailViolation` | Show "Content could not be summarized" |
| `rateLimited` | Wait and retry automatically |
| `assetsUnavailable` | Show "AI model not available, please check Apple Intelligence settings" |
| `decodingFailure` | Fall back to plain text generation instead of structured output |

## Title Generation

Separate from structured notes, we generate a meeting title:

```swift
let titleSession = LanguageModelSession(instructions: """
    Create a concise 3-8 word title for this meeting transcript.
    Use title case. Focus on the main topic. Do not use quotes.
    """)
let response = try await titleSession.respond(
    to: transcriptText,
    options: GenerationOptions(temperature: 0.3)
)
```

## Privacy

- All AI processing runs entirely on-device
- No transcript or summary data is sent to any server for AI processing
- The Foundation Models framework uses Apple's on-device LLM
- Network calls are only made for Notion sync (user-initiated)

## References

| Document | Identifier |
|----------|------------|
| LanguageModelSession | doc://com.apple.documentation/documentation/FoundationModels/LanguageModelSession |
| SystemLanguageModel | doc://com.apple.documentation/documentation/FoundationModels/SystemLanguageModel |
| Generable | doc://com.apple.documentation/documentation/FoundationModels/Generable |
| GenerationOptions | doc://com.apple.documentation/documentation/FoundationModels/GenerationOptions |
| GenerationGuide | doc://com.apple.documentation/documentation/FoundationModels/GenerationGuide |
| GenerationError | doc://com.apple.documentation/documentation/FoundationModels/LanguageModelSession/GenerationError |
| Instructions | doc://com.apple.documentation/documentation/FoundationModels/Instructions |
| WWDC25: Foundation Models | Docs/wwdc2025-foundation-models.txt (local) |
