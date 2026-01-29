import SwiftData
import SwiftUI

struct LibraryTab: View {
    @Query(sort: \Memo.createdAt, order: .reverse) private var memos: [Memo]
    @Environment(\.modelContext) private var modelContext
    @State private var memoToDelete: Memo?
    @State private var showDeleteConfirmation = false

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
            .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    memoToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let memo = memoToDelete {
                        modelContext.delete(memo)
                        memoToDelete = nil
                    }
                }
            } message: {
                if let memo = memoToDelete {
                    Text("Are you sure you want to delete \"\(memo.title)\"? This cannot be undone.")
                }
            }
        }
    }

    private func deleteMemos(offsets: IndexSet) {
        // Show confirmation for the first item to delete
        if let index = offsets.first {
            memoToDelete = memos[index]
            showDeleteConfirmation = true
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
    @State private var playbackError: String?

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
                        .accessibilityLabel(isPlaying ? "Stop playback" : "Play recording")
                        .accessibilityHint(isPlaying ? "Tap to stop audio playback" : "Tap to listen to the recording")

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
                SyncSection(memo: memo)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(memo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Playback Error", isPresented: .constant(playbackError != nil)) {
            Button("OK") { playbackError = nil }
        } message: {
            if let error = playbackError {
                Text(error)
            }
        }
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
                playbackError = "Could not play recording: \(error.localizedDescription)"
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Sync Section

struct SyncSection: View {
    @Bindable var memo: Memo
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                SyncBadge(state: memo.syncState)
                Spacer()
                Button {
                    syncToNotion()
                } label: {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            memo.notionPageId != nil ? "Resync" : "Sync to Notion",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.36, green: 0.69, blue: 0.55))
                .disabled(isSyncing || !NotionSettings.shared.isConfigured)
                .accessibilityLabel(memo.notionPageId != nil ? "Resync to Notion" : "Sync to Notion")
                .accessibilityHint(isSyncing ? "Currently syncing" : "Tap to upload your notes to Notion")
            }

            if !NotionSettings.shared.isConfigured {
                Text("Configure Notion in Settings to enable sync")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = syncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func syncToNotion() {
        isSyncing = true
        syncError = nil
        memo.syncState = .pending

        // Extract data on MainActor before passing to actor
        let syncData = MemoSyncData(
            title: memo.title,
            createdAt: memo.createdAt,
            transcriptText: memo.transcriptText,
            summaryText: memo.summaryText,
            decisions: memo.decisions,
            actionItems: memo.actionItems,
            existingPageId: memo.notionPageId
        )

        Task {
            do {
                let pageId = try await NotionService.shared.syncMemo(syncData)
                await MainActor.run {
                    memo.notionPageId = pageId
                    memo.syncState = .synced
                    memo.lastSyncError = nil
                }
            } catch {
                await MainActor.run {
                    syncError = error.localizedDescription
                    memo.syncState = .failed
                    memo.lastSyncError = error.localizedDescription
                }
            }
            await MainActor.run {
                isSyncing = false
            }
        }
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

                // Sync section
                SyncSection(memo: memo)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
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
