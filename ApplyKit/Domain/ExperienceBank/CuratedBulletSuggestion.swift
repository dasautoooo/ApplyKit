import Foundation

enum CuratedAddedState: String, Codable {
    case none
    case resume
    case bankOnly
}

struct CuratedBulletSuggestion: Identifiable, Codable {
    var id = UUID()
    var bulletText: String
    var relevance: String
    var howToLearn: String
    var story: String
    /// Non-nil when this is a rewrite of an existing bullet rather than a new one.
    var sourceBulletID: UUID?
    var sourceBulletTitle: String?
    var addedState: CuratedAddedState = .none
    /// The bullet ID added to the experience bank (new bullet, or parent bullet for variations).
    var addedBulletID: UUID?
    /// The variant ID added to the parent bullet (variations only).
    var addedVariantID: UUID?

    var isVariation: Bool { sourceBulletID != nil }
    var isAddedToBank: Bool { addedBulletID != nil }

    enum CodingKeys: String, CodingKey {
        case id, bulletText, relevance, howToLearn, story
        case sourceBulletID, sourceBulletTitle, addedState
        case addedBulletID, addedVariantID
    }

    init(id: UUID = UUID(), bulletText: String, relevance: String, howToLearn: String, story: String,
         sourceBulletID: UUID? = nil, sourceBulletTitle: String? = nil,
         addedState: CuratedAddedState = .none, addedBulletID: UUID? = nil, addedVariantID: UUID? = nil) {
        self.id = id; self.bulletText = bulletText; self.relevance = relevance
        self.howToLearn = howToLearn; self.story = story
        self.sourceBulletID = sourceBulletID; self.sourceBulletTitle = sourceBulletTitle
        self.addedState = addedState
        self.addedBulletID = addedBulletID; self.addedVariantID = addedVariantID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bulletText = try c.decode(String.self, forKey: .bulletText)
        relevance = try c.decodeIfPresent(String.self, forKey: .relevance) ?? ""
        howToLearn = try c.decodeIfPresent(String.self, forKey: .howToLearn) ?? ""
        story = try c.decodeIfPresent(String.self, forKey: .story) ?? ""
        sourceBulletID = try c.decodeIfPresent(UUID.self, forKey: .sourceBulletID)
        sourceBulletTitle = try c.decodeIfPresent(String.self, forKey: .sourceBulletTitle)
        addedState = try c.decodeIfPresent(CuratedAddedState.self, forKey: .addedState) ?? .none
        addedBulletID = try c.decodeIfPresent(UUID.self, forKey: .addedBulletID)
        addedVariantID = try c.decodeIfPresent(UUID.self, forKey: .addedVariantID)
    }
}
