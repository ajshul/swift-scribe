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

    // AI-generated content
    var summary: AttributedString?
    var transcriptText: String?
    var summaryText: String?
    var decisionsText: String?
    var actionItemsText: String?

    // Notion sync
    var notionPageId: String?
    var syncStateRaw: String
    var lastSyncError: String?

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .notConnected }
        set { syncStateRaw = newValue.rawValue }
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

    func generateAIEnhancements() async throws {
        guard SystemLanguageModel.default.isAvailable else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "Foundation Models not available", code: -1))
        }

        let transcript = transcriptText ?? String(text.characters)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "No content to enhance", code: -2))
        }

        let titleResult = try? await generateEnhancedTitle(from: transcript)
        let summaryResult = try? await generateRichSummary(from: transcript)

        self.title = titleResult ?? title
        self.summary = summaryResult ?? AttributedString("Summary could not be generated.")
    }

    private func generateEnhancedTitle(from text: String) async throws -> String {
        let session = FoundationModelsHelper.createSession(
            instructions: """
                You are an expert at creating clear, descriptive titles for meeting transcripts.
                Create a concise, informative title that captures the main topic.
                Keep titles between 3-8 words. Use title case. Do not use quotes.
                """)

        let title = try await FoundationModelsHelper.generateText(
            session: session,
            prompt: "Create a title for this meeting transcript:\n\n\(text.prefix(2000))",
            options: FoundationModelsHelper.temperatureOptions(0.3)
        )
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func generateRichSummary(from text: String) async throws -> AttributedString {
        let session = FoundationModelsHelper.createSession(
            instructions: """
                You are a meeting notes assistant. Create a concise summary of the meeting.
                Include key points and important details. Output in markdown format.
                Keep it to 2-4 paragraphs.
                """)

        let summaryText = try await FoundationModelsHelper.generateText(
            session: session,
            prompt: "Summarize this meeting transcript:\n\n\(text)",
            options: FoundationModelsHelper.temperatureOptions(0.4)
        )

        self.summaryText = summaryText
        return try AttributedString(markdown: summaryText)
    }

    func suggestedTitle() async throws -> String? {
        let transcript = transcriptText ?? String(text.characters)
        return try await generateEnhancedTitle(from: transcript)
    }

    func summarize(using template: String) async throws -> AttributedString? {
        let transcript = transcriptText ?? String(text.characters)
        return try await generateRichSummary(from: transcript)
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
