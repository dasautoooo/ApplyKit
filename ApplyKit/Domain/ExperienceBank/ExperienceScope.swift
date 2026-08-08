//
//  ExperienceScope.swift
//  ApplyKit
//
//  Visibility rules for application-scoped bullets and variants. A bullet the
//  tailoring clarify loop produced can either join the shared experience bank
//  (`owningApplicationID == nil`) or stay private to the application it was
//  recalled for. Scoped bullets live in `store.experiences` like any other and
//  render normally — only the surfaces that offer bullets for *reuse* filter
//  them out.
//

import Foundation

enum ExperienceScope {
    /// True when content owned by `owner` should be offered to `applicationID`.
    /// Shared content (`owner == nil`) is visible everywhere; scoped content only
    /// inside its own application (`applicationID == nil` means "a context with
    /// no application", such as the bank list or a master resume).
    static func isVisible(owner: UUID?, to applicationID: UUID?) -> Bool {
        guard let owner else { return true }
        return owner == applicationID
    }

    /// Bullets selectable from within one application: the shared bank plus the
    /// application's own private bullets.
    static func visible(_ experiences: [ExperienceBullet], to applicationID: UUID?) -> [ExperienceBullet] {
        experiences.filter { isVisible(owner: $0.owningApplicationID, to: applicationID) }
    }

    /// Bullets offered by contexts that have no owning application — the
    /// experience bank list and master resume editing.
    static func shared(_ experiences: [ExperienceBullet]) -> [ExperienceBullet] {
        experiences.filter { !$0.isApplicationScoped }
    }

    /// The private bullets belonging to one application, e.g. to delete them
    /// alongside it.
    static func owned(by applicationID: UUID, in experiences: [ExperienceBullet]) -> [ExperienceBullet] {
        experiences.filter { $0.owningApplicationID == applicationID }
    }
}
