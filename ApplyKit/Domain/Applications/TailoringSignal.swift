//
//  TailoringSignal.swift
//  ApplyKit
//
//  The seven hiring signals a rewrite can improve, from
//  `references/output-and-validation.md`, each with what it actually means.
//
//  The skill's output contract names the signal in one or two words. On its own
//  "Technical depth" is a tag, not a reason — it says a category, not why the
//  change is worth making. The glosses are ApplyKit's, written from the skill's
//  own examples of sufficient reasoning, and are fixed text rather than model
//  output: what a signal means doesn't vary by application, so there is nothing
//  to be gained by asking for it every time.
//

import Foundation

enum TailoringSignal: String, CaseIterable {
    case relevance = "Relevance"
    case technicalDepth = "Technical depth"
    case impact = "Impact"
    case clarity = "Clarity"
    case atsTerminology = "ATS terminology"
    case concision = "Concision"
    case ownership = "Ownership"

    /// Matches the model's wording loosely — it returns the label as prose, and
    /// case or a stray article shouldn't lose the gloss.
    init?(loose text: String) {
        let key = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter }
        guard let match = TailoringSignal.allCases.first(where: {
            $0.rawValue.lowercased().filter(\.isLetter) == key
        }) else { return nil }
        self = match
    }

    /// What improving this signal does for the reader, in the skill's terms.
    var meaning: String {
        switch self {
        case .relevance:
            "puts what this posting screens for where a skim will find it"
        case .technicalDepth:
            "makes the mechanism visible, so the skill is evidenced rather than merely listed"
        case .impact:
            "leads with the outcome instead of the activity that produced it"
        case .clarity:
            "removes wording a reader would have to re-read to follow"
        case .atsTerminology:
            "swaps an internal phrase for the industry-standard term the posting uses"
        case .concision:
            "frees page budget for stronger material without losing evidence"
        case .ownership:
            "makes your own part in the work unambiguous, without overclaiming the team's"
        }
    }

    /// Every signal named in a reply, in the order they appear.
    ///
    /// The field is specified as exactly one, but replies routinely carry
    /// several — "Relevance | Technical depth | Ownership | Concision" — so
    /// they're all read rather than the whole string failing to match and
    /// losing every gloss.
    static func all(in raw: String) -> [TailoringSignal] {
        let parts = raw.split(whereSeparator: { "|,;/".contains($0) || $0.isNewline })
            .flatMap { $0.components(separatedBy: " and ") }
        var found: [TailoringSignal] = []
        for part in parts {
            guard let signal = TailoringSignal(loose: String(part)), !found.contains(signal) else { continue }
            found.append(signal)
        }
        return found
    }

    /// One "Signal — what it does for the reader" line per signal named. Falls
    /// back to the raw label when none is recognized, so an unfamiliar signal
    /// is shown rather than swallowed.
    static func descriptions(_ raw: String) -> [String] {
        let signals = all(in: raw)
        guard !signals.isEmpty else {
            let text = raw.trimmed
            return text.isEmpty ? [] : [text]
        }
        return signals.map { "\($0.rawValue) — \($0.meaning)" }
    }

    /// "Technical depth — makes the mechanism visible…", newline-separated when
    /// a reply names more than one.
    static func described(_ raw: String) -> String {
        descriptions(raw).joined(separator: "\n")
    }
}
