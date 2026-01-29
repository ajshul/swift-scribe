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

                SyncBadge(state: .notConnected)
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

            if !memo.text.characters.isEmpty {
                Text(String(memo.text.characters.prefix(80)))
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

// MARK: - Placeholder Detail View

struct MemoDetailView: View {
    let memo: Memo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary section
                if let summary = memo.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Summary", systemImage: "sparkles")
                            .font(.headline)
                        Text(summary)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                // Transcript section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcript", systemImage: "doc.plaintext")
                        .font(.headline)

                    if memo.text.characters.isEmpty {
                        Text("No transcript available")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(memo.textBrokenUpByParagraphs())
                            .font(.body)
                            .textSelection(.enabled)
                    }
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
}

// MARK: - Placeholder Review Notes View

struct ReviewNotesView: View {
    let memo: Memo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Review Notes")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    Label("Summary", systemImage: "sparkles")
                        .font(.headline)
                    if let summary = memo.summary {
                        Text(summary)
                    } else {
                        Text("Summary will appear here after processing.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Transcript
                DisclosureGroup {
                    if memo.text.characters.isEmpty {
                        Text("No transcript available")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(memo.textBrokenUpByParagraphs())
                            .font(.body)
                            .textSelection(.enabled)
                    }
                } label: {
                    Label("Transcript", systemImage: "doc.plaintext")
                        .font(.headline)
                }
                .padding(.horizontal)

                // Sync button placeholder
                Button {
                    // TODO: Wire Notion sync
                } label: {
                    Label("Sync to Notion", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.36, green: 0.69, blue: 0.55))
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(memo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
