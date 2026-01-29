import AVFoundation
import Foundation
import Speech
import SwiftUI
import SwiftData

struct TranscriptView: View {
    @Binding var memo: Memo
    @Binding var isRecording: Bool
    @State var isPlaying = false
    @State var isGenerating = false

    @State var recorder: Recorder?
    @State var speechTranscriber: SpokenWordTranscriber

    @State var downloadProgress = 0.0

    @State var currentPlaybackTime = 0.0

    @State var timer: Timer?

    @State var recordingStartTime: Date?
    @State var recordingDuration: TimeInterval = 0
    @State var recordingTimer: Timer?

    @State var showingEnhancedView = false
    @State var enhancementError: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    init(memo: Binding<Memo>, isRecording: Binding<Bool>) {
        self._memo = memo
        self._isRecording = isRecording
        let transcriber = SpokenWordTranscriber(memo: memo)
        speechTranscriber = transcriber

        recorder = nil

        showingEnhancedView = memo.summary.wrappedValue != nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if !memo.isDone {
                        liveRecordingView
                    } else {
                        if memo.summary != nil && showingEnhancedView {
                            enhancedView
                        } else {
                            playbackView
                        }
                    }
                }

                #if os(iOS)
                    Spacer().frame(height: 100)
                #else
                    Spacer()
                #endif
            }
            #if os(macOS)
                .padding(20)
            #endif

            #if os(iOS)
                VStack {
                    Spacer()
                    bottomButtonBar
                }
                .ignoresSafeArea(.keyboard)
            #endif
        }
        .navigationTitle(memo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isRecording)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(memo.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200)

                        if memo.isDone {
                            Text(memo.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        #endif
        .toolbar {
            #if os(macOS)
                Group {
                    if memo.isDone {
                        ToolbarItem {
                            enhanceButton
                        }

                        if memo.summary != nil {
                            ToolbarItem {
                                viewToggleButton
                            }
                        }
                    }

                    ToolbarSpacer(.fixed)

                    if !memo.isDone {
                        ToolbarItem {
                            recordButton
                        }
                    }

                    ToolbarSpacer(.fixed)

                    if memo.isDone {
                        ToolbarItem {
                            playButton
                        }
                    }

                    ToolbarSpacer(.fixed)
                }
            #endif
        }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }

            if newValue == true {
                recordingStartTime = Date()
                recordingDuration = 0
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    Task { @MainActor in
                        if let startTime = recordingStartTime {
                            recordingDuration = Date().timeIntervalSince(startTime)
                        }
                    }
                }

                if memo.isDone {
                    memo.isDone = false
                    speechTranscriber.reset()
                }
                Task {
                    do {
                        try await recorder?.record()
                    } catch let error as TranscriptionError {
                        await MainActor.run {
                            isRecording = false
                            enhancementError = "Recording failed: \(error.descriptionString)"
                        }
                    } catch {
                        await MainActor.run {
                            isRecording = false
                            enhancementError = "Recording failed: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                recordingTimer?.invalidate()
                recordingTimer = nil
                recordingStartTime = nil
                recordingDuration = 0

                Task {
                    do {
                        try await recorder?.stopRecording()
                        await generateTitleIfNeeded()
                        await generateAIEnhancements()
                    } catch {
                        await MainActor.run {
                            enhancementError =
                                "Error stopping recording: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        .onChange(of: isPlaying) {
            handlePlayback()
        }
        .onAppear {
            if recorder == nil {
                recorder = Recorder(
                    transcriber: speechTranscriber,
                    memo: $memo
                )
            }

            if let progress = speechTranscriber.downloadProgress {
                let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    Task { @MainActor in
                        if progress.isFinished {
                            downloadProgress = 100.0
                        } else {
                            downloadProgress = progress.fractionCompleted * 100.0
                        }
                    }
                }

                Task { @MainActor in
                    while !progress.isFinished && timer.isValid {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    timer.invalidate()
                }
            }

            if !memo.isDone && memo.text.characters.isEmpty {
                speechTranscriber.reset()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isRecording = true
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            recordingTimer?.invalidate()
            recordingTimer = nil
        }
        .alert("Enhancement Error", isPresented: .constant(enhancementError != nil)) {
            Button("OK") {
                enhancementError = nil
            }
        } message: {
            if let error = enhancementError {
                Text(error)
            }
        }
    }

    // MARK: - Bottom Button Bar for iOS

    #if os(iOS)
        @ViewBuilder
        private var bottomButtonBar: some View {
            HStack(spacing: 16) {
                if !memo.isDone {
                    recordButtonLarge
                } else {
                    HStack(spacing: 12) {
                        if memo.summary != nil {
                            viewToggleButtonCompact
                        }
                    }

                    Spacer()

                    enhanceButtonCompact
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

        @ViewBuilder
        private var recordButtonLarge: some View {
            Button {
                handleRecordingButtonTap()
            } label: {
                HStack(spacing: 12) {
                    Label(
                        isRecording ? "Stop Recording" : "Start Recording",
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .font(.headline)
                    .fontWeight(.semibold)

                    if isRecording {
                        Text(formatDuration(recordingDuration))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
            .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
        }

        @ViewBuilder
        private var viewToggleButtonCompact: some View {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showingEnhancedView.toggle()
                }
            } label: {
                Label(
                    showingEnhancedView ? "Transcript" : "Summary",
                    systemImage: showingEnhancedView ? "doc.plaintext" : "sparkles"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingEnhancedView ? .gray : SpokenWordTranscriber.green)
        }

        @ViewBuilder
        private var enhanceButtonCompact: some View {
            Button {
                handleAIEnhanceButtonTap()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        memo.summary != nil ? "Re-summarize" : "Summarize with AI",
                        systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                    )
                    .font(.body)
                    .fontWeight(.medium)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(SpokenWordTranscriber.green)
            .disabled(memo.text.characters.isEmpty || isGenerating)
        }
    #endif

    // MARK: - Enhanced View

    @ViewBuilder
    private var enhancedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(SpokenWordTranscriber.green)

                    Text("AI Summary")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            #endif

            #if os(macOS)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(SpokenWordTranscriber.green)
                            .symbolRenderingMode(.monochrome)

                        Text("AI Enhanced Summary")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            #endif

            Group {
                if let summary = memo.summary, !String(summary.characters).isEmpty {
                    ScrollView {
                        Text(summary)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #if os(iOS)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            #else
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            #endif
                            .textSelection(.enabled)
                    }
                    #if os(macOS)
                        .padding(.horizontal, 16)
                    #endif
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .foregroundStyle(SpokenWordTranscriber.green)

                        VStack(spacing: 8) {
                            Text("Generating enhanced summary...")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("This may take a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
            .background(.background.secondary.opacity(0.3))
        #endif
    }

    // MARK: - Individual Toolbar Buttons

    @ViewBuilder
    private var playButton: some View {
        Button {
            handlePlayButtonTap()
        } label: {
            Label(
                isPlaying ? "Pause" : "Play",
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var recordButton: some View {
        Button {
            handleRecordingButtonTap()
        } label: {
            HStack(spacing: 8) {
                Label(
                    isRecording ? "Stop" : "Record",
                    systemImage: isRecording ? "stop.fill" : "record.circle"
                )

                if isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.body)
                        .monospacedDigit()
                }
            }
        }
        .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
    }

    @ViewBuilder
    private var viewToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView.toggle()
            }
        } label: {
            Label(
                showingEnhancedView ? "Transcript" : "Summary",
                systemImage: showingEnhancedView
                    ? "doc.plaintext.fill" : "sparkles.rectangle.stack.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var enhanceButton: some View {
        Button {
            handleAIEnhanceButtonTap()
        } label: {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    memo.summary != nil ? "Re-enhance" : "Enhance",
                    systemImage: memo.summary != nil ? "arrow.clockwise" : "sparkles"
                )
            }
        }
        .buttonStyle(.glass)
        .tint(SpokenWordTranscriber.green)
        .disabled(memo.text.characters.isEmpty || isGenerating)
    }

    @ViewBuilder
    var liveRecordingView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if speechTranscriber.finalizedTranscript.utf8.isEmpty
                    && speechTranscriber.volatileTranscript.utf8.isEmpty
                {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: isRecording)

                            Text(formatDuration(recordingDuration))
                                .font(.system(size: 32, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)

                            Text("Listening...")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("Start speaking into the microphone")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 32)
                        .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                        .padding(.top, 40)
                    #else
                        .padding()
                    #endif
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(
                            speechTranscriber.finalizedTranscript
                                + speechTranscriber.volatileTranscript
                        )
                        .font(.body)
                        .lineSpacing(4)
                        #if os(iOS)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        #else
                            .padding(20)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    var playbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                    Text("Transcript")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                #endif

                Text(memo.textBrokenUpByParagraphs())
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    #else
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    #endif
                    .textSelection(.enabled)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var progressView: some View {
        ProgressView(value: downloadProgress, total: 100)
            .progressViewStyle(LinearProgressViewStyle())
            .opacity(downloadProgress > 0 && downloadProgress < 100 ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: downloadProgress)
    }
}

// MARK: - TranscriptView Extension

extension TranscriptView {

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func handlePlayback() {
        guard memo.url != nil else {
            return
        }

        if isPlaying {
            Task {
                await recorder?.playRecording()
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                Task { @MainActor in
                    currentPlaybackTime = recorder?.playerNode?.currentTime ?? 0.0
                }
            }
        } else {
            Task {
                await recorder?.stopPlaying()
            }
            currentPlaybackTime = 0.0
            timer = nil
        }
    }

    func handleRecordingButtonTap() {
        isRecording.toggle()
    }

    func handlePlayButtonTap() {
        isPlaying.toggle()
    }

    func handleAIEnhanceButtonTap() {
        Task {
            await generateAIEnhancements()
        }
    }

    @MainActor
    private func generateAIEnhancements() async {
        isGenerating = true
        enhancementError = nil

        do {
            try await memo.generateAIEnhancements()
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView = true
            }
        } catch let error as FoundationModelsError {
            enhancementError = error.localizedDescription
        } catch {
            enhancementError = "Failed to generate AI enhancements: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    @MainActor
    private func generateTitleIfNeeded() async {
        guard !memo.text.characters.isEmpty,
            memo.title == "New Memo" || memo.title.isEmpty
        else {
            return
        }

        do {
            let suggestedTitle = try await memo.suggestedTitle() ?? memo.title
            memo.title = suggestedTitle
        } catch {
            print("Error generating title: \(error)")
        }
    }

    @ViewBuilder func textScrollView(attributedString: AttributedString) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                textWithHighlighting(attributedString: attributedString)
                Spacer()
            }
        }
    }

    func attributedStringWithCurrentValueHighlighted(attributedString: AttributedString)
        -> AttributedString
    {
        var copy = attributedString
        copy.runs.forEach { run in
            if shouldBeHighlighted(attributedStringRun: run) {
                let range = run.range
                copy[range].backgroundColor = .mint.opacity(0.2)
            }
        }
        return copy
    }

    func shouldBeHighlighted(attributedStringRun: AttributedString.Runs.Run) -> Bool {
        guard isPlaying else { return false }
        let start = attributedStringRun.audioTimeRange?.start.seconds
        let end = attributedStringRun.audioTimeRange?.end.seconds
        guard let start, let end else {
            return false
        }

        if end < currentPlaybackTime { return false }

        if start < currentPlaybackTime, currentPlaybackTime < end {
            return true
        }

        return false
    }

    @ViewBuilder func textWithHighlighting(attributedString: AttributedString) -> some View {
        Group {
            Text(attributedStringWithCurrentValueHighlighted(attributedString: attributedString))
                .font(.body)
        }
    }
}
