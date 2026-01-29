import AVFoundation
import Foundation
import Speech

@MainActor
@Observable
final class TranscriptionService {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<Void, any Error>?

    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    private let bufferConverter = BufferConverter()
    private(set) var analyzerFormat: AVAudioFormat?

    var finalizedText = ""
    var volatileText = ""

    var isTranscribing: Bool { recognizerTask != nil }

    static let preferredLocale = Locale(
        components: .init(languageCode: .english, languageRegion: .unitedStates)
    )

    init() {}

    /// Start transcription, returning when setup is complete.
    func start() async throws {
        finalizedText = ""
        volatileText = ""

        // Create new stream for this session (enables reuse after stop)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation

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

        try await analyzer?.start(inputSequence: stream)
    }

    /// Feed an audio buffer into the transcription pipeline.
    func processBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }

        guard let inputBuilder else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        let converted = try bufferConverter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    /// Finalize transcription and stop.
    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil
        inputSequence = nil
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
