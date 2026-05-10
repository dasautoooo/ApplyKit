//
//  PromptTemplate.swift
//  ApplyKit
//

import Foundation

struct PromptTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var purposeRaw: String
    var templateText: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(name: String, purpose: PromptPurpose, templateText: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.purposeRaw = purpose.rawValue
        self.templateText = templateText
        self.isDefault = isDefault
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
