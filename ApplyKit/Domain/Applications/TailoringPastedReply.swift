//
//  TailoringPastedReply.swift
//  ApplyKit
//
//  What the reconciler pulls out of a tailoring reply pasted from ChatGPT.
//
//  The paste path used to extract only the edits, so everything the reply
//  judged — fit, priority, investment, the candidate story, strong matches,
//  gaps — was read and discarded. For anyone working mostly in ChatGPT that
//  emptied the brief panel: no score, no gaps, nothing but a change list.
//

import Foundation

struct TailoringPastedReply: Decodable, Equatable {
    /// The reply's judgment, in the shape Stage 1 would have produced.
    var brief: TailoringBrief?
    /// The edits to apply.
    var plan: TailoringPlan?

    var isEmpty: Bool { brief?.hasContent != true && plan?.isEmpty != false }

    private enum CodingKeys: String, CodingKey { case brief }

    init(brief: TailoringBrief? = nil, plan: TailoringPlan? = nil) {
        self.brief = brief
        self.plan = plan
    }

    /// The judgment is nested under `brief`; the edits are the top-level object
    /// itself. Keeping the plan flat means a reply in the older shape — bare
    /// plan, no judgment — still decodes without a fallback path.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brief = try? container.decodeIfPresent(TailoringBrief.self, forKey: .brief)
        let plan = try? TailoringPlan(from: decoder)
        self.plan = (plan?.isEmpty == false) ? plan : nil
    }

    static func parse(from response: String) -> TailoringPastedReply? {
        guard let decoded = AIJSONResponse.decodeObject(TailoringPastedReply.self, from: response),
              !decoded.isEmpty else { return nil }
        return decoded
    }
}

extension TailoringBrief {
    /// Takes the judgment from a pasted reply while keeping everything the
    /// candidate has done in the app.
    ///
    /// Questions, answers, recalled facts, build notes and the clarify count
    /// are the candidate's own work — a pasted reply knows nothing about them,
    /// so pasting one must not silently erase them. Judgment fields are
    /// overwritten only when the reply actually carries them.
    func merging(judgmentFrom reply: TailoringBrief) -> TailoringBrief {
        var merged = self
        if let score = reply.fitScore { merged.fitScore = score }
        if let confidence = reply.fitConfidence?.trimmed, !confidence.isEmpty { merged.fitConfidence = confidence }
        if let priority = reply.recommendedPriority?.trimmed, !priority.isEmpty { merged.recommendedPriority = priority }
        if let tier = reply.investmentTier?.trimmed, !tier.isEmpty { merged.investmentTier = tier }
        if let time = reply.investmentTime?.trimmed, !time.isEmpty { merged.investmentTime = time }
        if let rationale = reply.effortRationale?.trimmed, !rationale.isEmpty { merged.effortRationale = rationale }
        if let story = reply.candidateStory?.trimmed, !story.isEmpty { merged.candidateStory = story }
        if !reply.strongMatches.isEmpty { merged.strongMatches = reply.strongMatches }
        if !reply.gaps.isEmpty { merged.gaps = reply.gaps }
        if reply.plan.hasContent { merged.plan = reply.plan }
        if let notes = reply.researchNotes, !notes.isEmpty { merged.researchNotes = notes }
        merged.generatedAt = Date()
        return merged
    }
}
