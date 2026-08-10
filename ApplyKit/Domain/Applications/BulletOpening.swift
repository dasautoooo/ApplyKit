//
//  BulletOpening.swift
//  ApplyKit
//
//  Catches the one rewrite the skill's rules keep failing to prevent: replacing
//  a bullet that opens with a *result* by one that opens with the *activity*.
//
//  `references/tailoring-principles.md` allows action-first wording — when the
//  outcome is qualitative, needs too much setup, or the engineering action is
//  the more distinctive signal. What it does not allow is trading away an
//  opening result the bullet already had. The prompts say so twice, and models
//  still do it, usually justified as "technical depth". So it is checked here
//  rather than only asked for: the rewrite is still offered, with the downgrade
//  named, and the candidate decides.
//

import Foundation

enum BulletOpening {
    /// Verbs that state what changed for the business or the system.
    private static let outcomeVerbs: Set<String> = [
        "accelerated", "boosted", "cut", "decreased", "delivered", "doubled", "drove", "eliminated",
        "enabled", "eradicated", "grew", "halved", "improved", "increased", "lowered", "made",
        "prevented", "raised", "recovered", "reduced", "removed", "restored", "saved", "shortened",
        "shrank", "slashed", "sped", "stopped", "sustained", "tripled", "unblocked", "unlocked"
    ]

    /// Verbs that state what was worked on. Fine as an opening in their own
    /// right — the skill permits action-first — but a step down from a result.
    private static let activityVerbs: Set<String> = [
        "added", "architected", "authored", "automated", "built", "configured", "constructed",
        "created", "designed", "developed", "engineered", "established", "expanded", "extended",
        "implemented", "instrumented", "integrated", "introduced", "led", "maintained", "managed",
        "migrated", "modernized", "owned", "ported", "prototyped", "rearchitected", "rebuilt",
        "refactored", "rewrote", "set", "shipped", "supported", "wrote"
    ]

    static func firstWord(_ text: String) -> String {
        text.trimmed
            .split(whereSeparator: { !$0.isLetter })
            .first
            .map { $0.lowercased() } ?? ""
    }

    static func opensWithOutcome(_ text: String) -> Bool { outcomeVerbs.contains(firstWord(text)) }
    static func opensWithActivity(_ text: String) -> Bool { activityVerbs.contains(firstWord(text)) }

    /// Non-nil when `proposed` gives up an opening result that `current` had.
    ///
    /// Deliberately narrow: it fires only when the current wording opens with a
    /// recognized outcome verb and the replacement opens with a recognized
    /// activity verb. Anything less clear-cut is left alone rather than
    /// nagging about rewrites that are fine.
    static func downgradeWarning(current: String, proposed: String) -> String? {
        guard opensWithOutcome(current), opensWithActivity(proposed) else { return nil }
        return "This opens with what was built (“\(firstWord(proposed))…”) where the current wording opens with "
            + "the result (“\(firstWord(current))…”). The skill keeps a result in the opening when the bullet "
            + "already has one — check this isn't a downgrade before applying."
    }
}
