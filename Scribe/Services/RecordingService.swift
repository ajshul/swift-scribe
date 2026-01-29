@preconcurrency import AVFoundation
import Foundation

@MainActor
@Observable
final class RecordingService {
    private var recordingEngine = AVAudioEngine()
    private var playbackEngine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?

    // These are accessed from the audio callback thread
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    private nonisolated(unsafe) var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var audioFileURL: URL?

    /// Start recording audio, returning a stream of audio buffers for transcription.
    func startRecording() async throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }

        guard await isAuthorized() else {
            throw RecordingError.notAuthorized
        }

        try configureAudioSession()

        let url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("m4a")
        self.audioFileURL = url

        // Create the stream first so continuation is available for the tap
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }

        try setupEngine(writingTo: url)

        recordingEngine.prepare()
        try recordingEngine.start()
        isRecording = true

        return stream
    }

    /// Stop the current recording.
    func stopRecording() {
        guard isRecording else { return }

        recordingEngine.inputNode.removeTap(onBus: 0)
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }
        outputContinuation?.finish()
        outputContinuation = nil
        audioFile = nil
        isRecording = false
    }

    /// Play back a recorded audio file.
    func playRecording(url: URL) throws {
        guard !isPlaying else { return }

        let file = try AVAudioFile(forReading: url)

        playerNode = AVAudioPlayerNode()
        guard let playerNode else { return }

        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.outputNode, format: file.processingFormat)

        playerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }

        try playbackEngine.start()
        playerNode.play()
        isPlaying = true
    }

    /// Stop playback.
    func stopPlayback() {
        playerNode?.stop()
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }
        if let node = playerNode {
            playbackEngine.detach(node)
            playerNode = nil
        }
        isPlaying = false
    }

    var currentPlaybackTime: TimeInterval {
        guard let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        #else
            if recordingEngine.isRunning {
                recordingEngine.stop()
            }
            recordingEngine.reset()
        #endif
    }

    private func setupEngine(writingTo url: URL) throws {
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }
        recordingEngine.inputNode.removeTap(onBus: 0)
        recordingEngine.reset()

        let inputFormat = recordingEngine.inputNode.outputFormat(forBus: 0)

        // Write as AAC m4a for smaller file sizes
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000,
        ]

        audioFile = try AVAudioFile(forWriting: url, settings: outputSettings)

        recordingEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self else { return }
            // Write to disk
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                print("[RecordingService] Write error: \(error)")
            }
            // Forward to transcription
            self.outputContinuation?.yield(buffer)
        }
    }

    nonisolated func isAuthorized() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

enum RecordingError: LocalizedError {
    case notAuthorized
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access is required. Please enable it in Settings."
        case .alreadyRecording:
            return "A recording is already in progress."
        }
    }
}
