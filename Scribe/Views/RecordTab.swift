import AVFoundation
import SwiftData
import SwiftUI

struct RecordTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var sessionState: SessionState = .idle
    @State private var meetingTitle: String = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var recordingStartTime: Date?

    @State private var currentMemo: Memo?
    @State private var navigateToReview = false

    private var defaultTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Meeting - \(formatter.string(from: Date()))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Meeting title
                VStack(spacing: 16) {
                    TextField("Meeting title", text: $meetingTitle)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 32)
                        .disabled(sessionState != .idle)
                        .opacity(sessionState == .idle ? 1.0 : 0.6)
                }

                Spacer()

                // Status + Timer
                VStack(spacing: 12) {
                    if sessionState == .recording {
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 48, weight: .light, design: .monospaced))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }

                    Text(sessionState.displayLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(sessionState.labelColor)
                        .animation(.smooth, value: sessionState)
                }

                Spacer()

                // Record / Stop button
                VStack(spacing: 24) {
                    Button {
                        handleRecordStopTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(sessionState == .recording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
                                .frame(width: 88, height: 88)

                            Image(systemName: sessionState == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState.isProcessing)
                    .opacity(sessionState.isProcessing ? 0.5 : 1.0)
                    .sensoryFeedback(.impact(weight: .medium), trigger: sessionState)

                    if sessionState.isProcessing {
                        ProgressView()
                            .controlSize(.regular)
                    }
                }

                Spacer()
                Spacer()
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if meetingTitle.isEmpty {
                    meetingTitle = defaultTitle
                }
            }
            .navigationDestination(isPresented: $navigateToReview) {
                if let memo = currentMemo {
                    ReviewNotesView(memo: memo)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleRecordStopTap() {
        switch sessionState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        default:
            break
        }
    }

    private func startRecording() {
        let title = meetingTitle.isEmpty ? defaultTitle : meetingTitle
        let memo = Memo(title: title, text: AttributedString(""))
        modelContext.insert(memo)
        currentMemo = memo

        sessionState = .recording
        recordingStartTime = Date()
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if let start = recordingStartTime {
                    recordingDuration = Date().timeIntervalSince(start)
                }
            }
        }

        // TODO: Wire RecordingService + TranscriptionService in milestone 4/5
    }

    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil

        if let memo = currentMemo {
            memo.duration = recordingDuration
            memo.isDone = true
        }

        sessionState = .transcribing

        // TODO: Wire actual transcription + summarization pipeline
        // For now, simulate the state transitions
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            await MainActor.run {
                sessionState = .summarizing
            }
            try? await Task.sleep(for: .seconds(0.5))
            await MainActor.run {
                sessionState = .ready
                navigateToReview = true
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Session State

enum SessionState: String, Codable {
    case idle
    case recording
    case transcribing
    case summarizing
    case ready
    case syncing
    case completed

    var displayLabel: String {
        switch self {
        case .idle: return "Ready to Record"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing..."
        case .summarizing: return "Generating Notes..."
        case .ready: return "Notes Ready"
        case .syncing: return "Syncing to Notion..."
        case .completed: return "Done"
        }
    }

    var labelColor: Color {
        switch self {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing, .summarizing, .syncing: return .orange
        case .ready: return Color(red: 0.36, green: 0.69, blue: 0.55)
        case .completed: return .green
        }
    }

    var isProcessing: Bool {
        switch self {
        case .transcribing, .summarizing, .syncing: return true
        default: return false
        }
    }
}
