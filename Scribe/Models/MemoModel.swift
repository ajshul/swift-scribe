import AVFoundation
import Foundation
import FoundationModels
import SwiftData
import SwiftUI

@Model
class Memo {
    var id: UUID
    var createdAt: Date
    var title: String
    var text: AttributedString
    var url: URL?
    var isDone: Bool
    var duration: TimeInterval?

    // Transcript (plain text for easier processing)
    var transcriptText: String?

    // AI-generated content (structured)
    var summaryText: String?
    var decisionsText: String?  // JSON array as string for persistence
    var actionItemsText: String?  // JSON array as string for persistence

    // Legacy field for AttributedString summary display
    var summary: AttributedString?

    // Notion sync
    var notionPageId: String?
    var syncStateRaw: String
    var lastSyncError: String?

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .notConnected }
        set { syncStateRaw = newValue.rawValue }
    }

    // Computed properties for structured data
    var decisions: [String] {
        get {
            guard let data = decisionsText?.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                decisionsText = String(data: data, encoding: .utf8)
            }
        }
    }

    var actionItems: [String] {
        get {
            guard let data = actionItemsText?.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                actionItemsText = String(data: data, encoding: .utf8)
            }
        }
    }

    init(
        title: String,
        text: AttributedString = AttributedString(""),
        url: URL? = nil,
        isDone: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.title = title
        self.text = text
        self.url = url
        self.isDone = isDone
        self.duration = duration
        self.syncStateRaw = SyncState.notConnected.rawValue
    }

    /// Generate AI title and structured notes from transcript.
    @MainActor
    func generateAIEnhancements() async throws {
        let service = SummarizationService.shared
        guard service.isAvailable else {
            throw SummarizationError.modelUnavailable
        }

        let transcript = transcriptText ?? String(text.characters)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.emptyTranscript
        }

        // Generate title
        if let newTitle = try? await service.generateTitle(from: transcript) {
            self.title = newTitle
        }

        // Generate structured notes
        let notes = try await service.generateMeetingNotes(from: transcript)

        self.summaryText = notes.summary
        self.decisions = notes.decisions
        self.actionItems = notes.actionItems

        // Also create markdown summary for display
        var markdown = notes.summary
        if !notes.decisions.isEmpty {
            markdown += "\n\n**Decisions:**\n"
            for decision in notes.decisions {
                markdown += "• \(decision)\n"
            }
        }
        if !notes.actionItems.isEmpty {
            markdown += "\n\n**Action Items:**\n"
            for item in notes.actionItems {
                markdown += "- [ ] \(item)\n"
            }
        }

        self.summary = try? AttributedString(markdown: markdown)
    }
}

extension Memo {
    static func blank() -> Memo {
        return .init(title: "New Memo", text: AttributedString(""))
    }

    func textBrokenUpByParagraphs() -> AttributedString {
        guard url != nil else { return text }

        var final = AttributedString("")
        var working = AttributedString("")
        let copy = text
        copy.runs.forEach { run in
            if copy[run.range].characters.contains(".") {
                working.append(copy[run.range])
                final.append(working)
                final.append(AttributedString("\n\n"))
                working = AttributedString("")
            } else {
                if working.characters.isEmpty {
                    let newText = copy[run.range].characters
                    let attributes = run.attributes
                    let trimmed = newText.trimmingPrefix(" ")
                    let newAttributed = AttributedString(trimmed, attributes: attributes)
                    working.append(newAttributed)
                } else {
                    working.append(copy[run.range])
                }
            }
        }

        return final.characters.isEmpty ? working : final
    }
}
