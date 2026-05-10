//
//  CoverLetterRenderer.swift
//  ApplyKit
//

import Foundation

struct CoverLetterDraft: Codable {
    var recipientLines: [String]
    var salutation: String
    var paragraphs: [String]
    var closing: String

    enum CodingKeys: String, CodingKey {
        case recipientLines = "recipient_lines"
        case salutation
        case paragraphs
        case closing
    }
}

enum CoverLetterRenderer {
    static let recipientPlaceholder = "{{APPLYKIT_RECIPIENT}}"
    static let salutationPlaceholder = "{{APPLYKIT_SALUTATION}}"
    static let bodyPlaceholder = "{{APPLYKIT_BODY}}"
    static let closingPlaceholder = "{{APPLYKIT_CLOSING}}"

    static func render(template: String, draft: CoverLetterDraft, application: JobApplication) -> String {
        let recipient = normalizedRecipientLines(draft.recipientLines, application: application)
            .map(ResumeRenderer.escapeLatex)
            .joined(separator: " \\\\ ")
        let salutation = normalizedSalutation(draft.salutation)
        let closing = draft.closing.trimmed.isEmpty ? "Sincerely," : draft.closing.trimmed
        let body = draft.paragraphs
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .map(ResumeRenderer.escapeLatex)
            .joined(separator: "\n\n")

        return template
            .replacingOccurrences(of: recipientPlaceholder, with: recipient)
            .replacingOccurrences(of: salutationPlaceholder, with: ResumeRenderer.escapeLatex(salutation))
            .replacingOccurrences(of: bodyPlaceholder, with: body.isEmpty ? "% No cover letter body generated." : body)
            .replacingOccurrences(of: closingPlaceholder, with: ResumeRenderer.escapeLatex(closing))
    }

    static func parseDraft(from response: String) throws -> CoverLetterDraft {
        let cleaned = stripCodeFence(response)
        let jsonText = extractJSONObject(from: cleaned)
        guard let data = jsonText.data(using: .utf8) else {
            throw WorkflowError.invalidAIResponse("The AI response was not valid UTF-8.")
        }
        let draft = try JSONDecoder().decode(CoverLetterDraft.self, from: data)
        guard !draft.paragraphs.map(\.trimmed).filter({ !$0.isEmpty }).isEmpty else {
            throw WorkflowError.invalidAIResponse("The AI response did not include cover letter paragraphs.")
        }
        return draft
    }

    private static func normalizedRecipientLines(_ lines: [String], application: JobApplication) -> [String] {
        let cleaned = lines.map(\.trimmed).filter { !$0.isEmpty }
        if !cleaned.isEmpty {
            return cleaned
        }
        return ["Hiring Manager", application.companyName.trimmed].filter { !$0.isEmpty }
    }

    private static func normalizedSalutation(_ value: String) -> String {
        var salutation = value.trimmed
        if salutation.isEmpty {
            salutation = "Dear Hiring Manager,"
        }
        if !salutation.hasSuffix(",") && !salutation.hasSuffix(":") {
            salutation += ","
        }
        return salutation
    }

    private static func stripCodeFence(_ value: String) -> String {
        let trimmed = value.trimmed
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmed == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmed
    }

    private static func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }
}
