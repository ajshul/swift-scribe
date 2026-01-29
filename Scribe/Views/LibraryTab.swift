import SwiftData
import SwiftUI

struct LibraryTab: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if memos.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Recordings will appear here after you record a meeting.")
                    )
                } else {
                    List {
                        ForEach(memos) { memo in
                            NavigationLink(value: memo) {
                                MemoRow(memo: memo)
                            }
                        }
                        .onDelete(perform: deleteMemos)
                    }
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: Memo.self) { memo in
                MemoDetailView(memo: memo)
            }
            .toolbar {
                #if os(iOS)
                    if !memos.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                        }
                    }
                #endif
            }
        }
    }

    private func deleteMemos(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(memos[index])
        }
    }
}

// MARK: - Memo Row

struct MemoRow: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(memo.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                SyncBadge(state: memo.syncState)
            }

            HStack(spacing: 8) {
                Text(memo.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = memo.duration {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary = memo.summaryText, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Sync Badge

enum SyncState: String, Codable {
    case notConnected
    case pending
    case synced
    case failed
}

struct SyncBadge: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)

            Text(badgeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var badgeColor: Color {
        switch state {
        case .notConnected: return .gray
        case .pending: return .orange
        case .synced: return .green
        case .failed: return .red
        }
    }

    private var badgeText: String {
        switch state {
        case .notConnected: return "Not Synced"
        case .pending: return "Pending"
        case .synced: return "Synced"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Memo Detail View

struct MemoDetailView: View {
    @Bindable var memo: Memo
    @State private var isPlaying = false
    @State private var recordingService = RecordingService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary section
                if let summary = memo.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Summary", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.36, green: 0.69, blue: 0.55))

                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)
                }

                // Decisions
                if !memo.decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Decisions", systemImage: "checkmark.circle")
                            .font(.headline)

                        ForEach(memo.decisions, id: \.self) { decision in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .padding(.top, 6)
                                Text(decision)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Action Items
                if !memo.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Action Items", systemImage: "checklist")
                            .font(.headline)

                        ForEach(memo.actionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "square")
                                    .font(.system(size: 14))
                                Text(item)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Playback
                if memo.url != nil {
                    HStack {
                        Button {
                            togglePlayback()
                        } label: {
                            Label(isPlaying ? "Stop" : "Play Recording", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)

                        if let duration = memo.duration {
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }

                // Transcript section
                DisclosureGroup {
                    if let transcript = memo.transcriptText, !transcript.isEmpty {
                        Text(transcript)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    } else {
                        Text("No transcript available")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Transcript", systemImage: "doc.plaintext")
                        .font(.headline)
                }
                .padding(.horizontal)

                // Sync status
                HStack {
                    SyncBadge(state: memo.syncState)
                    Spacer()
                    Button {
                        // TODO: Wire Notion sync
                    } label: {
                        Label("Sync to Notion", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.36, green: 0.69, blue: 0.55))
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(memo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func togglePlayback() {
        if isPlaying {
            recordingService.stopPlayback()
            isPlaying = false
        } else if let url = memo.url {
            do {
                try recordingService.playRecording(url: url)
                isPlaying = true
            } catch {
                print("Playback error: \(error)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Review Notes View

struct ReviewNotesView: View {
    @Bindable var memo: Memo
    @Environment(\.dismiss) private var dismiss
    @State private var showingTranscript = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Summary", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.36, green: 0.69, blue: 0.55))
                        Spacer()
                    }

                    if let summary = memo.summary {
                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                    } else if let summaryText = memo.summaryText {
                        Text(summaryText)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("Summary not available")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Decisions
                VStack(alignment: .leading, spacing: 8) {
                    Label("Decisions", systemImage: "checkmark.circle")
                        .font(.headline)

                    if memo.decisions.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memo.decisions, id: \.self) { decision in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .padding(.top, 6)
                                Text(decision)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Action Items
                VStack(alignment: .leading, spacing: 8) {
                    Label("Action Items", systemImage: "checklist")
                        .font(.headline)

                    if memo.actionItems.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memo.actionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "square")
                                    .font(.system(size: 14))
                                Text(item)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Transcript toggle
                DisclosureGroup("Transcript", isExpanded: $showingTranscript) {
                    if let transcript = memo.transcriptText, !transcript.isEmpty {
                        Text(transcript)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    } else {
                        Text("No transcript available")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        // TODO: Wire Notion sync
                    } label: {
                        Label("Sync to Notion", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.36, green: 0.69, blue: 0.55))

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Sync status
                HStack {
                    Spacer()
                    SyncBadge(state: memo.syncState)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .navigationTitle(memo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
