import AVFoundation
import Foundation
import SwiftUI
import SwiftData

class Recorder {
    private var outputContinuation: AsyncStream<AudioData>.Continuation?

    private let recordingEngine: AVAudioEngine
    private let playbackEngine: AVAudioEngine

    private let transcriber: SpokenWordTranscriber
    private var audioFile: AVAudioFile?
    var playerNode: AVAudioPlayerNode?

    var memo: Binding<Memo>
    private let url: URL

    init(transcriber: SpokenWordTranscriber, memo: Binding<Memo>) {
        self.recordingEngine = AVAudioEngine()
        self.playbackEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.memo = memo
        self.url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("wav")
    }

    func record() async throws {
        let memoURLBinding = memo.url
        let recordingURL = url
        await MainActor.run {
            memoURLBinding.wrappedValue = recordingURL
        }

        guard await isAuthorized() else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        try setUpAudioSession()

        do {
            try await transcriber.setUpTranscriber()
        } catch {
            throw error
        }

        do {
            let audioStreamSequence = try await audioStream()
            for await audioData in audioStreamSequence {
                try await self.transcriber.streamAudioToTranscriber(audioData.buffer)
            }
        } catch {
            throw error
        }
    }

    func stopRecording() async throws {
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }

        recordingEngine.inputNode.removeTap(onBus: 0)

        let memoIsDoneBinding = memo.isDone
        await MainActor.run {
            memoIsDoneBinding.wrappedValue = true
        }

        outputContinuation?.finish()
        outputContinuation = nil

        do {
            try await transcriber.finishTranscribing()
        } catch {
            throw error
        }
    }

    func pauseRecording() {
        recordingEngine.pause()
    }

    func resumeRecording() throws {
        try recordingEngine.start()
    }

    #if os(iOS)
        func setUpAudioSession() throws {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
    #else
        func setUpAudioSession() throws {
            if recordingEngine.isRunning {
                recordingEngine.stop()
            }
            recordingEngine.reset()

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                break
            case .notDetermined:
                break
            case .denied, .restricted:
                throw TranscriptionError.failedToSetupRecognitionStream
            @unknown default:
                throw TranscriptionError.failedToSetupRecognitionStream
            }
        }
    #endif

    private func audioStream() async throws -> AsyncStream<AudioData> {
        try setupRecordingEngine()

        recordingEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self] (buffer, time) in
            guard let self else { return }
            self.writeBufferToDisk(buffer: buffer)
            let audioData = AudioData(buffer: buffer, time: time)
            self.outputContinuation?.yield(audioData)
        }

        recordingEngine.prepare()
        try recordingEngine.start()

        return AsyncStream(AudioData.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }
    }

    private func setupRecordingEngine() throws {
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }

        recordingEngine.inputNode.removeTap(onBus: 0)
        recordingEngine.reset()

        let inputFormat = recordingEngine.inputNode.outputFormat(forBus: 0)

        let inputSettings = inputFormat.settings
        do {
            self.audioFile = try AVAudioFile(forWriting: url, settings: inputSettings)
        } catch {
            throw error
        }
    }

    private func writeBufferToDisk(buffer: AVAudioPCMBuffer) {
        do {
            try audioFile?.write(from: buffer)
        } catch {
            print("[Recorder]: File writing error: \(error)")
        }
    }

    func playRecording() async {
        guard let audioFile = audioFile else {
            return
        }

        await stopPlaying()

        playerNode = AVAudioPlayerNode()
        guard let playerNode = playerNode else {
            return
        }

        playbackEngine.attach(playerNode)
        playbackEngine.connect(
            playerNode,
            to: playbackEngine.outputNode,
            format: audioFile.processingFormat
        )

        playerNode.scheduleFile(
            audioFile,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in }

        do {
            try playbackEngine.start()
            playerNode.play()
        } catch {
            print("[Recorder]: Error starting playback engine: \(error.localizedDescription)")
        }
    }

    func stopPlaying() async {
        playerNode?.stop()

        if playbackEngine.isRunning {
            playbackEngine.stop()
        }

        if let playerNode = playerNode {
            playbackEngine.detach(playerNode)
            self.playerNode = nil
        }
    }
}
