import Foundation
import FoundationModels

/// Structured meeting notes output
@Generable
struct MeetingNotes {
    @Guide(description: "A concise 2-4 sentence summary of the meeting's main topics and outcomes")
    let summary: String

    @Guide(description: "Key decisions made during the meeting, as a list")
    let decisions: [String]

    @Guide(description: "Action items identified, including owner if mentioned")
    let actionItems: [String]
}

@MainActor
final class SummarizationService {
    static let shared = SummarizationService()

    private init() {}

    /// Check if the Foundation Models framework is available on this device.
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Generate structured meeting notes from a transcript.
    func generateMeetingNotes(from transcript: String) async throws -> MeetingNotes {
        guard isAvailable else {
            throw SummarizationError.modelUnavailable
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.emptyTranscript
        }

        let session = LanguageModelSession(instructions: """
            You are a meeting notes assistant. Given a meeting transcript, extract:
            1. A concise summary (2-4 sentences covering the main topics)
            2. Key decisions made (as a list; empty if none)
            3. Action items with owners if mentioned (as a list; empty if none)

            Be factual and concise. Only include information present in the transcript.
            """)

        let prompt = "Extract meeting notes from this transcript:\n\n\(transcript)"

        do {
            let response = try await session.respond(
                to: prompt,
                generating: MeetingNotes.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return response.content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Retry with truncated transcript
            let truncated = String(transcript.prefix(4000))
            let response = try await session.respond(
                to: "Extract meeting notes from this transcript:\n\n\(truncated)",
                generating: MeetingNotes.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return response.content
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw SummarizationError.unsupportedLanguage
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            throw SummarizationError.contentFiltered
        } catch {
            throw SummarizationError.generationFailed(error)
        }
    }

    /// Generate a title from a transcript.
    func generateTitle(from transcript: String) async throws -> String {
        guard isAvailable else {
            throw SummarizationError.modelUnavailable
        }

        let session = LanguageModelSession(instructions: """
            Create a concise meeting title (3-8 words) that captures the main topic.
            Use title case. Do not use quotes. Be specific.
            """)

        let response = try await session.respond(
            to: "Create a title for this meeting:\n\n\(transcript.prefix(1500))",
            options: GenerationOptions(temperature: 0.3)
        )

        return response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }
}

enum SummarizationError: LocalizedError {
    case modelUnavailable
    case emptyTranscript
    case unsupportedLanguage
    case contentFiltered
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "AI summarization is not available on this device. Enable Apple Intelligence in Settings."
        case .emptyTranscript:
            return "No content to summarize."
        case .unsupportedLanguage:
            return "The current language is not supported for AI summarization."
        case .contentFiltered:
            return "The content could not be summarized due to content guidelines."
        case .generationFailed(let error):
            return "Failed to generate summary: \(error.localizedDescription)"
        }
    }
}
