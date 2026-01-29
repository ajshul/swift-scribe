import AVFoundation
import Foundation
import Speech

@MainActor
@Observable
final class TranscriptionService {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<Void, any Error>?

    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation

    private let bufferConverter = BufferConverter()
    private(set) var analyzerFormat: AVAudioFormat?

    var finalizedText = ""
    var volatileText = ""

    var isTranscribing: Bool { recognizerTask != nil }

    static let preferredLocale = Locale(
        components: .init(languageCode: .english, languageRegion: .unitedStates)
    )

    init() {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }

    /// Start transcription, returning when setup is complete.
    func start() async throws {
        finalizedText = ""
        volatileText = ""

        transcriber = SpeechTranscriber(
            locale: Self.preferredLocale,
            preset: .timeIndexedProgressiveTranscription
        )

        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard analyzerFormat != nil else {
            throw TranscriptionError.invalidAudioDataType
        }

        // Start listening for results
        recognizerTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalizedText += text
                    volatileText = ""
                } else {
                    volatileText = text
                }
            }
        }

        try await analyzer?.start(inputSequence: inputSequence)
    }

    /// Feed an audio buffer into the transcription pipeline.
    func processBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }

        let converted = try bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    /// Finalize transcription and stop.
    func stop() async {
        inputBuilder.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        analyzer = nil
        transcriber = nil
    }

    /// Reset for a new session.
    func reset() {
        finalizedText = ""
        volatileText = ""
    }

    var fullText: String {
        finalizedText + volatileText
    }
}
